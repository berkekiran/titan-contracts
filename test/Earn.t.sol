// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TitanToken.sol";
import "../src/Earn.sol";

contract EarnTest is Test {
    TitanToken public token;
    Earn public earn;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant REWARD_RATE = 1e15; // 0.001 TITAN per second per token staked
    uint256 public constant USER_BALANCE = 10_000 * 10 ** 18;
    uint256 public constant REWARD_POOL = 10_000_000 * 10 ** 18;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event PausedStateChanged(bool paused);
    event RewardsDeposited(address indexed depositor, uint256 amount);
    event ExcessRewardsWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);
        token = new TitanToken(owner);
        earn = new Earn(address(token), REWARD_RATE, owner);

        // Fund earn contract with rewards
        token.transfer(address(earn), REWARD_POOL);

        // Give users some tokens
        token.transfer(user1, USER_BALANCE);
        token.transfer(user2, USER_BALANCE);
        vm.stopPrank();

        // Users approve earn contract
        vm.prank(user1);
        token.approve(address(earn), type(uint256).max);

        vm.prank(user2);
        token.approve(address(earn), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectToken() public view {
        assertEq(address(earn.titanToken()), address(token));
    }

    function test_Constructor_SetsCorrectRewardRate() public view {
        assertEq(earn.rewardRate(), REWARD_RATE);
    }

    function test_Constructor_SetsCorrectOwner() public view {
        assertEq(earn.owner(), owner);
    }

    function test_Constructor_RevertsIfZeroTokenAddress() public {
        vm.expectRevert(Earn.InvalidToken.selector);
        new Earn(address(0), REWARD_RATE, owner);
    }

    // ============ Stake Tests ============

    function test_Stake_UpdatesBalances() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        assertEq(earn.stakedBalance(user1), stakeAmount);
        assertEq(earn.totalStaked(), stakeAmount);
        assertEq(token.balanceOf(user1), USER_BALANCE - stakeAmount);
    }

    function test_Stake_EmitsStakedEvent() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit Staked(user1, stakeAmount);

        vm.prank(user1);
        earn.stake(stakeAmount);
    }

    function test_Stake_RevertsIfZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(Earn.CannotStakeZero.selector);
        earn.stake(0);
    }

    function test_Stake_RevertsIfPaused() public {
        vm.prank(owner);
        earn.setPaused(true);

        vm.prank(user1);
        vm.expectRevert(Earn.ContractPaused.selector);
        earn.stake(1000 * 10 ** 18);
    }

    function test_Stake_MultipleStakes() public {
        uint256 stakeAmount1 = 500 * 10 ** 18;
        uint256 stakeAmount2 = 300 * 10 ** 18;

        vm.startPrank(user1);
        earn.stake(stakeAmount1);
        earn.stake(stakeAmount2);
        vm.stopPrank();

        assertEq(earn.stakedBalance(user1), stakeAmount1 + stakeAmount2);
    }

    function testFuzz_Stake_VariousAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= USER_BALANCE);

        vm.prank(user1);
        earn.stake(amount);

        assertEq(earn.stakedBalance(user1), amount);
    }

    // ============ Unstake Tests ============

    function test_Unstake_UpdatesBalances() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        uint256 unstakeAmount = 400 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.prank(user1);
        earn.unstake(unstakeAmount);

        assertEq(earn.stakedBalance(user1), stakeAmount - unstakeAmount);
        assertEq(earn.totalStaked(), stakeAmount - unstakeAmount);
    }

    function test_Unstake_EmitsUnstakedEvent() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, stakeAmount);

        vm.prank(user1);
        earn.unstake(stakeAmount);
    }

    function test_Unstake_RevertsIfZeroAmount() public {
        vm.prank(user1);
        earn.stake(1000 * 10 ** 18);

        vm.prank(user1);
        vm.expectRevert(Earn.CannotUnstakeZero.selector);
        earn.unstake(0);
    }

    function test_Unstake_RevertsIfInsufficientBalance() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.prank(user1);
        vm.expectRevert(Earn.InsufficientBalance.selector);
        earn.unstake(stakeAmount + 1);
    }

    // ============ Rewards Tests ============

    function test_Earned_ReturnsCorrectRewards() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        // Fast forward time
        vm.warp(block.timestamp + 100);

        uint256 expectedRewards = (100 * REWARD_RATE * 1e18) / 1e18;
        uint256 earned = earn.earned(user1);

        // Allow for small rounding errors
        assertApproxEqAbs(earned, expectedRewards, 1e10);
    }

    function test_ClaimRewards_TransfersRewards() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.warp(block.timestamp + 100);

        uint256 earnedBefore = earn.earned(user1);
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        earn.claimRewards();

        assertEq(earn.earned(user1), 0);
        assertApproxEqAbs(token.balanceOf(user1), balanceBefore + earnedBefore, 1e10);
    }

    function test_ClaimRewards_EmitsEvent() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.warp(block.timestamp + 100);

        uint256 expectedRewards = earn.earned(user1);

        vm.expectEmit(true, false, false, false);
        emit RewardsClaimed(user1, expectedRewards);

        vm.prank(user1);
        earn.claimRewards();
    }

    function test_ClaimRewards_RevertsIfNoRewards() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.prank(user1);
        vm.expectRevert(Earn.NoRewardsToClaim.selector);
        earn.claimRewards();
    }

    function test_ClaimRewards_RevertsIfInsufficientRewardBalance() public {
        // Create a new Earn contract with very little rewards
        Earn smallEarn = new Earn(address(token), 1e18, owner);

        vm.prank(owner);
        token.transfer(address(smallEarn), 1 * 10 ** 18); // Only 1 TITAN

        vm.prank(user1);
        token.approve(address(smallEarn), type(uint256).max);

        vm.prank(user1);
        smallEarn.stake(1000 * 10 ** 18);

        vm.warp(block.timestamp + 1000); // Earn more than available

        uint256 earned = smallEarn.earned(user1);
        assertTrue(earned > 1 * 10 ** 18); // More than available

        vm.prank(user1);
        vm.expectRevert(Earn.InsufficientRewardBalance.selector);
        smallEarn.claimRewards();
    }

    // ============ Exit Tests ============

    function test_Exit_UnstakesAndClaimsRewards() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.warp(block.timestamp + 100);

        uint256 earnedBefore = earn.earned(user1);
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        earn.exit();

        assertEq(earn.stakedBalance(user1), 0);
        assertEq(earn.earned(user1), 0);
        assertApproxEqAbs(token.balanceOf(user1), balanceBefore + stakeAmount + earnedBefore, 1e10);
    }

    // ============ Reward Rate Tests ============

    function test_SetRewardRate_UpdatesRate() public {
        uint256 newRate = 2e15;

        vm.prank(owner);
        earn.setRewardRate(newRate);

        assertEq(earn.rewardRate(), newRate);
    }

    function test_SetRewardRate_EmitsEvent() public {
        uint256 newRate = 2e15;

        vm.expectEmit(false, false, false, true);
        emit RewardRateUpdated(REWARD_RATE, newRate);

        vm.prank(owner);
        earn.setRewardRate(newRate);
    }

    function test_SetRewardRate_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        earn.setRewardRate(2e15);
    }

    // ============ Pause Tests ============

    function test_SetPaused_PausesContract() public {
        vm.prank(owner);
        earn.setPaused(true);

        assertTrue(earn.paused());
    }

    function test_SetPaused_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit PausedStateChanged(true);

        vm.prank(owner);
        earn.setPaused(true);
    }

    function test_SetPaused_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        earn.setPaused(true);
    }

    // ============ Multiple Users Tests ============

    function test_MultipleUsers_CorrectRewardDistribution() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        // User1 stakes
        vm.prank(user1);
        earn.stake(stakeAmount);

        vm.warp(block.timestamp + 50);

        // User2 stakes
        vm.prank(user2);
        earn.stake(stakeAmount);

        vm.warp(block.timestamp + 50);

        uint256 earned1 = earn.earned(user1);
        uint256 earned2 = earn.earned(user2);

        // User1 should have earned more (staked longer and alone initially)
        assertTrue(earned1 > earned2);
    }

    // ============ Deposit Rewards Tests ============

    function test_DepositRewards() public {
        vm.prank(owner);
        token.approve(address(earn), 1000 * 10 ** 18);

        vm.expectEmit(true, false, false, true);
        emit RewardsDeposited(owner, 1000 * 10 ** 18);

        vm.prank(owner);
        earn.depositRewards(1000 * 10 ** 18);

        assertEq(token.balanceOf(address(earn)), REWARD_POOL + 1000 * 10 ** 18);
    }

    // ============ Available Rewards Tests ============

    function test_AvailableRewards_ReturnsCorrectAmount() public {
        // Initially, available rewards = contract balance = REWARD_POOL
        assertEq(earn.availableRewards(), REWARD_POOL);

        // After staking, user adds tokens to the contract
        // Balance = REWARD_POOL + staked, totalStaked = staked
        // Available = balance - totalStaked = REWARD_POOL (unchanged)
        vm.prank(user1);
        earn.stake(1000 * 10 ** 18);

        // Available rewards should still equal REWARD_POOL
        assertEq(earn.availableRewards(), REWARD_POOL);
    }

    // ============ Emergency Withdraw Tests ============

    function test_EmergencyWithdraw_OnlyWithdrawsExcessRewards() public {
        // User stakes
        vm.prank(user1);
        earn.stake(1000 * 10 ** 18);

        uint256 available = earn.availableRewards();

        vm.prank(owner);
        earn.emergencyWithdraw(available);

        assertEq(token.balanceOf(address(earn)), earn.totalStaked());
    }

    function test_EmergencyWithdraw_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        earn.emergencyWithdraw(1000 * 10 ** 18);
    }

    function test_EmergencyWithdraw_RevertsIfExceedsAvailable() public {
        vm.prank(user1);
        earn.stake(1000 * 10 ** 18);

        // Available = REWARD_POOL (balance - totalStaked)
        // Try to withdraw more than available
        vm.prank(owner);
        vm.expectRevert(Earn.InsufficientRewardBalance.selector);
        earn.emergencyWithdraw(REWARD_POOL + 1); // Can't withdraw more than available
    }

    function test_EmergencyWithdraw_ProtectsUserFunds() public {
        vm.prank(user1);
        earn.stake(5000 * 10 ** 18);

        uint256 userStaked = earn.stakedBalance(user1);
        uint256 contractBalance = token.balanceOf(address(earn));

        // Owner can only withdraw the excess (rewards - not staked)
        uint256 maxWithdraw = contractBalance - userStaked;

        vm.prank(owner);
        earn.emergencyWithdraw(maxWithdraw);

        // User can still unstake their full amount
        vm.prank(user1);
        earn.unstake(userStaked);

        assertEq(token.balanceOf(user1), USER_BALANCE);
    }

    // ============ View Functions Tests ============

    function test_RewardPerToken_ReturnsZeroWhenNoStakes() public view {
        assertEq(earn.rewardPerToken(), 0);
    }

    function test_RewardPerToken_IncreasesOverTime() public {
        vm.prank(user1);
        earn.stake(1000 * 10 ** 18);

        uint256 rpt1 = earn.rewardPerToken();
        vm.warp(block.timestamp + 100);
        uint256 rpt2 = earn.rewardPerToken();

        assertTrue(rpt2 > rpt1);
    }
}
