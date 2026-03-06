// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TitanToken.sol";
import "../src/Faucet.sol";

contract FaucetTest is Test {
    TitanToken public token;
    Faucet public faucet;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant DRIP_AMOUNT = 1000 * 10 ** 18;
    uint256 public constant COOLDOWN_PERIOD = 24 hours;
    uint256 public constant FAUCET_BALANCE = 10_000_000 * 10 ** 18;

    event TokensClaimed(address indexed claimer, uint256 amount);
    event DripAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event CooldownPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event PausedStateChanged(bool paused);
    event TokensDeposited(address indexed depositor, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);

        token = new TitanToken(owner);
        faucet = new Faucet(address(token), DRIP_AMOUNT, COOLDOWN_PERIOD, owner);

        // Fund faucet
        token.transfer(address(faucet), FAUCET_BALANCE);

        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectToken() public view {
        assertEq(address(faucet.titanToken()), address(token));
    }

    function test_Constructor_SetsCorrectDripAmount() public view {
        assertEq(faucet.dripAmount(), DRIP_AMOUNT);
    }

    function test_Constructor_SetsCorrectCooldownPeriod() public view {
        assertEq(faucet.cooldownPeriod(), COOLDOWN_PERIOD);
    }

    function test_Constructor_SetsCorrectOwner() public view {
        assertEq(faucet.owner(), owner);
    }

    function test_Constructor_NotPausedByDefault() public view {
        assertFalse(faucet.paused());
    }

    function test_Constructor_RevertsIfZeroTokenAddress() public {
        vm.expectRevert("Faucet: invalid token");
        new Faucet(address(0), DRIP_AMOUNT, COOLDOWN_PERIOD, owner);
    }

    function test_Constructor_RevertsIfZeroDripAmount() public {
        vm.expectRevert("Faucet: invalid drip amount");
        new Faucet(address(token), 0, COOLDOWN_PERIOD, owner);
    }

    function test_Constructor_RevertsIfZeroCooldown() public {
        vm.expectRevert("Faucet: invalid cooldown");
        new Faucet(address(token), DRIP_AMOUNT, 0, owner);
    }

    // ============ Claim Tests ============

    function test_Claim_TransfersTokens() public {
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        faucet.claim();

        assertEq(token.balanceOf(user1), balanceBefore + DRIP_AMOUNT);
    }

    function test_Claim_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit TokensClaimed(user1, DRIP_AMOUNT);

        vm.prank(user1);
        faucet.claim();
    }

    function test_Claim_UpdatesLastClaimTime() public {
        vm.prank(user1);
        faucet.claim();

        assertEq(faucet.lastClaimTime(user1), block.timestamp);
    }

    function test_Claim_RevertsIfCooldownNotPassed() public {
        vm.prank(user1);
        faucet.claim();

        vm.prank(user1);
        vm.expectRevert("Faucet: cooldown not passed");
        faucet.claim();
    }

    function test_Claim_SucceedsAfterCooldown() public {
        vm.prank(user1);
        faucet.claim();

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        vm.prank(user1);
        faucet.claim();

        assertEq(token.balanceOf(user1), DRIP_AMOUNT * 2);
    }

    function test_Claim_RevertsIfPaused() public {
        vm.prank(owner);
        faucet.setPaused(true);

        vm.prank(user1);
        vm.expectRevert("Faucet: paused");
        faucet.claim();
    }

    function test_Claim_RevertsIfInsufficientBalance() public {
        // Deploy new faucet with no balance
        vm.prank(owner);
        Faucet emptyFaucet = new Faucet(address(token), DRIP_AMOUNT, COOLDOWN_PERIOD, owner);

        vm.prank(user1);
        vm.expectRevert("Faucet: insufficient balance");
        emptyFaucet.claim();
    }

    function test_Claim_MultipleUsers() public {
        vm.prank(user1);
        faucet.claim();

        vm.prank(user2);
        faucet.claim();

        assertEq(token.balanceOf(user1), DRIP_AMOUNT);
        assertEq(token.balanceOf(user2), DRIP_AMOUNT);
    }

    // ============ Can Claim Tests ============

    function test_CanClaim_TrueIfNeverClaimed() public view {
        assertTrue(faucet.canClaim(user1));
    }

    function test_CanClaim_FalseIfCooldownNotPassed() public {
        vm.prank(user1);
        faucet.claim();

        assertFalse(faucet.canClaim(user1));
    }

    function test_CanClaim_TrueAfterCooldown() public {
        vm.prank(user1);
        faucet.claim();

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        assertTrue(faucet.canClaim(user1));
    }

    // ============ Time Until Next Claim Tests ============

    function test_TimeUntilNextClaim_ZeroIfNeverClaimed() public view {
        assertEq(faucet.timeUntilNextClaim(user1), 0);
    }

    function test_TimeUntilNextClaim_ReturnsCorrectTime() public {
        vm.prank(user1);
        faucet.claim();

        assertEq(faucet.timeUntilNextClaim(user1), COOLDOWN_PERIOD);

        vm.warp(block.timestamp + COOLDOWN_PERIOD / 2);

        assertEq(faucet.timeUntilNextClaim(user1), COOLDOWN_PERIOD / 2);
    }

    function test_TimeUntilNextClaim_ZeroAfterCooldown() public {
        vm.prank(user1);
        faucet.claim();

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        assertEq(faucet.timeUntilNextClaim(user1), 0);
    }

    // ============ Set Drip Amount Tests ============

    function test_SetDripAmount_UpdatesAmount() public {
        uint256 newAmount = 2000 * 10 ** 18;

        vm.prank(owner);
        faucet.setDripAmount(newAmount);

        assertEq(faucet.dripAmount(), newAmount);
    }

    function test_SetDripAmount_EmitsEvent() public {
        uint256 newAmount = 2000 * 10 ** 18;

        vm.expectEmit(false, false, false, true);
        emit DripAmountUpdated(DRIP_AMOUNT, newAmount);

        vm.prank(owner);
        faucet.setDripAmount(newAmount);
    }

    function test_SetDripAmount_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        faucet.setDripAmount(2000 * 10 ** 18);
    }

    function test_SetDripAmount_RevertsIfZero() public {
        vm.prank(owner);
        vm.expectRevert("Faucet: invalid drip amount");
        faucet.setDripAmount(0);
    }

    // ============ Set Cooldown Period Tests ============

    function test_SetCooldownPeriod_UpdatesPeriod() public {
        uint256 newPeriod = 12 hours;

        vm.prank(owner);
        faucet.setCooldownPeriod(newPeriod);

        assertEq(faucet.cooldownPeriod(), newPeriod);
    }

    function test_SetCooldownPeriod_EmitsEvent() public {
        uint256 newPeriod = 12 hours;

        vm.expectEmit(false, false, false, true);
        emit CooldownPeriodUpdated(COOLDOWN_PERIOD, newPeriod);

        vm.prank(owner);
        faucet.setCooldownPeriod(newPeriod);
    }

    function test_SetCooldownPeriod_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        faucet.setCooldownPeriod(12 hours);
    }

    function test_SetCooldownPeriod_RevertsIfZero() public {
        vm.prank(owner);
        vm.expectRevert("Faucet: invalid cooldown");
        faucet.setCooldownPeriod(0);
    }

    // ============ Set Paused Tests ============

    function test_SetPaused_PausesFaucet() public {
        vm.prank(owner);
        faucet.setPaused(true);

        assertTrue(faucet.paused());
    }

    function test_SetPaused_UnpausesFaucet() public {
        vm.startPrank(owner);
        faucet.setPaused(true);
        faucet.setPaused(false);
        vm.stopPrank();

        assertFalse(faucet.paused());
    }

    function test_SetPaused_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit PausedStateChanged(true);

        vm.prank(owner);
        faucet.setPaused(true);
    }

    function test_SetPaused_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        faucet.setPaused(true);
    }

    // ============ Deposit Tests ============

    function test_Deposit_TransfersTokens() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 balanceBefore = token.balanceOf(address(faucet));

        vm.startPrank(owner);
        token.approve(address(faucet), depositAmount);
        faucet.deposit(depositAmount);
        vm.stopPrank();

        assertEq(token.balanceOf(address(faucet)), balanceBefore + depositAmount);
    }

    function test_Deposit_EmitsEvent() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.startPrank(owner);
        token.approve(address(faucet), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit TokensDeposited(owner, depositAmount);

        faucet.deposit(depositAmount);
        vm.stopPrank();
    }

    function test_Deposit_RevertsIfZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("Faucet: invalid amount");
        faucet.deposit(0);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw_TransfersTokens() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;
        uint256 balanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        faucet.withdraw(withdrawAmount);

        assertEq(token.balanceOf(owner), balanceBefore + withdrawAmount);
    }

    function test_Withdraw_EmitsEvent() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit TokensWithdrawn(owner, withdrawAmount);

        vm.prank(owner);
        faucet.withdraw(withdrawAmount);
    }

    function test_Withdraw_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        faucet.withdraw(1000 * 10 ** 18);
    }

    function test_Withdraw_RevertsIfZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("Faucet: invalid amount");
        faucet.withdraw(0);
    }

    function test_Withdraw_RevertsIfInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert("Faucet: insufficient balance");
        faucet.withdraw(FAUCET_BALANCE + 1);
    }

    // ============ Balance Tests ============

    function test_Balance_ReturnsCorrectBalance() public view {
        assertEq(faucet.balance(), FAUCET_BALANCE);
    }

    function test_Balance_UpdatesAfterClaim() public {
        vm.prank(user1);
        faucet.claim();

        assertEq(faucet.balance(), FAUCET_BALANCE - DRIP_AMOUNT);
    }

    // ============ Fuzz Tests ============

    function testFuzz_Claim_AfterVariousCooldowns(uint256 timeElapsed) public {
        vm.assume(timeElapsed >= COOLDOWN_PERIOD && timeElapsed <= 365 days);

        vm.prank(user1);
        faucet.claim();

        vm.warp(block.timestamp + timeElapsed);

        vm.prank(user1);
        faucet.claim();

        assertEq(token.balanceOf(user1), DRIP_AMOUNT * 2);
    }

    function testFuzz_SetDripAmount_VariousAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount <= FAUCET_BALANCE);

        vm.prank(owner);
        faucet.setDripAmount(amount);

        assertEq(faucet.dripAmount(), amount);
    }
}
