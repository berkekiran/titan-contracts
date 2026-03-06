// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TitanToken.sol";
import "../src/StakedTitan.sol";

contract StakedTitanTest is Test {
    TitanToken public titan;
    StakedTitan public sTitan;

    address public owner;
    address public user1;
    address public user2;
    address public rewardDistributor;

    uint256 public constant INITIAL_BALANCE = 10_000 * 10 ** 18;

    event Deposited(address indexed user, uint256 titanAmount, uint256 sTitanAmount);
    event Withdrawn(address indexed user, uint256 sTitanAmount, uint256 titanAmount);
    event RewardsAdded(address indexed from, uint256 amount, uint256 newExchangeRate);
    event DepositsPausedChanged(bool paused);
    event WithdrawalsPausedChanged(bool paused);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        rewardDistributor = makeAddr("rewardDistributor");

        vm.startPrank(owner);

        titan = new TitanToken(owner);
        sTitan = new StakedTitan(address(titan), owner);

        // Distribute tokens
        titan.transfer(user1, INITIAL_BALANCE);
        titan.transfer(user2, INITIAL_BALANCE);
        titan.transfer(rewardDistributor, INITIAL_BALANCE * 10);

        vm.stopPrank();

        // Users approve sTitan contract
        vm.prank(user1);
        titan.approve(address(sTitan), type(uint256).max);

        vm.prank(user2);
        titan.approve(address(sTitan), type(uint256).max);

        vm.prank(rewardDistributor);
        titan.approve(address(sTitan), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectName() public view {
        assertEq(sTitan.name(), "Staked Titan");
    }

    function test_Constructor_SetsCorrectSymbol() public view {
        assertEq(sTitan.symbol(), "sTitan");
    }

    function test_Constructor_SetsCorrectTitan() public view {
        assertEq(address(sTitan.titan()), address(titan));
    }

    function test_Constructor_SetsCorrectOwner() public view {
        assertEq(sTitan.owner(), owner);
    }

    function test_Constructor_RevertsIfZeroToken() public {
        vm.expectRevert(StakedTitan.InvalidToken.selector);
        new StakedTitan(address(0), owner);
    }

    // ============ Exchange Rate Tests ============

    function test_ExchangeRate_InitiallyOne() public view {
        assertEq(sTitan.exchangeRate(), 1e18);
    }

    function test_ExchangeRate_StaysOneAfterFirstDeposit() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        assertEq(sTitan.exchangeRate(), 1e18);
    }

    function test_ExchangeRate_IncreasesWithRewards() public {
        // User deposits 1000 TITAN
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // Add 100 TITAN as rewards (10%)
        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        // Exchange rate should be 1.1
        assertEq(sTitan.exchangeRate(), 1.1e18);
    }

    // ============ Deposit Tests ============

    function test_Deposit_MintsCorrectSTitan() public {
        vm.prank(user1);
        uint256 sTitanReceived = sTitan.deposit(1000 * 10 ** 18);

        assertEq(sTitanReceived, 1000 * 10 ** 18);
        assertEq(sTitan.balanceOf(user1), 1000 * 10 ** 18);
    }

    function test_Deposit_TransfersTitan() public {
        uint256 balanceBefore = titan.balanceOf(user1);

        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        assertEq(titan.balanceOf(user1), balanceBefore - 1000 * 10 ** 18);
        assertEq(titan.balanceOf(address(sTitan)), 1000 * 10 ** 18);
    }

    function test_Deposit_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Deposited(user1, 1000 * 10 ** 18, 1000 * 10 ** 18);

        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);
    }

    function test_Deposit_WithExistingRewards() public {
        // User1 deposits 1000 TITAN
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // Add 100 TITAN rewards
        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        // User2 deposits 1100 TITAN (should get ~1000 sTitan at 1.1 rate)
        vm.prank(user2);
        uint256 sTitanReceived = sTitan.deposit(1100 * 10 ** 18);

        assertEq(sTitanReceived, 1000 * 10 ** 18);
    }

    function test_Deposit_RevertsIfZero() public {
        vm.prank(user1);
        vm.expectRevert(StakedTitan.ZeroAmount.selector);
        sTitan.deposit(0);
    }

    function test_Deposit_RevertsIfTooSmall() public {
        vm.prank(user1);
        vm.expectRevert(StakedTitan.DepositTooSmall.selector);
        sTitan.deposit(1e14); // Below minimum
    }

    function test_Deposit_RevertsIfPaused() public {
        vm.prank(owner);
        sTitan.setDepositsPaused(true);

        vm.prank(user1);
        vm.expectRevert(StakedTitan.DepositsPaused.selector);
        sTitan.deposit(1000 * 10 ** 18);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw_ReturnsCorrectTitan() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(user1);
        uint256 titanReceived = sTitan.withdraw(1000 * 10 ** 18);

        assertEq(titanReceived, 1000 * 10 ** 18);
    }

    function test_Withdraw_BurnsSTitan() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(user1);
        sTitan.withdraw(500 * 10 ** 18);

        assertEq(sTitan.balanceOf(user1), 500 * 10 ** 18);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(user1, 1000 * 10 ** 18, 1000 * 10 ** 18);

        vm.prank(user1);
        sTitan.withdraw(1000 * 10 ** 18);
    }

    function test_Withdraw_WithAccruedRewards() public {
        // User deposits 1000 TITAN, gets 1000 sTitan
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // Add 100 TITAN rewards (10%)
        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        // Withdraw all sTitan, should get 1100 TITAN
        vm.prank(user1);
        uint256 titanReceived = sTitan.withdraw(1000 * 10 ** 18);

        assertEq(titanReceived, 1100 * 10 ** 18);
    }

    function test_Withdraw_RevertsIfZero() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(user1);
        vm.expectRevert(StakedTitan.ZeroAmount.selector);
        sTitan.withdraw(0);
    }

    function test_Withdraw_RevertsIfInsufficientBalance() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(user1);
        vm.expectRevert(StakedTitan.InsufficientBalance.selector);
        sTitan.withdraw(2000 * 10 ** 18);
    }

    function test_Withdraw_RevertsIfPaused() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(owner);
        sTitan.setWithdrawalsPaused(true);

        vm.prank(user1);
        vm.expectRevert(StakedTitan.WithdrawalsPaused.selector);
        sTitan.withdraw(1000 * 10 ** 18);
    }

    // ============ WithdrawAll Tests ============

    function test_WithdrawAll_WithdrawsEverything() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        uint256 balanceBefore = titan.balanceOf(user1);

        vm.prank(user1);
        uint256 titanReceived = sTitan.withdrawAll();

        assertEq(titanReceived, 1100 * 10 ** 18);
        assertEq(titan.balanceOf(user1), balanceBefore + 1100 * 10 ** 18);
        assertEq(sTitan.balanceOf(user1), 0);
    }

    function test_WithdrawAll_RevertsIfNoBalance() public {
        vm.prank(user1);
        vm.expectRevert(StakedTitan.ZeroAmount.selector);
        sTitan.withdrawAll();
    }

    // ============ AddRewards Tests ============

    function test_AddRewards_IncreasesExchangeRate() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        uint256 rateBefore = sTitan.exchangeRate();

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        assertTrue(sTitan.exchangeRate() > rateBefore);
    }

    function test_AddRewards_EmitsEvent() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.expectEmit(true, false, false, true);
        emit RewardsAdded(rewardDistributor, 100 * 10 ** 18, 1.1e18);

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);
    }

    function test_AddRewards_RevertsIfZero() public {
        vm.prank(rewardDistributor);
        vm.expectRevert(StakedTitan.ZeroAmount.selector);
        sTitan.addRewards(0);
    }

    // ============ Preview Tests ============

    function test_PreviewDeposit_ReturnsCorrectAmount() public {
        // First deposit: 1:1
        uint256 preview1 = sTitan.previewDeposit(1000 * 10 ** 18);
        assertEq(preview1, 1000 * 10 ** 18);

        // After deposit and rewards
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        // At 1.1 rate, 1100 TITAN = 1000 sTitan
        uint256 preview2 = sTitan.previewDeposit(1100 * 10 ** 18);
        assertEq(preview2, 1000 * 10 ** 18);
    }

    function test_PreviewWithdraw_ReturnsCorrectAmount() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        // 1000 sTitan = 1100 TITAN at 1.1 rate
        uint256 preview = sTitan.previewWithdraw(1000 * 10 ** 18);
        assertEq(preview, 1100 * 10 ** 18);
    }

    // ============ View Function Tests ============

    function test_TotalTitan_ReturnsCorrectAmount() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        assertEq(sTitan.totalTitan(), 1100 * 10 ** 18);
    }

    function test_TitanBalanceOf_ReturnsCorrectValue() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        assertEq(sTitan.titanBalanceOf(user1), 1100 * 10 ** 18);
    }

    // ============ Pause Tests ============

    function test_SetDepositsPaused_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit DepositsPausedChanged(true);

        vm.prank(owner);
        sTitan.setDepositsPaused(true);
    }

    function test_SetDepositsPaused_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        sTitan.setDepositsPaused(true);
    }

    function test_SetWithdrawalsPaused_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit WithdrawalsPausedChanged(true);

        vm.prank(owner);
        sTitan.setWithdrawalsPaused(true);
    }

    function test_SetWithdrawalsPaused_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        sTitan.setWithdrawalsPaused(true);
    }

    // ============ Multiple Users Tests ============

    function test_MultipleUsers_FairDistribution() public {
        // User1 deposits 1000 TITAN
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // Add 100 TITAN rewards
        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        // User2 deposits 1100 TITAN (gets 1000 sTitan at 1.1 rate)
        vm.prank(user2);
        sTitan.deposit(1100 * 10 ** 18);

        // Add another 220 TITAN rewards (10% of 2200 total)
        vm.prank(rewardDistributor);
        sTitan.addRewards(220 * 10 ** 18);

        // Total: 2420 TITAN, 2000 sTitan
        // Each user has 1000 sTitan = 1210 TITAN

        assertEq(sTitan.titanBalanceOf(user1), 1210 * 10 ** 18);
        assertEq(sTitan.titanBalanceOf(user2), 1210 * 10 ** 18);
    }

    // ============ Additional Branch Coverage Tests ============

    function test_PreviewWithdraw_WhenNoSupply() public view {
        // When no supply, previewWithdraw should return 0
        uint256 preview = sTitan.previewWithdraw(1000 * 10 ** 18);
        assertEq(preview, 0);
    }

    function test_PreviewDeposit_WhenNoSupply() public view {
        // When no supply, should be 1:1
        uint256 preview = sTitan.previewDeposit(1000 * 10 ** 18);
        assertEq(preview, 1000 * 10 ** 18);
    }

    function test_WithdrawAll_RevertsIfPaused() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(owner);
        sTitan.setWithdrawalsPaused(true);

        vm.prank(user1);
        vm.expectRevert(StakedTitan.WithdrawalsPaused.selector);
        sTitan.withdrawAll();
    }

    function test_TitanBalanceOf_WhenNoBalance() public view {
        // Should return 0 when user has no sTitan
        assertEq(sTitan.titanBalanceOf(user1), 0);
    }

    function test_TotalTitan_WhenEmpty() public view {
        // Should return 0 when no deposits
        assertEq(sTitan.totalTitan(), 0);
    }

    function test_Deposit_MinimumAmount() public {
        uint256 minDeposit = sTitan.MINIMUM_DEPOSIT();

        vm.prank(user1);
        uint256 received = sTitan.deposit(minDeposit);

        assertEq(received, minDeposit);
        assertEq(sTitan.balanceOf(user1), minDeposit);
    }

    function test_Deposit_LargeAmount() public {
        vm.prank(user1);
        uint256 received = sTitan.deposit(INITIAL_BALANCE);

        assertEq(received, INITIAL_BALANCE);
        assertEq(sTitan.balanceOf(user1), INITIAL_BALANCE);
    }

    function test_ExchangeRate_AfterMultipleRewards() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // Add multiple rewards
        vm.startPrank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);
        sTitan.addRewards(100 * 10 ** 18);
        sTitan.addRewards(100 * 10 ** 18);
        vm.stopPrank();

        // Rate should be 1.3
        assertEq(sTitan.exchangeRate(), 1.3e18);
    }

    function test_Withdraw_PartialAmount() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.addRewards(100 * 10 ** 18);

        // Withdraw half
        vm.prank(user1);
        uint256 received = sTitan.withdraw(500 * 10 ** 18);

        // Should get 550 TITAN (half of 1100)
        assertEq(received, 550 * 10 ** 18);
        assertEq(sTitan.balanceOf(user1), 500 * 10 ** 18);
    }

    function test_SetDepositsPaused_Toggle() public {
        vm.startPrank(owner);

        sTitan.setDepositsPaused(true);
        assertTrue(sTitan.depositsPaused());

        sTitan.setDepositsPaused(false);
        assertFalse(sTitan.depositsPaused());

        vm.stopPrank();
    }

    function test_SetWithdrawalsPaused_Toggle() public {
        vm.startPrank(owner);

        sTitan.setWithdrawalsPaused(true);
        assertTrue(sTitan.withdrawalsPaused());

        sTitan.setWithdrawalsPaused(false);
        assertFalse(sTitan.withdrawalsPaused());

        vm.stopPrank();
    }

    // ============ Fuzz Tests ============

    function testFuzz_DepositWithdraw_Symmetry(uint256 amount) public {
        amount = bound(amount, sTitan.MINIMUM_DEPOSIT(), INITIAL_BALANCE);

        vm.prank(user1);
        uint256 sTitanReceived = sTitan.deposit(amount);

        vm.prank(user1);
        uint256 titanReceived = sTitan.withdraw(sTitanReceived);

        // Should get back same amount (no rewards added)
        assertEq(titanReceived, amount);
    }

    function testFuzz_ExchangeRate_NeverDecreases(uint256 reward1, uint256 reward2) public {
        reward1 = bound(reward1, 1e18, 1000 * 10 ** 18);
        reward2 = bound(reward2, 1e18, 1000 * 10 ** 18);

        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        uint256 rate1 = sTitan.exchangeRate();

        vm.prank(rewardDistributor);
        sTitan.addRewards(reward1);

        uint256 rate2 = sTitan.exchangeRate();
        assertTrue(rate2 >= rate1);

        vm.prank(rewardDistributor);
        sTitan.addRewards(reward2);

        uint256 rate3 = sTitan.exchangeRate();
        assertTrue(rate3 >= rate2);
    }

    function testFuzz_MultipleDepositsAndWithdrawals(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, sTitan.MINIMUM_DEPOSIT(), INITIAL_BALANCE / 2);
        amount2 = bound(amount2, sTitan.MINIMUM_DEPOSIT(), INITIAL_BALANCE / 2);

        vm.startPrank(user1);
        sTitan.deposit(amount1);
        sTitan.deposit(amount2);

        uint256 totalSTitan = sTitan.balanceOf(user1);
        uint256 titanReceived = sTitan.withdrawAll();
        vm.stopPrank();

        assertEq(sTitan.balanceOf(user1), 0);
        assertEq(titanReceived, amount1 + amount2);
    }
}
