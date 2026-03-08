// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TitanToken.sol";
import "../src/TitanUSD.sol";
import "../src/Vault.sol";

contract VaultTest is Test {
    TitanToken public titan;
    TitanUSD public tusd;
    Vault public vault;

    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public liquidator = makeAddr("liquidator");

    // TITAN price: $0.10 (8 decimals)
    uint256 public constant INITIAL_PRICE = 10000000;
    uint256 public constant TITAN_AMOUNT = 10000 * 1e18; // 10,000 TITAN

    function setUp() public {
        // Deploy tokens
        titan = new TitanToken(owner);
        tusd = new TitanUSD(owner);

        // Deploy vault
        vault = new Vault(
            address(titan),
            address(tusd),
            INITIAL_PRICE,
            owner
        );

        // Authorize vault to mint tUSD
        tusd.setMinter(address(vault), true);

        // Fund users with TITAN
        titan.transfer(alice, TITAN_AMOUNT);
        titan.transfer(bob, TITAN_AMOUNT);
        titan.transfer(liquidator, TITAN_AMOUNT);

        // Approve vault
        vm.prank(alice);
        titan.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        titan.approve(address(vault), type(uint256).max);
        vm.prank(liquidator);
        titan.approve(address(vault), type(uint256).max);
    }

    // ============ Deposit Tests ============

    function test_DepositCollateral() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(alice);
        vault.depositCollateral(depositAmount);

        (uint256 collateral,,,,) = vault.getPosition(alice);
        assertEq(collateral, depositAmount);
        assertEq(vault.totalCollateral(), depositAmount);
    }

    function test_DepositCollateral_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.depositCollateral(0);
    }

    function test_MultipleDeposits() public {
        vm.startPrank(alice);
        vault.depositCollateral(500 * 1e18);
        vault.depositCollateral(500 * 1e18);
        vm.stopPrank();

        (uint256 collateral,,,,) = vault.getPosition(alice);
        assertEq(collateral, 1000 * 1e18);
    }

    // ============ Borrow Tests ============

    function test_Borrow() public {
        uint256 depositAmount = 1000 * 1e18; // 1000 TITAN = $100 at $0.10
        uint256 borrowAmount = 50 * 1e18; // 50 tUSD (50% of max at 150% MCR)

        vm.startPrank(alice);
        vault.depositCollateral(depositAmount);
        vault.borrow(borrowAmount);
        vm.stopPrank();

        (, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(debt, borrowAmount);
        assertEq(tusd.balanceOf(alice), borrowAmount);
    }

    function test_Borrow_MaxAmount() public {
        uint256 depositAmount = 1500 * 1e18; // 1500 TITAN = $150
        // At 150% MCR, max borrow = $150 / 1.5 = $100
        uint256 maxBorrow = 100 * 1e18;

        vm.startPrank(alice);
        vault.depositCollateral(depositAmount);
        vault.borrow(maxBorrow);
        vm.stopPrank();

        (, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(debt, maxBorrow);
    }

    function test_Borrow_RevertBelowMCR() public {
        uint256 depositAmount = 1000 * 1e18; // $100 collateral
        uint256 borrowAmount = 70 * 1e18; // Try to borrow $70 (would be 142% CR < 150%)

        vm.startPrank(alice);
        vault.depositCollateral(depositAmount);
        vm.expectRevert(Vault.BelowMCR.selector);
        vault.borrow(borrowAmount);
        vm.stopPrank();
    }

    function test_Borrow_RevertDebtTooLow() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 borrowAmount = 5 * 1e18; // 5 tUSD < 10 tUSD minimum

        vm.startPrank(alice);
        vault.depositCollateral(depositAmount);
        vm.expectRevert(Vault.DebtTooLow.selector);
        vault.borrow(borrowAmount);
        vm.stopPrank();
    }

    function test_Borrow_RevertNoPosition() public {
        vm.prank(alice);
        vm.expectRevert(Vault.NoPosition.selector);
        vault.borrow(50 * 1e18);
    }

    // ============ DepositAndBorrow Tests ============

    function test_DepositAndBorrow() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 borrowAmount = 50 * 1e18;

        vm.prank(alice);
        vault.depositAndBorrow(depositAmount, borrowAmount);

        (uint256 collateral, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(collateral, depositAmount);
        assertEq(debt, borrowAmount);
        assertEq(tusd.balanceOf(alice), borrowAmount);
    }

    // ============ Repay Tests ============

    function test_Repay() public {
        vm.startPrank(alice);
        vault.depositAndBorrow(1000 * 1e18, 50 * 1e18);

        tusd.approve(address(vault), type(uint256).max);
        vault.repay(20 * 1e18);
        vm.stopPrank();

        (, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(debt, 30 * 1e18);
    }

    function test_RepayFull() public {
        vm.startPrank(alice);
        vault.depositAndBorrow(1000 * 1e18, 50 * 1e18);

        tusd.approve(address(vault), type(uint256).max);
        vault.repay(50 * 1e18);
        vm.stopPrank();

        (, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(debt, 0);
    }

    function test_Repay_RevertDebtTooLow() public {
        vm.startPrank(alice);
        vault.depositAndBorrow(1000 * 1e18, 50 * 1e18);

        tusd.approve(address(vault), type(uint256).max);
        // Try to repay leaving only 5 tUSD debt (below 10 minimum)
        vm.expectRevert(Vault.DebtTooLow.selector);
        vault.repay(45 * 1e18);
        vm.stopPrank();
    }

    // ============ Withdraw Tests ============

    function test_WithdrawCollateral() public {
        vm.startPrank(alice);
        vault.depositCollateral(1000 * 1e18);
        vault.withdrawCollateral(500 * 1e18);
        vm.stopPrank();

        (uint256 collateral,,,,) = vault.getPosition(alice);
        assertEq(collateral, 500 * 1e18);
    }

    function test_WithdrawCollateral_RevertBelowMCR() public {
        vm.startPrank(alice);
        vault.depositAndBorrow(1000 * 1e18, 50 * 1e18);

        // Try to withdraw too much (would put below MCR)
        vm.expectRevert(Vault.BelowMCR.selector);
        vault.withdrawCollateral(500 * 1e18);
        vm.stopPrank();
    }

    function test_WithdrawCollateral_RevertInsufficientCollateral() public {
        vm.startPrank(alice);
        vault.depositCollateral(1000 * 1e18);

        vm.expectRevert(Vault.InsufficientCollateral.selector);
        vault.withdrawCollateral(2000 * 1e18);
        vm.stopPrank();
    }

    // ============ Close Position Tests ============

    function test_ClosePosition() public {
        vm.startPrank(alice);
        vault.depositAndBorrow(1000 * 1e18, 50 * 1e18);

        tusd.approve(address(vault), type(uint256).max);
        uint256 titanBefore = titan.balanceOf(alice);
        vault.closePosition();
        vm.stopPrank();

        (uint256 collateral, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(collateral, 0);
        assertEq(debt, 0);
        assertEq(titan.balanceOf(alice), titanBefore + 1000 * 1e18);
    }

    // ============ Liquidation Tests ============

    function test_IsLiquidatable() public {
        vm.prank(alice);
        vault.depositAndBorrow(1500 * 1e18, 100 * 1e18); // 150% CR exactly

        // Not liquidatable at 150% CR
        assertFalse(vault.isLiquidatable(alice));

        // Drop price by 30% to $0.07 - CR becomes ~105%
        vault.setPrice(7000000);
        assertTrue(vault.isLiquidatable(alice));
    }

    function test_Liquidate() public {
        // Alice opens position at 150% CR
        vm.prank(alice);
        vault.depositAndBorrow(1500 * 1e18, 100 * 1e18);

        // Price drops 30%, position becomes liquidatable
        vault.setPrice(7000000);
        assertTrue(vault.isLiquidatable(alice));

        // Give liquidator some tUSD to repay
        vm.prank(alice);
        tusd.transfer(liquidator, 50 * 1e18);

        // Liquidator liquidates
        vm.startPrank(liquidator);
        tusd.approve(address(vault), type(uint256).max);
        uint256 titanBefore = titan.balanceOf(liquidator);
        vault.liquidate(alice, 50 * 1e18);
        vm.stopPrank();

        // Liquidator received collateral with bonus
        uint256 titanReceived = titan.balanceOf(liquidator) - titanBefore;
        assertTrue(titanReceived > 0);

        // Alice's position was reduced
        (uint256 collateral, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(debt, 50 * 1e18); // 100 - 50 repaid
        assertTrue(collateral < 1500 * 1e18);
    }

    function test_Liquidate_RevertNotLiquidatable() public {
        vm.prank(alice);
        vault.depositAndBorrow(1500 * 1e18, 50 * 1e18); // 300% CR - very safe

        vm.prank(liquidator);
        vm.expectRevert(Vault.NotLiquidatable.selector);
        vault.liquidate(alice, 50 * 1e18);
    }

    // ============ View Function Tests ============

    function test_GetPosition() public {
        vm.prank(alice);
        vault.depositAndBorrow(1500 * 1e18, 100 * 1e18);

        (
            uint256 collateral,
            uint256 debt,
            uint256 collateralValue,
            uint256 collateralRatio,
            uint256 maxBorrow
        ) = vault.getPosition(alice);

        assertEq(collateral, 1500 * 1e18);
        assertEq(debt, 100 * 1e18);
        assertEq(collateralValue, 150 * 1e18); // 1500 TITAN * $0.10
        assertEq(collateralRatio, 15000); // 150% in basis points
        assertEq(maxBorrow, 0); // At exactly 150% MCR, no more borrow allowed
    }

    function test_MaxBorrowAmount() public view {
        uint256 collateral = 1500 * 1e18; // $150 worth
        uint256 maxBorrow = vault.maxBorrowAmount(collateral);
        assertEq(maxBorrow, 100 * 1e18); // $150 / 1.5 = $100
    }

    function test_GetCollateralValue() public view {
        uint256 collateral = 1000 * 1e18;
        uint256 value = vault.getCollateralValue(collateral);
        assertEq(value, 100 * 1e18); // 1000 TITAN * $0.10 = $100
    }

    // ============ Admin Tests ============

    function test_SetPrice() public {
        uint256 newPrice = 20000000; // $0.20
        vault.setPrice(newPrice);
        assertEq(vault.titanPrice(), newPrice);
    }

    function test_SetPrice_RevertInvalidPrice() public {
        vm.expectRevert(Vault.InvalidPrice.selector);
        vault.setPrice(0);
    }

    function test_SetPrice_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setPrice(20000000);
    }

    // ============ Integration Tests ============

    function test_FullFlow() public {
        // 1. Alice deposits and borrows
        vm.startPrank(alice);
        vault.depositAndBorrow(2000 * 1e18, 100 * 1e18);
        vm.stopPrank();

        // 2. Alice uses tUSD (simulated by transferring)
        vm.prank(alice);
        tusd.transfer(bob, 50 * 1e18);

        // 3. Alice gets more tUSD somehow and repays partially
        vm.prank(bob);
        tusd.transfer(alice, 30 * 1e18);

        vm.startPrank(alice);
        tusd.approve(address(vault), type(uint256).max);
        vault.repay(30 * 1e18);
        vm.stopPrank();

        // 4. Alice withdraws some collateral
        vm.prank(alice);
        vault.withdrawCollateral(500 * 1e18);

        // 5. Check final state
        (uint256 collateral, uint256 debt,,,) = vault.getPosition(alice);
        assertEq(collateral, 1500 * 1e18);
        assertEq(debt, 70 * 1e18);
    }

    function test_MultipleUsersIndependent() public {
        // Alice opens position
        vm.prank(alice);
        vault.depositAndBorrow(1500 * 1e18, 100 * 1e18);

        // Bob opens position
        vm.prank(bob);
        vault.depositAndBorrow(2000 * 1e18, 50 * 1e18);

        // Check positions are independent
        (uint256 aliceCol, uint256 aliceDebt,,,) = vault.getPosition(alice);
        (uint256 bobCol, uint256 bobDebt,,,) = vault.getPosition(bob);

        assertEq(aliceCol, 1500 * 1e18);
        assertEq(aliceDebt, 100 * 1e18);
        assertEq(bobCol, 2000 * 1e18);
        assertEq(bobDebt, 50 * 1e18);

        // Check totals
        assertEq(vault.totalCollateral(), 3500 * 1e18);
        assertEq(vault.totalDebt(), 150 * 1e18);
    }
}
