// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Vault
 * @author Titan Team
 * @notice Overcollateralized lending - deposit TITAN, borrow tUSD
 * @dev Liquidation-enabled CDP system similar to MakerDAO/Liquity
 *
 * How it works:
 * 1. User deposits TITAN as collateral
 * 2. User can borrow tUSD up to (collateral value / MCR)
 * 3. If collateral ratio drops below liquidation threshold, position can be liquidated
 * 4. Liquidators repay debt and receive collateral at a discount
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./TitanUSD.sol";

contract Vault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice TITAN token
    IERC20 public immutable titan;

    /// @notice tUSD stablecoin
    TitanUSD public immutable tusd;

    /// @notice TITAN price in USD (8 decimals, e.g., 10000000 = $0.10)
    uint256 public titanPrice;

    /// @notice Minimum Collateral Ratio (e.g., 15000 = 150%)
    uint256 public constant MCR = 15000; // 150%

    /// @notice Liquidation threshold (e.g., 11000 = 110%)
    uint256 public constant LIQUIDATION_THRESHOLD = 11000; // 110%

    /// @notice Liquidation bonus for liquidators (e.g., 1000 = 10%)
    uint256 public constant LIQUIDATION_BONUS = 1000; // 10%

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Price decimals
    uint256 public constant PRICE_DECIMALS = 8;

    /// @notice Minimum debt amount to prevent dust
    uint256 public constant MIN_DEBT = 10 * 1e18; // 10 tUSD minimum

    // ============ Position Storage ============

    struct Position {
        uint256 collateral;  // TITAN deposited
        uint256 debt;        // tUSD borrowed
    }

    /// @notice User positions
    mapping(address => Position) public positions;

    /// @notice Total collateral in the system
    uint256 public totalCollateral;

    /// @notice Total debt in the system
    uint256 public totalDebt;

    // ============ Events ============

    event CollateralDeposited(address indexed user, uint256 amount, uint256 totalCollateral);
    event CollateralWithdrawn(address indexed user, uint256 amount, uint256 totalCollateral);
    event DebtMinted(address indexed user, uint256 amount, uint256 totalDebt);
    event DebtRepaid(address indexed user, uint256 amount, uint256 totalDebt);
    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        uint256 debtRepaid,
        uint256 collateralSeized
    );
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);

    // ============ Errors ============

    error ZeroAmount();
    error InsufficientCollateral();
    error InsufficientDebt();
    error BelowMCR();
    error NotLiquidatable();
    error DebtTooLow();
    error NoPosition();
    error InvalidPrice();

    // ============ Constructor ============

    /**
     * @notice Constructs the Vault
     * @param _titan TITAN token address
     * @param _tusd tUSD token address
     * @param _initialPrice Initial TITAN price (8 decimals)
     * @param _owner Contract owner
     */
    constructor(
        address _titan,
        address _tusd,
        uint256 _initialPrice,
        address _owner
    ) Ownable(_owner) {
        titan = IERC20(_titan);
        tusd = TitanUSD(_tusd);
        titanPrice = _initialPrice;
    }

    // ============ View Functions ============

    /**
     * @notice Get user's position details
     * @param user User address
     * @return collateral Amount of TITAN deposited
     * @return debt Amount of tUSD borrowed
     * @return collateralValue USD value of collateral (18 decimals)
     * @return collateralRatio Current collateral ratio (basis points)
     * @return maxBorrow Maximum additional tUSD that can be borrowed
     */
    function getPosition(address user) external view returns (
        uint256 collateral,
        uint256 debt,
        uint256 collateralValue,
        uint256 collateralRatio,
        uint256 maxBorrow
    ) {
        Position memory pos = positions[user];
        collateral = pos.collateral;
        debt = pos.debt;
        collateralValue = _getCollateralValue(collateral);
        collateralRatio = debt > 0 ? (collateralValue * BASIS_POINTS) / debt : type(uint256).max;

        uint256 maxDebt = (collateralValue * BASIS_POINTS) / MCR;
        maxBorrow = maxDebt > debt ? maxDebt - debt : 0;
    }

    /**
     * @notice Check if a position is liquidatable
     * @param user User address
     * @return True if position can be liquidated
     */
    function isLiquidatable(address user) public view returns (bool) {
        Position memory pos = positions[user];
        if (pos.debt == 0) return false;

        uint256 collateralValue = _getCollateralValue(pos.collateral);
        uint256 ratio = (collateralValue * BASIS_POINTS) / pos.debt;
        return ratio < LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Get collateral value in USD (18 decimals)
     * @param collateralAmount Amount of TITAN
     * @return USD value with 18 decimals
     */
    function getCollateralValue(uint256 collateralAmount) external view returns (uint256) {
        return _getCollateralValue(collateralAmount);
    }

    /**
     * @notice Calculate max borrowable amount for given collateral
     * @param collateralAmount Amount of TITAN
     * @return Maximum tUSD that can be borrowed
     */
    function maxBorrowAmount(uint256 collateralAmount) external view returns (uint256) {
        uint256 collateralValue = _getCollateralValue(collateralAmount);
        return (collateralValue * BASIS_POINTS) / MCR;
    }

    // ============ User Functions ============

    /**
     * @notice Deposit TITAN collateral
     * @param amount Amount of TITAN to deposit
     */
    function depositCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        titan.safeTransferFrom(msg.sender, address(this), amount);

        positions[msg.sender].collateral += amount;
        totalCollateral += amount;

        emit CollateralDeposited(msg.sender, amount, positions[msg.sender].collateral);
    }

    /**
     * @notice Withdraw TITAN collateral
     * @param amount Amount of TITAN to withdraw
     */
    function withdrawCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        Position storage pos = positions[msg.sender];
        if (pos.collateral < amount) revert InsufficientCollateral();

        // Check if withdrawal would put position below MCR
        uint256 newCollateral = pos.collateral - amount;
        if (pos.debt > 0) {
            uint256 newCollateralValue = _getCollateralValue(newCollateral);
            uint256 newRatio = (newCollateralValue * BASIS_POINTS) / pos.debt;
            if (newRatio < MCR) revert BelowMCR();
        }

        pos.collateral = newCollateral;
        totalCollateral -= amount;

        titan.safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, amount, pos.collateral);
    }

    /**
     * @notice Borrow tUSD against collateral
     * @param amount Amount of tUSD to borrow
     */
    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        Position storage pos = positions[msg.sender];
        if (pos.collateral == 0) revert NoPosition();

        uint256 newDebt = pos.debt + amount;
        if (newDebt < MIN_DEBT) revert DebtTooLow();

        // Check collateral ratio
        uint256 collateralValue = _getCollateralValue(pos.collateral);
        uint256 newRatio = (collateralValue * BASIS_POINTS) / newDebt;
        if (newRatio < MCR) revert BelowMCR();

        pos.debt = newDebt;
        totalDebt += amount;

        tusd.mint(msg.sender, amount);

        emit DebtMinted(msg.sender, amount, pos.debt);
    }

    /**
     * @notice Repay tUSD debt
     * @param amount Amount of tUSD to repay
     */
    function repay(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        Position storage pos = positions[msg.sender];
        if (pos.debt == 0) revert InsufficientDebt();

        uint256 repayAmount = amount > pos.debt ? pos.debt : amount;
        uint256 newDebt = pos.debt - repayAmount;

        // Ensure remaining debt is either 0 or above minimum
        if (newDebt > 0 && newDebt < MIN_DEBT) revert DebtTooLow();

        pos.debt = newDebt;
        totalDebt -= repayAmount;

        tusd.burnFrom(msg.sender, repayAmount);

        emit DebtRepaid(msg.sender, repayAmount, pos.debt);
    }

    /**
     * @notice Deposit collateral and borrow in one transaction
     * @param collateralAmount Amount of TITAN to deposit
     * @param borrowAmount Amount of tUSD to borrow
     */
    function depositAndBorrow(uint256 collateralAmount, uint256 borrowAmount) external nonReentrant {
        if (collateralAmount == 0) revert ZeroAmount();
        if (borrowAmount == 0) revert ZeroAmount();
        if (borrowAmount < MIN_DEBT) revert DebtTooLow();

        titan.safeTransferFrom(msg.sender, address(this), collateralAmount);

        Position storage pos = positions[msg.sender];
        pos.collateral += collateralAmount;
        totalCollateral += collateralAmount;

        uint256 newDebt = pos.debt + borrowAmount;
        uint256 collateralValue = _getCollateralValue(pos.collateral);
        uint256 newRatio = (collateralValue * BASIS_POINTS) / newDebt;
        if (newRatio < MCR) revert BelowMCR();

        pos.debt = newDebt;
        totalDebt += borrowAmount;

        tusd.mint(msg.sender, borrowAmount);

        emit CollateralDeposited(msg.sender, collateralAmount, pos.collateral);
        emit DebtMinted(msg.sender, borrowAmount, pos.debt);
    }

    /**
     * @notice Repay all debt and withdraw all collateral
     */
    function closePosition() external nonReentrant {
        Position storage pos = positions[msg.sender];
        if (pos.collateral == 0 && pos.debt == 0) revert NoPosition();

        uint256 debt = pos.debt;
        uint256 collateral = pos.collateral;

        if (debt > 0) {
            tusd.burnFrom(msg.sender, debt);
            totalDebt -= debt;
            pos.debt = 0;
        }

        if (collateral > 0) {
            pos.collateral = 0;
            totalCollateral -= collateral;
            titan.safeTransfer(msg.sender, collateral);
        }

        emit DebtRepaid(msg.sender, debt, 0);
        emit CollateralWithdrawn(msg.sender, collateral, 0);
    }

    // ============ Liquidation ============

    /**
     * @notice Liquidate an undercollateralized position
     * @param user Address of the position to liquidate
     * @param debtToRepay Amount of debt to repay
     */
    function liquidate(address user, uint256 debtToRepay) external nonReentrant {
        if (!isLiquidatable(user)) revert NotLiquidatable();
        if (debtToRepay == 0) revert ZeroAmount();

        Position storage pos = positions[user];
        uint256 actualDebtToRepay = debtToRepay > pos.debt ? pos.debt : debtToRepay;

        // Calculate collateral to seize (debt value + liquidation bonus)
        // collateralToSeize = (debtToRepay * (1 + bonus)) / titanPrice
        uint256 collateralValue = (actualDebtToRepay * (BASIS_POINTS + LIQUIDATION_BONUS)) / BASIS_POINTS;
        uint256 collateralToSeize = (collateralValue * 10 ** PRICE_DECIMALS * 1e18) / (titanPrice * 1e18);

        // Cap at available collateral
        if (collateralToSeize > pos.collateral) {
            collateralToSeize = pos.collateral;
        }

        // Update position
        pos.debt -= actualDebtToRepay;
        pos.collateral -= collateralToSeize;
        totalDebt -= actualDebtToRepay;
        totalCollateral -= collateralToSeize;

        // Burn repaid tUSD from liquidator
        tusd.burnFrom(msg.sender, actualDebtToRepay);

        // Transfer collateral to liquidator
        titan.safeTransfer(msg.sender, collateralToSeize);

        emit PositionLiquidated(user, msg.sender, actualDebtToRepay, collateralToSeize);
    }

    // ============ Admin Functions ============

    /**
     * @notice Update TITAN price (for testnet - would use oracle in production)
     * @param newPrice New price (8 decimals)
     */
    function setPrice(uint256 newPrice) external onlyOwner {
        if (newPrice == 0) revert InvalidPrice();
        uint256 oldPrice = titanPrice;
        titanPrice = newPrice;
        emit PriceUpdated(oldPrice, newPrice);
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculate collateral value in USD
     * @param collateralAmount Amount of TITAN (18 decimals)
     * @return USD value (18 decimals)
     */
    function _getCollateralValue(uint256 collateralAmount) internal view returns (uint256) {
        // collateralAmount is 18 decimals, titanPrice is 8 decimals
        // Result should be 18 decimals (tUSD has 18 decimals)
        return (collateralAmount * titanPrice) / (10 ** PRICE_DECIMALS);
    }
}
