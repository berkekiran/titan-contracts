// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title StakedTitan (sTitan)
 * @author Titan Team
 * @notice Liquid staking token for TITAN with auto-compounding rewards
 * @dev Exchange rate model - sTitan appreciates in value as rewards accrue automatically
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StakedTitan
 * @notice Stake TITAN and receive sTitan - a liquid staking token with auto-compounding
 * @dev Uses exchange rate model where sTitan value increases over time based on rewardRate
 *
 * How it works:
 * - Deposit TITAN → receive sTitan based on current exchange rate
 * - Exchange rate increases automatically over time based on rewardRate
 * - Withdraw sTitan → receive TITAN at current exchange rate (more than deposited)
 *
 * Example:
 * - Day 1: Deposit 100 TITAN, get 100 sTitan (rate = 1.0)
 * - Day 30: Rate increased to 1.025 (2.5% monthly)
 * - Withdraw 100 sTitan → receive 102.5 TITAN
 */
contract StakedTitan is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The TITAN token
    IERC20 public immutable titan;

    /// @notice Minimum deposit amount to prevent rounding issues
    uint256 public constant MINIMUM_DEPOSIT = 1e15; // 0.001 TITAN

    /// @notice Reward rate per second per total staked (scaled by 1e18)
    /// @dev Example: 1e15 = 0.1% per second, ~31.5% APY
    uint256 public rewardRate;

    /// @notice Last time rewards were accrued
    uint256 public lastRewardTime;

    /// @notice Virtual total TITAN (actual balance + accrued rewards)
    /// @dev This increases over time based on rewardRate
    uint256 public totalTitanAccrued;

    /// @notice Whether deposits are paused
    bool public depositsPaused;

    /// @notice Whether withdrawals are paused
    bool public withdrawalsPaused;

    /// @notice Emitted when TITAN is deposited
    event Deposited(address indexed user, uint256 titanAmount, uint256 sTitanAmount);

    /// @notice Emitted when sTitan is withdrawn
    event Withdrawn(address indexed user, uint256 sTitanAmount, uint256 titanAmount);

    /// @notice Emitted when rewards are accrued
    event RewardsAccrued(uint256 amount, uint256 newExchangeRate);

    /// @notice Emitted when reward rate is updated
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when rewards are deposited
    event RewardsDeposited(address indexed from, uint256 amount);

    /// @notice Emitted when pause state changes
    event DepositsPausedChanged(bool paused);
    event WithdrawalsPausedChanged(bool paused);

    /// @notice Error definitions
    error InvalidToken();
    error DepositTooSmall();
    error InsufficientBalance();
    error DepositsPaused();
    error WithdrawalsPaused();
    error ZeroAmount();
    error ZeroShares();
    error InsufficientRewards();

    /**
     * @notice Constructs the StakedTitan contract
     * @param _titan Address of the TITAN token
     * @param _rewardRate Initial reward rate per second (scaled by 1e18)
     * @param _owner Address of the contract owner
     */
    constructor(
        address _titan,
        uint256 _rewardRate,
        address _owner
    ) ERC20("Staked Titan", "sTITAN") Ownable(_owner) {
        if (_titan == address(0)) revert InvalidToken();
        titan = IERC20(_titan);
        rewardRate = _rewardRate;
        lastRewardTime = block.timestamp;
    }

    /**
     * @notice Accrue rewards based on time elapsed
     * @dev Called automatically before any state-changing operation
     */
    function _accrueRewards() internal {
        if (totalSupply() == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastRewardTime;
        if (timeElapsed == 0) return;

        // Calculate new rewards: totalTitan * rewardRate * timeElapsed / 1e18
        uint256 currentTotal = totalTitanAccrued > 0 ? totalTitanAccrued : titan.balanceOf(address(this));
        uint256 newRewards = (currentTotal * rewardRate * timeElapsed) / 1e18;

        // Cap rewards to actual balance
        uint256 actualBalance = titan.balanceOf(address(this));
        uint256 maxRewards = actualBalance > currentTotal ? actualBalance - currentTotal : 0;

        if (newRewards > maxRewards) {
            newRewards = maxRewards;
        }

        if (newRewards > 0) {
            totalTitanAccrued = currentTotal + newRewards;
            emit RewardsAccrued(newRewards, exchangeRate());
        }

        lastRewardTime = block.timestamp;
    }

    /**
     * @notice Get the current exchange rate (TITAN per sTitan)
     * @return Exchange rate scaled by 1e18
     * @dev Returns 1e18 if no sTitan exists yet
     */
    function exchangeRate() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 1e18; // 1:1 initially
        }

        // Calculate pending rewards
        uint256 currentTotal = totalTitanAccrued > 0 ? totalTitanAccrued : titan.balanceOf(address(this));
        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 pendingRewards = (currentTotal * rewardRate * timeElapsed) / 1e18;

        // Cap to actual balance
        uint256 actualBalance = titan.balanceOf(address(this));
        uint256 maxRewards = actualBalance > currentTotal ? actualBalance - currentTotal : 0;
        if (pendingRewards > maxRewards) {
            pendingRewards = maxRewards;
        }

        uint256 totalWithPending = currentTotal + pendingRewards;
        return (totalWithPending * 1e18) / supply;
    }

    /**
     * @notice Get the total TITAN backing all sTitan (including pending rewards)
     * @return Total TITAN value
     */
    function totalTitan() external view returns (uint256) {
        uint256 currentTotal = totalTitanAccrued > 0 ? totalTitanAccrued : titan.balanceOf(address(this));
        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 pendingRewards = (currentTotal * rewardRate * timeElapsed) / 1e18;

        uint256 actualBalance = titan.balanceOf(address(this));
        uint256 maxRewards = actualBalance > currentTotal ? actualBalance - currentTotal : 0;
        if (pendingRewards > maxRewards) {
            pendingRewards = maxRewards;
        }

        return currentTotal + pendingRewards;
    }

    /**
     * @notice Preview how much sTitan you would receive for a TITAN deposit
     * @param titanAmount Amount of TITAN to deposit
     * @return Amount of sTitan that would be minted
     */
    function previewDeposit(uint256 titanAmount) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return titanAmount; // 1:1 for first deposit
        }
        // sTitan = titanAmount * totalSupply / totalTitan
        uint256 rate = exchangeRate();
        return (titanAmount * 1e18) / rate;
    }

    /**
     * @notice Preview how much TITAN you would receive for an sTitan withdrawal
     * @param sTitanAmount Amount of sTitan to withdraw
     * @return Amount of TITAN that would be returned
     */
    function previewWithdraw(uint256 sTitanAmount) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 0;
        }
        // TITAN = sTitanAmount * exchangeRate / 1e18
        return (sTitanAmount * exchangeRate()) / 1e18;
    }

    /**
     * @notice Deposit TITAN and receive sTitan
     * @param titanAmount Amount of TITAN to deposit
     * @return sTitanAmount Amount of sTitan minted
     */
    function deposit(uint256 titanAmount) external nonReentrant returns (uint256 sTitanAmount) {
        if (depositsPaused) revert DepositsPaused();
        if (titanAmount == 0) revert ZeroAmount();
        if (titanAmount < MINIMUM_DEPOSIT) revert DepositTooSmall();

        // Accrue rewards first
        _accrueRewards();

        sTitanAmount = previewDeposit(titanAmount);
        if (sTitanAmount == 0) revert ZeroShares();

        // Transfer TITAN in first (checks-effects-interactions)
        titan.safeTransferFrom(msg.sender, address(this), titanAmount);

        // Update total accrued
        totalTitanAccrued += titanAmount;

        // Mint sTitan to user
        _mint(msg.sender, sTitanAmount);

        emit Deposited(msg.sender, titanAmount, sTitanAmount);
    }

    /**
     * @notice Withdraw TITAN by burning sTitan
     * @param sTitanAmount Amount of sTitan to burn
     * @return titanAmount Amount of TITAN returned
     */
    function withdraw(uint256 sTitanAmount) external nonReentrant returns (uint256 titanAmount) {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        if (sTitanAmount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < sTitanAmount) revert InsufficientBalance();

        // Accrue rewards first
        _accrueRewards();

        titanAmount = previewWithdraw(sTitanAmount);
        if (titanAmount == 0) revert ZeroAmount();
        if (titan.balanceOf(address(this)) < titanAmount) revert InsufficientRewards();

        // Update total accrued
        totalTitanAccrued -= titanAmount;

        // Burn sTitan first (checks-effects-interactions)
        _burn(msg.sender, sTitanAmount);

        // Transfer TITAN to user
        titan.safeTransfer(msg.sender, titanAmount);

        emit Withdrawn(msg.sender, sTitanAmount, titanAmount);
    }

    /**
     * @notice Withdraw all sTitan
     * @return titanAmount Amount of TITAN returned
     */
    function withdrawAll() external nonReentrant returns (uint256 titanAmount) {
        if (withdrawalsPaused) revert WithdrawalsPaused();

        uint256 sTitanAmount = balanceOf(msg.sender);
        if (sTitanAmount == 0) revert ZeroAmount();

        // Accrue rewards first
        _accrueRewards();

        titanAmount = previewWithdraw(sTitanAmount);
        if (titanAmount == 0) revert ZeroAmount();
        if (titan.balanceOf(address(this)) < titanAmount) revert InsufficientRewards();

        // Update total accrued
        totalTitanAccrued -= titanAmount;

        _burn(msg.sender, sTitanAmount);
        titan.safeTransfer(msg.sender, titanAmount);

        emit Withdrawn(msg.sender, sTitanAmount, titanAmount);
    }

    /**
     * @notice Deposit reward tokens to fund future rewards
     * @param amount Amount of TITAN to deposit as rewards
     * @dev These tokens will be distributed over time based on rewardRate
     */
    function depositRewards(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _accrueRewards();
        titan.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsDeposited(msg.sender, amount);
    }

    /**
     * @notice Update the reward rate
     * @param newRate New reward rate per second (scaled by 1e18)
     */
    function setRewardRate(uint256 newRate) external onlyOwner {
        _accrueRewards();

        uint256 oldRate = rewardRate;
        rewardRate = newRate;

        emit RewardRateUpdated(oldRate, newRate);
    }

    /**
     * @notice Pause or unpause deposits
     * @param paused Whether to pause deposits
     */
    function setDepositsPaused(bool paused) external onlyOwner {
        depositsPaused = paused;
        emit DepositsPausedChanged(paused);
    }

    /**
     * @notice Pause or unpause withdrawals
     * @param paused Whether to pause withdrawals
     */
    function setWithdrawalsPaused(bool paused) external onlyOwner {
        withdrawalsPaused = paused;
        emit WithdrawalsPausedChanged(paused);
    }

    /**
     * @notice Get the TITAN value of an account's sTitan holdings
     * @param account Address to check
     * @return TITAN value of the account's sTitan
     */
    function titanBalanceOf(address account) external view returns (uint256) {
        return previewWithdraw(balanceOf(account));
    }

    /**
     * @notice Get available reward balance (tokens beyond what's owed to stakers)
     * @return Available rewards that can fund future distributions
     */
    function availableRewards() external view returns (uint256) {
        uint256 balance = titan.balanceOf(address(this));
        uint256 owed = totalTitanAccrued > 0 ? totalTitanAccrued : 0;
        return balance > owed ? balance - owed : 0;
    }

    /**
     * @notice Get current APY based on reward rate
     * @return APY scaled by 100 (e.g., 3000 = 30%)
     */
    function currentAPY() external view returns (uint256) {
        // APY = (1 + rewardRate)^(seconds per year) - 1
        // Simplified: APY ≈ rewardRate * seconds per year * 100 / 1e18
        return (rewardRate * 365 days * 100) / 1e18;
    }
}
