// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Earn
 * @author Titan Team
 * @notice Earn rewards by staking TITAN tokens
 * @dev Implements secure staking with protected emergency withdrawal
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Earn
 * @notice Stake TITAN tokens and earn TITAN rewards
 * @dev Simple staking with configurable reward rate and no lockup period
 */
contract Earn is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The TITAN token used for staking and rewards
    IERC20 public immutable titanToken;

    /// @notice Reward rate per second per token staked (scaled by 1e18)
    uint256 public rewardRate;

    /// @notice Last time reward variables were updated
    uint256 public lastUpdateTime;

    /// @notice Accumulated rewards per token (scaled by 1e18)
    uint256 public rewardPerTokenStored;

    /// @notice Total amount of tokens staked
    uint256 public totalStaked;

    /// @notice Mapping of user address to their staked amount
    mapping(address => uint256) public stakedBalance;

    /// @notice User's reward per token paid
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice User's pending rewards
    mapping(address => uint256) public rewards;

    /// @notice Whether the contract is paused
    bool public paused;

    /// @notice Emitted when a user stakes tokens
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user unstakes tokens
    event Unstaked(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims rewards
    event RewardsClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when the reward rate is updated
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when paused state changes
    event PausedStateChanged(bool paused);

    /// @notice Emitted when rewards are deposited
    event RewardsDeposited(address indexed depositor, uint256 amount);

    /// @notice Emitted when excess rewards are withdrawn
    event ExcessRewardsWithdrawn(address indexed to, uint256 amount);

    /// @notice Error definitions
    error InvalidToken();
    error CannotStakeZero();
    error CannotUnstakeZero();
    error InsufficientBalance();
    error NoRewardsToClaim();
    error ContractPaused();
    error InsufficientRewardBalance();

    /**
     * @notice Constructs the Earn contract
     * @param _titanToken Address of the TITAN token
     * @param _rewardRate Initial reward rate per second per token (scaled by 1e18)
     * @param _owner Address of the contract owner
     */
    constructor(address _titanToken, uint256 _rewardRate, address _owner) Ownable(_owner) {
        if (_titanToken == address(0)) revert InvalidToken();
        titanToken = IERC20(_titanToken);
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Modifier to check if contract is not paused
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /**
     * @notice Updates the reward rate
     * @dev Only callable by owner. Updates rewards before changing rate
     * @param newRewardRate New reward rate per second per token
     */
    function setRewardRate(uint256 newRewardRate) external onlyOwner {
        _updateRewardPerToken();
        uint256 oldRate = rewardRate;
        rewardRate = newRewardRate;
        emit RewardRateUpdated(oldRate, newRewardRate);
    }

    /**
     * @notice Pause or unpause the contract
     * @param isPaused Whether to pause
     */
    function setPaused(bool isPaused) external onlyOwner {
        paused = isPaused;
        emit PausedStateChanged(isPaused);
    }

    /**
     * @notice Calculates current reward per token
     * @return Current accumulated reward per token
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((block.timestamp - lastUpdateTime) * rewardRate * 1e18) / totalStaked;
    }

    /**
     * @notice Calculates pending rewards for an account
     * @param account The address to calculate rewards for
     * @return The amount of pending rewards
     */
    function earned(address account) public view returns (uint256) {
        return
            (stakedBalance[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 +
            rewards[account];
    }

    /**
     * @notice Get available reward tokens (balance minus staked)
     * @return Available reward tokens
     */
    function availableRewards() public view returns (uint256) {
        uint256 balance = titanToken.balanceOf(address(this));
        return balance > totalStaked ? balance - totalStaked : 0;
    }

    /**
     * @notice Stakes TITAN tokens
     * @param amount The amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert CannotStakeZero();
        _updateReward(msg.sender);

        totalStaked += amount;
        stakedBalance[msg.sender] += amount;

        titanToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstakes TITAN tokens
     * @param amount The amount of tokens to unstake
     */
    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert CannotUnstakeZero();
        if (stakedBalance[msg.sender] < amount) revert InsufficientBalance();
        _updateReward(msg.sender);

        totalStaked -= amount;
        stakedBalance[msg.sender] -= amount;

        titanToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claims pending rewards
     */
    function claimRewards() external nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward == 0) revert NoRewardsToClaim();

        // Check if contract has enough reward tokens
        if (availableRewards() < reward) revert InsufficientRewardBalance();

        rewards[msg.sender] = 0;
        titanToken.safeTransfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    /**
     * @notice Unstakes all tokens and claims all rewards
     */
    function exit() external nonReentrant {
        _updateReward(msg.sender);
        uint256 stakedAmount = stakedBalance[msg.sender];
        uint256 reward = rewards[msg.sender];

        if (stakedAmount > 0) {
            totalStaked -= stakedAmount;
            stakedBalance[msg.sender] = 0;
            titanToken.safeTransfer(msg.sender, stakedAmount);
            emit Unstaked(msg.sender, stakedAmount);
        }

        if (reward > 0 && availableRewards() >= reward) {
            rewards[msg.sender] = 0;
            titanToken.safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, reward);
        }
    }

    /**
     * @notice Deposit reward tokens into the contract
     * @param amount Amount to deposit
     */
    function depositRewards(uint256 amount) external {
        titanToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsDeposited(msg.sender, amount);
    }

    /**
     * @notice Updates the global reward per token
     */
    function _updateRewardPerToken() internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Updates rewards for a specific account
     * @param account The address to update rewards for
     */
    function _updateReward(address account) internal {
        _updateRewardPerToken();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /**
     * @notice Emergency withdrawal of excess reward tokens by owner
     * @dev Only allows withdrawing tokens not staked by users
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        uint256 available = availableRewards();
        if (amount > available) revert InsufficientRewardBalance();

        titanToken.safeTransfer(owner(), amount);
        emit ExcessRewardsWithdrawn(owner(), amount);
    }
}
