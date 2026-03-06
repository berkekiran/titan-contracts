// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Farm
 * @author Titan Team
 * @notice Yield farming contract for LP tokens
 * @dev Implements secure farming with protected LP token withdrawals
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Farm
 * @notice Stake LP tokens and earn TITAN rewards across multiple pools
 * @dev Supports multiple pools with configurable allocation points
 */
contract Farm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Info of each user
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided
        uint256 rewardDebt; // Reward debt
    }

    /// @notice Info of each pool
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract
        uint256 allocPoint;       // How many allocation points assigned to this pool
        uint256 lastRewardTime;   // Last timestamp that TITAN distribution occurred
        uint256 accTitanPerShare; // Accumulated TITAN per share, times 1e12
        uint256 totalStaked;      // Total LP tokens staked in this pool
        bool isActive;            // Whether the pool is active
    }

    /// @notice The TITAN token
    IERC20 public immutable titanToken;

    /// @notice TITAN tokens distributed per second
    uint256 public titanPerSecond;

    /// @notice Info of each pool
    PoolInfo[] public poolInfo;

    /// @notice Info of each user that stakes LP tokens
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice Total allocation points. Must be the sum of all allocation points in all pools
    uint256 public totalAllocPoint;

    /// @notice Mapping to check if LP token already has a pool
    mapping(address => bool) public lpTokenExists;

    /// @notice Maximum number of pools
    uint256 public constant MAX_POOLS = 100;

    /// @notice Emitted when a user deposits LP tokens
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a user withdraws LP tokens
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a user emergency withdraws without rewards
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when rewards are harvested
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a new pool is added
    event PoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);

    /// @notice Emitted when a pool is updated
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint, bool isActive);

    /// @notice Emitted when titanPerSecond is updated
    event TitanPerSecondUpdated(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when reward tokens are deposited
    event RewardsDeposited(address indexed depositor, uint256 amount);

    /// @notice Emitted when excess rewards are withdrawn
    event ExcessRewardsWithdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when rewards are capped due to insufficient balance
    event RewardsCapped(address indexed user, uint256 requested, uint256 actual);

    /// @notice Error definitions
    error InvalidToken();
    error InvalidLPToken();
    error LPTokenAlreadyAdded();
    error InvalidPoolId();
    error PoolNotActive();
    error InsufficientBalance();
    error NothingToHarvest();
    error TooManyPools();
    error InsufficientRewardBalance();

    /**
     * @notice Constructs the Farm contract
     * @param _titanToken Address of the TITAN token
     * @param _titanPerSecond TITAN tokens distributed per second
     * @param _owner Address of the contract owner
     */
    constructor(address _titanToken, uint256 _titanPerSecond, address _owner) Ownable(_owner) {
        if (_titanToken == address(0)) revert InvalidToken();
        titanToken = IERC20(_titanToken);
        titanPerSecond = _titanPerSecond;
    }

    /**
     * @notice Returns the number of pools
     * @return Number of pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @notice Add a new LP pool
     * @param allocPoint Allocation points for the new pool
     * @param lpToken Address of the LP token
     * @param withUpdate Whether to update all pools
     */
    function addPool(uint256 allocPoint, address lpToken, bool withUpdate) external onlyOwner {
        if (lpToken == address(0)) revert InvalidLPToken();
        if (lpTokenExists[lpToken]) revert LPTokenAlreadyAdded();
        if (poolInfo.length >= MAX_POOLS) revert TooManyPools();

        if (withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardTime = block.timestamp;
        totalAllocPoint += allocPoint;
        lpTokenExists[lpToken] = true;

        poolInfo.push(
            PoolInfo({
                lpToken: IERC20(lpToken),
                allocPoint: allocPoint,
                lastRewardTime: lastRewardTime,
                accTitanPerShare: 0,
                totalStaked: 0,
                isActive: true
            })
        );

        emit PoolAdded(poolInfo.length - 1, lpToken, allocPoint);
    }

    /**
     * @notice Update the given pool's allocation points and active status
     * @param pid The pool ID
     * @param allocPoint New allocation points
     * @param isActive Whether the pool is active
     * @param withUpdate Whether to update all pools
     */
    function setPool(
        uint256 pid,
        uint256 allocPoint,
        bool isActive,
        bool withUpdate
    ) external onlyOwner {
        if (pid >= poolInfo.length) revert InvalidPoolId();

        if (withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint - poolInfo[pid].allocPoint + allocPoint;
        poolInfo[pid].allocPoint = allocPoint;
        poolInfo[pid].isActive = isActive;

        emit PoolUpdated(pid, allocPoint, isActive);
    }

    /**
     * @notice Update titanPerSecond
     * @param newTitanPerSecond New titan per second rate
     */
    function setTitanPerSecond(uint256 newTitanPerSecond) external onlyOwner {
        massUpdatePools();
        uint256 oldRate = titanPerSecond;
        titanPerSecond = newTitanPerSecond;
        emit TitanPerSecondUpdated(oldRate, newTitanPerSecond);
    }

    /**
     * @notice Deposit reward tokens
     * @param amount Amount to deposit
     */
    function depositRewards(uint256 amount) external {
        titanToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsDeposited(msg.sender, amount);
    }

    /**
     * @notice View function to see pending TITAN on frontend
     * @param pid The pool ID
     * @param account The user address
     * @return Pending TITAN rewards
     */
    function pendingTitan(uint256 pid, address account) external view returns (uint256) {
        if (pid >= poolInfo.length) revert InvalidPoolId();
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][account];
        uint256 accTitanPerShare = pool.accTitanPerShare;
        uint256 lpSupply = pool.totalStaked;

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0 && totalAllocPoint > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
            // Use mulDiv to prevent precision loss from divide-before-multiply
            uint256 titanReward = Math.mulDiv(
                timeElapsed * titanPerSecond,
                pool.allocPoint,
                totalAllocPoint
            );
            accTitanPerShare = accTitanPerShare + Math.mulDiv(titanReward, 1e12, lpSupply);
        }

        return (user.amount * accTitanPerShare) / 1e12 - user.rewardDebt;
    }

    /**
     * @notice Update reward variables for all pools
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @notice Update reward variables of the given pool
     * @param pid The pool ID
     */
    function updatePool(uint256 pid) public {
        if (pid >= poolInfo.length) revert InvalidPoolId();
        PoolInfo storage pool = poolInfo[pid];

        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 lpSupply = pool.totalStaked;
        if (lpSupply == 0 || !pool.isActive || totalAllocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        // Use mulDiv to prevent precision loss from divide-before-multiply
        uint256 titanReward = Math.mulDiv(
            timeElapsed * titanPerSecond,
            pool.allocPoint,
            totalAllocPoint
        );
        pool.accTitanPerShare = pool.accTitanPerShare + Math.mulDiv(titanReward, 1e12, lpSupply);
        pool.lastRewardTime = block.timestamp;
    }

    /**
     * @notice Deposit LP tokens to earn TITAN
     * @param pid The pool ID
     * @param amount Amount of LP tokens to deposit
     */
    function deposit(uint256 pid, uint256 amount) external nonReentrant {
        if (pid >= poolInfo.length) revert InvalidPoolId();
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        if (!pool.isActive) revert PoolNotActive();

        updatePool(pid);

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accTitanPerShare) / 1e12 - user.rewardDebt;
            if (pending > 0) {
                _safeTitanTransfer(msg.sender, pending);
                emit Harvest(msg.sender, pid, pending);
            }
        }

        if (amount > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), amount);
            user.amount += amount;
            pool.totalStaked += amount;
        }

        user.rewardDebt = (user.amount * pool.accTitanPerShare) / 1e12;
        emit Deposit(msg.sender, pid, amount);
    }

    /**
     * @notice Withdraw LP tokens
     * @param pid The pool ID
     * @param amount Amount of LP tokens to withdraw
     */
    function withdraw(uint256 pid, uint256 amount) external nonReentrant {
        if (pid >= poolInfo.length) revert InvalidPoolId();
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        if (user.amount < amount) revert InsufficientBalance();

        updatePool(pid);

        uint256 pending = (user.amount * pool.accTitanPerShare) / 1e12 - user.rewardDebt;
        if (pending > 0) {
            _safeTitanTransfer(msg.sender, pending);
            emit Harvest(msg.sender, pid, pending);
        }

        if (amount > 0) {
            user.amount -= amount;
            pool.totalStaked -= amount;
            pool.lpToken.safeTransfer(msg.sender, amount);
        }

        user.rewardDebt = (user.amount * pool.accTitanPerShare) / 1e12;
        emit Withdraw(msg.sender, pid, amount);
    }

    /**
     * @notice Harvest rewards from a pool
     * @param pid The pool ID
     */
    function harvest(uint256 pid) external nonReentrant {
        if (pid >= poolInfo.length) revert InvalidPoolId();
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        updatePool(pid);

        uint256 pending = (user.amount * pool.accTitanPerShare) / 1e12 - user.rewardDebt;
        if (pending == 0) revert NothingToHarvest();

        user.rewardDebt = (user.amount * pool.accTitanPerShare) / 1e12;
        _safeTitanTransfer(msg.sender, pending);
        emit Harvest(msg.sender, pid, pending);
    }

    /**
     * @notice Emergency withdraw without caring about rewards
     * @param pid The pool ID
     */
    function emergencyWithdraw(uint256 pid) external nonReentrant {
        if (pid >= poolInfo.length) revert InvalidPoolId();
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;

        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount);
    }

    /**
     * @notice Get available reward tokens (not staked LP tokens)
     * @return Available reward tokens
     */
    function availableRewardBalance() public view returns (uint256) {
        return titanToken.balanceOf(address(this));
    }

    /**
     * @notice Safe TITAN transfer function, in case rounding error causes pool to not have enough TITAN
     * @param _to Address to transfer to
     * @param _amount Amount to transfer
     */
    function _safeTitanTransfer(address _to, uint256 _amount) internal {
        uint256 titanBal = titanToken.balanceOf(address(this));
        if (_amount > titanBal) {
            emit RewardsCapped(_to, _amount, titanBal);
            titanToken.safeTransfer(_to, titanBal);
        } else {
            titanToken.safeTransfer(_to, _amount);
        }
    }

    /**
     * @notice Emergency withdrawal of reward tokens by owner
     * @dev Only allows withdrawing TITAN tokens, NOT LP tokens
     * @param amount Amount to withdraw
     */
    function emergencyRewardWithdraw(uint256 amount) external onlyOwner {
        uint256 available = titanToken.balanceOf(address(this));
        if (amount > available) revert InsufficientRewardBalance();

        titanToken.safeTransfer(owner(), amount);
        emit ExcessRewardsWithdrawn(owner(), amount);
    }
}
