// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TitanToken.sol";
import "../src/Farm.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock LP Token for testing
contract MockLPToken is ERC20 {
    constructor() ERC20("Mock LP", "MLP") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FarmTest is Test {
    TitanToken public titanToken;
    Farm public farm;
    MockLPToken public lpToken1;
    MockLPToken public lpToken2;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant TITAN_PER_SECOND = 1e18; // 1 TITAN per second
    uint256 public constant REWARD_POOL = 10_000_000 * 10 ** 18;
    uint256 public constant USER_LP_BALANCE = 10_000 * 10 ** 18;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint, bool isActive);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);

        titanToken = new TitanToken(owner);
        farm = new Farm(address(titanToken), TITAN_PER_SECOND, owner);

        lpToken1 = new MockLPToken();
        lpToken2 = new MockLPToken();

        // Fund farm with rewards
        titanToken.transfer(address(farm), REWARD_POOL);

        // Give users LP tokens
        lpToken1.transfer(user1, USER_LP_BALANCE);
        lpToken1.transfer(user2, USER_LP_BALANCE);
        lpToken2.transfer(user1, USER_LP_BALANCE);
        lpToken2.transfer(user2, USER_LP_BALANCE);

        vm.stopPrank();

        // Users approve farm
        vm.prank(user1);
        lpToken1.approve(address(farm), type(uint256).max);
        vm.prank(user1);
        lpToken2.approve(address(farm), type(uint256).max);

        vm.prank(user2);
        lpToken1.approve(address(farm), type(uint256).max);
        vm.prank(user2);
        lpToken2.approve(address(farm), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectToken() public view {
        assertEq(address(farm.titanToken()), address(titanToken));
    }

    function test_Constructor_SetsCorrectTitanPerSecond() public view {
        assertEq(farm.titanPerSecond(), TITAN_PER_SECOND);
    }

    function test_Constructor_SetsCorrectOwner() public view {
        assertEq(farm.owner(), owner);
    }

    function test_Constructor_RevertsIfZeroTokenAddress() public {
        vm.expectRevert(Farm.InvalidToken.selector);
        new Farm(address(0), TITAN_PER_SECOND, owner);
    }

    // ============ Add Pool Tests ============

    function test_AddPool_CreatesPool() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        assertEq(farm.poolLength(), 1);
        assertEq(farm.totalAllocPoint(), 100);
    }

    function test_AddPool_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit PoolAdded(0, address(lpToken1), 100);

        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);
    }

    function test_AddPool_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        farm.addPool(100, address(lpToken1), false);
    }

    function test_AddPool_RevertsIfZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Farm.InvalidLPToken.selector);
        farm.addPool(100, address(0), false);
    }

    function test_AddPool_RevertsIfDuplicateLPToken() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.expectRevert(Farm.LPTokenAlreadyAdded.selector);
        farm.addPool(100, address(lpToken1), false);
        vm.stopPrank();
    }

    function test_AddPool_RevertsIfMaxPoolsReached() public {
        vm.startPrank(owner);

        // Add 100 pools (MAX_POOLS)
        for (uint256 i = 0; i < 100; i++) {
            MockLPToken newLp = new MockLPToken();
            farm.addPool(100, address(newLp), false);
        }

        // Try to add one more
        MockLPToken extraLp = new MockLPToken();
        vm.expectRevert(Farm.TooManyPools.selector);
        farm.addPool(100, address(extraLp), false);

        vm.stopPrank();
    }

    function test_AddPool_MultiplePools() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);
        farm.addPool(200, address(lpToken2), false);
        vm.stopPrank();

        assertEq(farm.poolLength(), 2);
        assertEq(farm.totalAllocPoint(), 300);
    }

    // ============ Set Pool Tests ============

    function test_SetPool_UpdatesAllocPoint() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);
        farm.setPool(0, 200, true, false);
        vm.stopPrank();

        assertEq(farm.totalAllocPoint(), 200);
    }

    function test_SetPool_CanDeactivatePool() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);
        farm.setPool(0, 100, false, false);
        vm.stopPrank();

        (, , , , , bool isActive) = farm.poolInfo(0);
        assertFalse(isActive);
    }

    function test_SetPool_RevertsIfInvalidPid() public {
        vm.prank(owner);
        vm.expectRevert(Farm.InvalidPoolId.selector);
        farm.setPool(0, 100, true, false);
    }

    // ============ Deposit Tests ============

    function test_Deposit_UpdatesUserInfo() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        (uint256 amount, ) = farm.userInfo(0, user1);
        assertEq(amount, 1000 * 10 ** 18);
    }

    function test_Deposit_EmitsEvent() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, 0, 1000 * 10 ** 18);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);
    }

    function test_Deposit_TransfersLPTokens() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        uint256 balanceBefore = lpToken1.balanceOf(user1);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        assertEq(lpToken1.balanceOf(user1), balanceBefore - 1000 * 10 ** 18);
        assertEq(lpToken1.balanceOf(address(farm)), 1000 * 10 ** 18);
    }

    function test_Deposit_RevertsIfInactivePool() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);
        farm.setPool(0, 100, false, false);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(Farm.PoolNotActive.selector);
        farm.deposit(0, 1000 * 10 ** 18);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw_UpdatesUserInfo() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.prank(user1);
        farm.withdraw(0, 400 * 10 ** 18);

        (uint256 amount, ) = farm.userInfo(0, user1);
        assertEq(amount, 600 * 10 ** 18);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.expectEmit(true, true, false, true);
        emit Withdraw(user1, 0, 400 * 10 ** 18);

        vm.prank(user1);
        farm.withdraw(0, 400 * 10 ** 18);
    }

    function test_Withdraw_RevertsIfInsufficientBalance() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.prank(user1);
        vm.expectRevert(Farm.InsufficientBalance.selector);
        farm.withdraw(0, 2000 * 10 ** 18);
    }

    // ============ Pending Rewards Tests ============

    function test_PendingTitan_ReturnsCorrectAmount() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 100);

        uint256 pending = farm.pendingTitan(0, user1);
        // With 1 TITAN per second for 100 seconds
        assertEq(pending, 100 * 10 ** 18);
    }

    function test_PendingTitan_MultipleUsers() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.prank(user2);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 100);

        uint256 pending1 = farm.pendingTitan(0, user1);
        uint256 pending2 = farm.pendingTitan(0, user2);

        // Each user gets half
        assertEq(pending1, 50 * 10 ** 18);
        assertEq(pending2, 50 * 10 ** 18);
    }

    // ============ Harvest Tests ============

    function test_Harvest_TransfersRewards() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 100);

        uint256 balanceBefore = titanToken.balanceOf(user1);

        vm.prank(user1);
        farm.harvest(0);

        assertEq(titanToken.balanceOf(user1), balanceBefore + 100 * 10 ** 18);
    }

    function test_Harvest_EmitsEvent() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 100);

        vm.expectEmit(true, true, false, true);
        emit Harvest(user1, 0, 100 * 10 ** 18);

        vm.prank(user1);
        farm.harvest(0);
    }

    function test_Harvest_RevertsIfNothingToHarvest() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.prank(user1);
        vm.expectRevert(Farm.NothingToHarvest.selector);
        farm.harvest(0);
    }

    // ============ Emergency Withdraw Tests ============

    function test_EmergencyWithdraw_ReturnsLPTokens() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 100);

        uint256 balanceBefore = lpToken1.balanceOf(user1);

        vm.prank(user1);
        farm.emergencyWithdraw(0);

        assertEq(lpToken1.balanceOf(user1), balanceBefore + 1000 * 10 ** 18);
        (uint256 amount, ) = farm.userInfo(0, user1);
        assertEq(amount, 0);
    }

    // ============ Multiple Pools Tests ============

    function test_MultiplePools_CorrectRewardDistribution() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false); // 1/3 of rewards
        farm.addPool(200, address(lpToken2), false); // 2/3 of rewards
        vm.stopPrank();

        vm.startPrank(user1);
        farm.deposit(0, 1000 * 10 ** 18);
        farm.deposit(1, 1000 * 10 ** 18);
        vm.stopPrank();

        vm.warp(block.timestamp + 300);

        uint256 pending0 = farm.pendingTitan(0, user1);
        uint256 pending1 = farm.pendingTitan(1, user1);

        // Pool 0 should get ~100 TITAN (1/3 of 300)
        // Pool 1 should get ~200 TITAN (2/3 of 300)
        assertEq(pending0, 100 * 10 ** 18);
        assertEq(pending1, 200 * 10 ** 18);
    }

    // ============ Set Titan Per Second Tests ============

    function test_SetTitanPerSecond_UpdatesRate() public {
        vm.prank(owner);
        farm.setTitanPerSecond(2e18);

        assertEq(farm.titanPerSecond(), 2e18);
    }

    function test_SetTitanPerSecond_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        farm.setTitanPerSecond(2e18);
    }

    // ============ Emergency Reward Withdraw Tests ============

    function test_EmergencyRewardWithdraw_OnlyOwner() public {
        vm.prank(owner);
        farm.emergencyRewardWithdraw(1000 * 10 ** 18);

        assertEq(titanToken.balanceOf(owner), 100_000_000 * 10 ** 18 - REWARD_POOL + 1000 * 10 ** 18);
    }

    function test_EmergencyRewardWithdraw_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        farm.emergencyRewardWithdraw(1000 * 10 ** 18);
    }

    function test_EmergencyRewardWithdraw_RevertsIfInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(Farm.InsufficientRewardBalance.selector);
        farm.emergencyRewardWithdraw(REWARD_POOL + 1);
    }

    // ============ Deposit Rewards Tests ============

    function test_DepositRewards() public {
        vm.prank(owner);
        titanToken.approve(address(farm), 1000 * 10 ** 18);

        vm.prank(owner);
        farm.depositRewards(1000 * 10 ** 18);

        assertEq(titanToken.balanceOf(address(farm)), REWARD_POOL + 1000 * 10 ** 18);
    }

    // ============ Additional Branch Coverage Tests ============

    function test_AddPool_WithMassUpdate() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);

        // Add second pool WITH update
        farm.addPool(200, address(lpToken2), true);
        vm.stopPrank();

        assertEq(farm.poolLength(), 2);
        assertEq(farm.totalAllocPoint(), 300);
    }

    function test_SetPool_WithMassUpdate() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);

        // Set pool WITH update
        farm.setPool(0, 200, true, true);
        vm.stopPrank();

        assertEq(farm.totalAllocPoint(), 200);
    }

    function test_UpdatePool_WhenTimestampNotElapsed() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        // Call updatePool twice in same block - second call should return early
        farm.updatePool(0);
        farm.updatePool(0);

        // Should not revert
        assertTrue(true);
    }

    function test_UpdatePool_WhenNoLpSupply() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.warp(block.timestamp + 100);

        // Update pool with no LP staked
        farm.updatePool(0);

        // Should update lastRewardTime but not accTitanPerShare
        (, , uint256 lastRewardTime, uint256 accTitanPerShare, , ) = farm.poolInfo(0);
        assertEq(lastRewardTime, block.timestamp);
        assertEq(accTitanPerShare, 0);
    }

    function test_UpdatePool_WhenPoolInactive() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);
        vm.stopPrank();

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.prank(owner);
        farm.setPool(0, 100, false, false); // Deactivate

        vm.warp(block.timestamp + 100);

        farm.updatePool(0);

        // Should update lastRewardTime but not distribute rewards
        (, , uint256 lastRewardTime, , , ) = farm.poolInfo(0);
        assertEq(lastRewardTime, block.timestamp);
    }

    function test_UpdatePool_WhenTotalAllocPointZero() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);
        vm.stopPrank();

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.prank(owner);
        farm.setPool(0, 0, true, false); // Set allocPoint to 0

        vm.warp(block.timestamp + 100);

        farm.updatePool(0);

        (, , uint256 lastRewardTime, , , ) = farm.poolInfo(0);
        assertEq(lastRewardTime, block.timestamp);
    }

    function test_Deposit_ZeroAmount() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 100);

        // Deposit 0 should still harvest pending rewards
        uint256 balanceBefore = titanToken.balanceOf(user1);

        vm.prank(user1);
        farm.deposit(0, 0);

        assertGt(titanToken.balanceOf(user1), balanceBefore);
    }

    function test_Withdraw_ZeroAmountHarvestsRewards() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 100);

        uint256 balanceBefore = titanToken.balanceOf(user1);

        // Withdraw 0 should still harvest rewards
        vm.prank(user1);
        farm.withdraw(0, 0);

        assertGt(titanToken.balanceOf(user1), balanceBefore);
    }

    function test_SafeTitanTransfer_WhenAmountExceedsBalance() public {
        // Create farm with very little rewards
        Farm smallFarm = new Farm(address(titanToken), TITAN_PER_SECOND, owner);

        vm.startPrank(owner);
        titanToken.transfer(address(smallFarm), 10 * 10 ** 18); // Only 10 TITAN
        smallFarm.addPool(100, address(lpToken1), false);
        vm.stopPrank();

        vm.prank(user1);
        lpToken1.approve(address(smallFarm), type(uint256).max);

        vm.prank(user1);
        smallFarm.deposit(0, 1000 * 10 ** 18);

        vm.warp(block.timestamp + 1000); // Earn more than available

        uint256 pending = smallFarm.pendingTitan(0, user1);
        assertGt(pending, 10 * 10 ** 18); // Should be more than balance

        uint256 balanceBefore = titanToken.balanceOf(user1);

        vm.prank(user1);
        smallFarm.harvest(0);

        // Should receive only the available balance
        assertEq(titanToken.balanceOf(user1), balanceBefore + 10 * 10 ** 18);
    }

    function test_PendingTitan_RevertsIfInvalidPid() public {
        vm.expectRevert(Farm.InvalidPoolId.selector);
        farm.pendingTitan(0, user1);
    }

    function test_Deposit_RevertsIfInvalidPid() public {
        vm.prank(user1);
        vm.expectRevert(Farm.InvalidPoolId.selector);
        farm.deposit(999, 1000 * 10 ** 18);
    }

    function test_Withdraw_RevertsIfInvalidPid() public {
        vm.prank(user1);
        vm.expectRevert(Farm.InvalidPoolId.selector);
        farm.withdraw(999, 1000 * 10 ** 18);
    }

    function test_Harvest_RevertsIfInvalidPid() public {
        vm.prank(user1);
        vm.expectRevert(Farm.InvalidPoolId.selector);
        farm.harvest(999);
    }

    function test_EmergencyWithdraw_RevertsIfInvalidPid() public {
        vm.prank(user1);
        vm.expectRevert(Farm.InvalidPoolId.selector);
        farm.emergencyWithdraw(999);
    }

    function test_UpdatePool_RevertsIfInvalidPid() public {
        vm.expectRevert(Farm.InvalidPoolId.selector);
        farm.updatePool(999);
    }

    function test_MassUpdatePools_UpdatesAllPools() public {
        vm.startPrank(owner);
        farm.addPool(100, address(lpToken1), false);
        farm.addPool(200, address(lpToken2), false);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        farm.massUpdatePools();

        (, , uint256 lastRewardTime1, , , ) = farm.poolInfo(0);
        (, , uint256 lastRewardTime2, , , ) = farm.poolInfo(1);

        assertEq(lastRewardTime1, block.timestamp);
        assertEq(lastRewardTime2, block.timestamp);
    }

    function test_PendingTitan_WhenNoTimeElapsed() public {
        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, 1000 * 10 ** 18);

        // No time warp - pending should be 0
        uint256 pending = farm.pendingTitan(0, user1);
        assertEq(pending, 0);
    }

    function test_PoolLength() public {
        assertEq(farm.poolLength(), 0);

        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        assertEq(farm.poolLength(), 1);
    }

    function test_AvailableRewardBalance() public view {
        assertEq(farm.availableRewardBalance(), REWARD_POOL);
    }

    // ============ Fuzz Tests ============

    function testFuzz_Deposit_VariousAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= USER_LP_BALANCE);

        vm.prank(owner);
        farm.addPool(100, address(lpToken1), false);

        vm.prank(user1);
        farm.deposit(0, amount);

        (uint256 userAmount, ) = farm.userInfo(0, user1);
        assertEq(userAmount, amount);
    }
}
