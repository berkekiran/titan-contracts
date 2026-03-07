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
    uint256 public constant REWARD_RATE = 1e10; // ~31.5% APY

    event Deposited(address indexed user, uint256 titanAmount, uint256 sTitanAmount);
    event Withdrawn(address indexed user, uint256 sTitanAmount, uint256 titanAmount);
    event RewardsAccrued(uint256 amount, uint256 newExchangeRate);
    event RewardsDeposited(address indexed from, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event DepositsPausedChanged(bool paused);
    event WithdrawalsPausedChanged(bool paused);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        rewardDistributor = makeAddr("rewardDistributor");

        vm.startPrank(owner);

        titan = new TitanToken(owner);
        sTitan = new StakedTitan(address(titan), REWARD_RATE, owner);

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
        assertEq(sTitan.symbol(), "sTITAN");
    }

    function test_Constructor_SetsCorrectTitan() public view {
        assertEq(address(sTitan.titan()), address(titan));
    }

    function test_Constructor_SetsCorrectOwner() public view {
        assertEq(sTitan.owner(), owner);
    }

    function test_Constructor_SetsCorrectRewardRate() public view {
        assertEq(sTitan.rewardRate(), REWARD_RATE);
    }

    function test_Constructor_RevertsIfZeroToken() public {
        vm.expectRevert(StakedTitan.InvalidToken.selector);
        new StakedTitan(address(0), REWARD_RATE, owner);
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

    function test_ExchangeRate_IncreasesOverTime() public {
        // User deposits 1000 TITAN
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // Fund rewards
        vm.prank(rewardDistributor);
        sTitan.depositRewards(1000 * 10 ** 18);

        // Move time forward
        vm.warp(block.timestamp + 365 days);

        // Exchange rate should have increased
        uint256 rate = sTitan.exchangeRate();
        assertTrue(rate > 1e18, "Exchange rate should increase over time");
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

        // Fund rewards
        vm.prank(rewardDistributor);
        sTitan.depositRewards(1000 * 10 ** 18);

        // Warp time forward to accrue rewards
        vm.warp(block.timestamp + 365 days);

        // Withdraw all sTitan, should get more than deposited
        vm.prank(user1);
        uint256 titanReceived = sTitan.withdraw(1000 * 10 ** 18);

        assertTrue(titanReceived > 1000 * 10 ** 18, "Should receive rewards");
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

        uint256 balanceBefore = titan.balanceOf(user1);

        vm.prank(user1);
        uint256 titanReceived = sTitan.withdrawAll();

        assertEq(titanReceived, 1000 * 10 ** 18);
        assertEq(titan.balanceOf(user1), balanceBefore + 1000 * 10 ** 18);
        assertEq(sTitan.balanceOf(user1), 0);
    }

    function test_WithdrawAll_RevertsIfNoBalance() public {
        vm.prank(user1);
        vm.expectRevert(StakedTitan.ZeroAmount.selector);
        sTitan.withdrawAll();
    }

    // ============ DepositRewards Tests ============

    function test_DepositRewards_TransfersTokens() public {
        uint256 balanceBefore = titan.balanceOf(address(sTitan));

        vm.prank(rewardDistributor);
        sTitan.depositRewards(100 * 10 ** 18);

        assertEq(titan.balanceOf(address(sTitan)), balanceBefore + 100 * 10 ** 18);
    }

    function test_DepositRewards_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit RewardsDeposited(rewardDistributor, 100 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.depositRewards(100 * 10 ** 18);
    }

    function test_DepositRewards_RevertsIfZero() public {
        vm.prank(rewardDistributor);
        vm.expectRevert(StakedTitan.ZeroAmount.selector);
        sTitan.depositRewards(0);
    }

    // ============ SetRewardRate Tests ============

    function test_SetRewardRate_UpdatesRate() public {
        uint256 newRate = 2e10;

        vm.prank(owner);
        sTitan.setRewardRate(newRate);

        assertEq(sTitan.rewardRate(), newRate);
    }

    function test_SetRewardRate_EmitsEvent() public {
        uint256 newRate = 2e10;

        vm.expectEmit(false, false, false, true);
        emit RewardRateUpdated(REWARD_RATE, newRate);

        vm.prank(owner);
        sTitan.setRewardRate(newRate);
    }

    function test_SetRewardRate_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        sTitan.setRewardRate(2e10);
    }

    // ============ Preview Tests ============

    function test_PreviewDeposit_ReturnsCorrectAmount() public view {
        // First deposit: 1:1
        uint256 preview1 = sTitan.previewDeposit(1000 * 10 ** 18);
        assertEq(preview1, 1000 * 10 ** 18);
    }

    function test_PreviewWithdraw_ReturnsCorrectAmount() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // 1000 sTitan = 1000 TITAN at 1.0 rate
        uint256 preview = sTitan.previewWithdraw(1000 * 10 ** 18);
        assertEq(preview, 1000 * 10 ** 18);
    }

    // ============ View Function Tests ============

    function test_TotalTitan_ReturnsCorrectAmount() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        assertEq(sTitan.totalTitan(), 1000 * 10 ** 18);
    }

    function test_TitanBalanceOf_ReturnsCorrectValue() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        assertEq(sTitan.titanBalanceOf(user1), 1000 * 10 ** 18);
    }

    function test_CurrentAPY_ReturnsCorrectValue() public view {
        uint256 apy = sTitan.currentAPY();
        // REWARD_RATE = 1e10, APY ≈ 31.5%
        assertTrue(apy > 30 && apy < 35, "APY should be around 31.5%");
    }

    function test_AvailableRewards_ReturnsCorrectValue() public {
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.depositRewards(500 * 10 ** 18);

        uint256 available = sTitan.availableRewards();
        assertEq(available, 500 * 10 ** 18);
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

    // ============ Time-based Reward Tests ============

    function test_Rewards_AccrueOverTime() public {
        // User deposits
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // Fund rewards
        vm.prank(rewardDistributor);
        sTitan.depositRewards(1000 * 10 ** 18);

        uint256 valueBefore = sTitan.titanBalanceOf(user1);

        // Warp 30 days
        vm.warp(block.timestamp + 30 days);

        uint256 valueAfter = sTitan.titanBalanceOf(user1);

        assertTrue(valueAfter > valueBefore, "Value should increase over time");
    }

    function test_Rewards_StopWhenNoFunds() public {
        // User deposits
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // No rewards deposited

        // Warp 30 days
        vm.warp(block.timestamp + 30 days);

        // Value should stay the same (capped by available balance)
        uint256 value = sTitan.titanBalanceOf(user1);
        assertEq(value, 1000 * 10 ** 18, "Value should not increase without reward funds");
    }

    // ============ Multiple Users Tests ============

    function test_MultipleUsers_FairDistribution() public {
        // User1 deposits 1000 TITAN
        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        // User2 deposits 1000 TITAN
        vm.prank(user2);
        sTitan.deposit(1000 * 10 ** 18);

        // Fund rewards
        vm.prank(rewardDistributor);
        sTitan.depositRewards(200 * 10 ** 18);

        // Warp time
        vm.warp(block.timestamp + 365 days);

        // Both users should have equal value
        uint256 value1 = sTitan.titanBalanceOf(user1);
        uint256 value2 = sTitan.titanBalanceOf(user2);

        assertEq(value1, value2, "Users should have equal value");
    }

    // ============ Fuzz Tests ============

    function testFuzz_DepositWithdraw_Symmetry(uint256 amount) public {
        amount = bound(amount, sTitan.MINIMUM_DEPOSIT(), INITIAL_BALANCE);

        vm.prank(user1);
        uint256 sTitanReceived = sTitan.deposit(amount);

        vm.prank(user1);
        uint256 titanReceived = sTitan.withdraw(sTitanReceived);

        // Should get back same amount (no time passed, no rewards)
        assertEq(titanReceived, amount);
    }

    function testFuzz_ExchangeRate_NeverDecreases(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 365 days);

        vm.prank(user1);
        sTitan.deposit(1000 * 10 ** 18);

        vm.prank(rewardDistributor);
        sTitan.depositRewards(1000 * 10 ** 18);

        uint256 rate1 = sTitan.exchangeRate();

        vm.warp(block.timestamp + timeElapsed);

        uint256 rate2 = sTitan.exchangeRate();
        assertTrue(rate2 >= rate1, "Exchange rate should never decrease");
    }
}
