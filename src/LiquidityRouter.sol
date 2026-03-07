// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPoolManager.sol";
import "./interfaces/IStateView.sol";
import "./libraries/TickMath.sol";
import "./libraries/LiquidityAmounts.sol";

/**
 * @title LiquidityRouter
 * @author Titan Team
 * @notice Liquidity router for Uniswap V4 pools
 * @dev Handles pool initialization and liquidity management via PoolManager unlock callback
 *      Uses proper Uniswap math to calculate liquidity from token amounts
 */
contract LiquidityRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;
    IStateView public immutable stateView;

    // Default initial sqrtPriceX96 for new pools (price = 1)
    uint160 internal constant DEFAULT_SQRT_PRICE_X96 = 79228162514264337593543950336;

    // Action types for unlock callback
    uint8 internal constant ACTION_ADD_LIQUIDITY = 1;
    uint8 internal constant ACTION_REMOVE_LIQUIDITY = 2;
    uint8 internal constant ACTION_COLLECT_FEES = 3;

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
    }

    struct CollectFeesParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        address recipient;
    }

    struct CallbackData {
        uint8 action;
        bytes params;
    }

    // User liquidity positions: user => poolId => tickLower => tickUpper => liquidity
    mapping(address => mapping(bytes32 => mapping(int24 => mapping(int24 => uint128)))) public positions;

    error InvalidPoolManager();
    error InvalidStateView();
    error InvalidAmounts();
    error OnlyPoolManager();
    error InvalidRecipient();
    error InsufficientLiquidity();
    error SlippageExceeded();
    error PoolNotInitialized();

    event PoolInitialized(address indexed token0, address indexed token1, uint24 fee, int24 tick);
    event LiquidityAdded(
        address indexed provider,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity
    );
    event LiquidityRemoved(
        address indexed provider,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity
    );
    event FeesCollected(
        address indexed provider,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1
    );

    constructor(address _poolManager, address _stateView, address _owner) Ownable(_owner) {
        if (_poolManager == address(0)) revert InvalidPoolManager();
        if (_stateView == address(0)) revert InvalidStateView();
        poolManager = IPoolManager(_poolManager);
        stateView = IStateView(_stateView);
    }

    /**
     * @notice Initialize a new pool if it doesn't exist
     */
    function initializePool(
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96
    ) external returns (int24 tick) {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: token0,
            currency1: token1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: address(0)
        });

        uint160 price = sqrtPriceX96 == 0 ? DEFAULT_SQRT_PRICE_X96 : sqrtPriceX96;
        tick = poolManager.initialize(key, price);

        emit PoolInitialized(token0, token1, fee, tick);
    }

    /**
     * @notice Add liquidity to a pool
     * @dev Calculates optimal liquidity from desired amounts using current pool price
     */
    function addLiquidity(AddLiquidityParams calldata params)
        external
        payable
        nonReentrant
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (params.amount0Desired == 0 && params.amount1Desired == 0) revert InvalidAmounts();
        if (params.recipient == address(0)) revert InvalidRecipient();

        // Transfer tokens from sender
        if (params.token0 != address(0) && params.amount0Desired > 0) {
            IERC20(params.token0).safeTransferFrom(msg.sender, address(this), params.amount0Desired);
        }
        if (params.token1 != address(0) && params.amount1Desired > 0) {
            IERC20(params.token1).safeTransferFrom(msg.sender, address(this), params.amount1Desired);
        }

        // Encode callback data
        bytes memory data = abi.encode(CallbackData({
            action: ACTION_ADD_LIQUIDITY,
            params: abi.encode(params)
        }));

        // Execute through unlock
        bytes memory result = poolManager.unlock(data);
        (liquidity, amount0, amount1) = abi.decode(result, (uint128, uint256, uint256));

        // Check slippage
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert SlippageExceeded();
        }

        // Store position
        bytes32 poolId = _getPoolId(params.token0, params.token1, params.fee, params.tickSpacing);
        positions[params.recipient][poolId][params.tickLower][params.tickUpper] += liquidity;

        emit LiquidityAdded(
            params.recipient,
            params.token0,
            params.token1,
            amount0,
            amount1,
            liquidity
        );
    }

    /**
     * @notice Remove liquidity from a pool
     */
    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (params.recipient == address(0)) revert InvalidRecipient();

        bytes32 poolId = _getPoolId(params.token0, params.token1, params.fee, params.tickSpacing);
        uint128 userLiquidity = positions[msg.sender][poolId][params.tickLower][params.tickUpper];

        if (params.liquidity > userLiquidity) revert InsufficientLiquidity();

        // Update position BEFORE external call (CEI pattern)
        positions[msg.sender][poolId][params.tickLower][params.tickUpper] -= params.liquidity;

        // Encode callback data
        bytes memory data = abi.encode(CallbackData({
            action: ACTION_REMOVE_LIQUIDITY,
            params: abi.encode(params)
        }));

        // Execute through unlock
        bytes memory result = poolManager.unlock(data);
        (amount0, amount1) = abi.decode(result, (uint256, uint256));

        // Check slippage
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert SlippageExceeded();
        }

        emit LiquidityRemoved(
            params.recipient,
            params.token0,
            params.token1,
            amount0,
            amount1,
            params.liquidity
        );
    }

    /**
     * @notice Collect accumulated fees from a position
     * @dev Calls modifyLiquidity with 0 delta to collect fees without changing position
     */
    function collectFees(CollectFeesParams calldata params)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (params.recipient == address(0)) revert InvalidRecipient();

        bytes32 poolId = _getPoolId(params.token0, params.token1, params.fee, params.tickSpacing);
        uint128 userLiquidity = positions[msg.sender][poolId][params.tickLower][params.tickUpper];

        // Must have a position to collect fees
        if (userLiquidity == 0) revert InsufficientLiquidity();

        // Encode callback data
        bytes memory data = abi.encode(CallbackData({
            action: ACTION_COLLECT_FEES,
            params: abi.encode(params)
        }));

        // Execute through unlock
        bytes memory result = poolManager.unlock(data);
        (amount0, amount1) = abi.decode(result, (uint256, uint256));

        emit FeesCollected(
            params.recipient,
            params.token0,
            params.token1,
            amount0,
            amount1
        );
    }

    /**
     * @notice Callback from PoolManager during unlock
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();

        CallbackData memory cbData = abi.decode(data, (CallbackData));

        if (cbData.action == ACTION_ADD_LIQUIDITY) {
            return _handleAddLiquidity(cbData.params);
        } else if (cbData.action == ACTION_REMOVE_LIQUIDITY) {
            return _handleRemoveLiquidity(cbData.params);
        } else if (cbData.action == ACTION_COLLECT_FEES) {
            return _handleCollectFees(cbData.params);
        }

        return "";
    }

    function _handleAddLiquidity(bytes memory params) internal returns (bytes memory) {
        AddLiquidityParams memory p = abi.decode(params, (AddLiquidityParams));

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: p.token0,
            currency1: p.token1,
            fee: p.fee,
            tickSpacing: p.tickSpacing,
            hooks: address(0)
        });

        // Get current pool state
        bytes32 poolId = _getPoolId(p.token0, p.token1, p.fee, p.tickSpacing);
        (uint160 sqrtPriceX96, , , ) = stateView.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        // Calculate liquidity from amounts using Uniswap math
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(p.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(p.tickUpper);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            p.amount0Desired,
            p.amount1Desired
        );

        if (liquidity == 0) revert InvalidAmounts();

        IPoolManager.ModifyLiquidityParams memory modifyParams = IPoolManager.ModifyLiquidityParams({
            tickLower: p.tickLower,
            tickUpper: p.tickUpper,
            liquidityDelta: int256(uint256(liquidity)),
            salt: bytes32(0)
        });

        (int256 callerDelta, ) = poolManager.modifyLiquidity(key, modifyParams, "");

        // Handle settlements
        int128 delta0 = int128(callerDelta >> 128);
        int128 delta1 = int128(callerDelta);

        uint256 amount0Used = 0;
        uint256 amount1Used = 0;

        // Settle token0 if we owe (negative delta = we owe)
        if (delta0 < 0) {
            amount0Used = uint256(int256(-delta0));
            if (p.token0 != address(0)) {
                poolManager.sync(p.token0);
                IERC20(p.token0).safeTransfer(address(poolManager), amount0Used);
                poolManager.settle();
            } else {
                poolManager.settle{value: amount0Used}();
            }
        }

        // Settle token1 if we owe
        if (delta1 < 0) {
            amount1Used = uint256(int256(-delta1));
            if (p.token1 != address(0)) {
                poolManager.sync(p.token1);
                IERC20(p.token1).safeTransfer(address(poolManager), amount1Used);
                poolManager.settle();
            } else {
                poolManager.settle{value: amount1Used}();
            }
        }

        // Refund unused tokens
        if (p.amount0Desired > amount0Used && p.token0 != address(0)) {
            IERC20(p.token0).safeTransfer(p.recipient, p.amount0Desired - amount0Used);
        }
        if (p.amount1Desired > amount1Used && p.token1 != address(0)) {
            IERC20(p.token1).safeTransfer(p.recipient, p.amount1Desired - amount1Used);
        }

        return abi.encode(liquidity, amount0Used, amount1Used);
    }

    function _handleRemoveLiquidity(bytes memory params) internal returns (bytes memory) {
        RemoveLiquidityParams memory p = abi.decode(params, (RemoveLiquidityParams));

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: p.token0,
            currency1: p.token1,
            fee: p.fee,
            tickSpacing: p.tickSpacing,
            hooks: address(0)
        });

        IPoolManager.ModifyLiquidityParams memory modifyParams = IPoolManager.ModifyLiquidityParams({
            tickLower: p.tickLower,
            tickUpper: p.tickUpper,
            liquidityDelta: -int256(uint256(p.liquidity)),
            salt: bytes32(0)
        });

        (int256 callerDelta, ) = poolManager.modifyLiquidity(key, modifyParams, "");

        // Handle takes (positive delta = we receive)
        int128 delta0 = int128(callerDelta >> 128);
        int128 delta1 = int128(callerDelta);

        uint256 amount0 = 0;
        uint256 amount1 = 0;

        // Take token0 if we receive
        if (delta0 > 0) {
            amount0 = uint256(int256(delta0));
            poolManager.take(p.token0, p.recipient, amount0);
        }

        // Take token1 if we receive
        if (delta1 > 0) {
            amount1 = uint256(int256(delta1));
            poolManager.take(p.token1, p.recipient, amount1);
        }

        return abi.encode(amount0, amount1);
    }

    function _handleCollectFees(bytes memory params) internal returns (bytes memory) {
        CollectFeesParams memory p = abi.decode(params, (CollectFeesParams));

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: p.token0,
            currency1: p.token1,
            fee: p.fee,
            tickSpacing: p.tickSpacing,
            hooks: address(0)
        });

        // Call modifyLiquidity with 0 delta to collect fees
        IPoolManager.ModifyLiquidityParams memory modifyParams = IPoolManager.ModifyLiquidityParams({
            tickLower: p.tickLower,
            tickUpper: p.tickUpper,
            liquidityDelta: 0,
            salt: bytes32(0)
        });

        (int256 callerDelta, ) = poolManager.modifyLiquidity(key, modifyParams, "");

        // Handle takes (positive delta = fees we receive)
        int128 delta0 = int128(callerDelta >> 128);
        int128 delta1 = int128(callerDelta);

        uint256 amount0 = 0;
        uint256 amount1 = 0;

        // Take token0 fees if any
        if (delta0 > 0) {
            amount0 = uint256(int256(delta0));
            poolManager.take(p.token0, p.recipient, amount0);
        }

        // Take token1 fees if any
        if (delta1 > 0) {
            amount1 = uint256(int256(delta1));
            poolManager.take(p.token1, p.recipient, amount1);
        }

        return abi.encode(amount0, amount1);
    }

    function _getPoolId(
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(token0, token1, fee, tickSpacing, address(0)));
    }

    /**
     * @notice Get user's liquidity position
     */
    function getPosition(
        address user,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint128 liquidity) {
        bytes32 poolId = _getPoolId(token0, token1, fee, tickSpacing);
        return positions[user][poolId][tickLower][tickUpper];
    }

    /**
     * @notice Sweep stuck ERC20 tokens
     */
    function sweepToken(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidRecipient();
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 sweepAmount = amount == 0 ? balance : amount;
        if (sweepAmount > 0) {
            IERC20(token).safeTransfer(to, sweepAmount);
        }
    }

    /**
     * @notice Sweep stuck ETH
     */
    function sweepEth(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidRecipient();
        uint256 balance = address(this).balance;
        uint256 sweepAmount = amount == 0 ? balance : amount;
        if (sweepAmount > 0) {
            Address.sendValue(to, sweepAmount);
        }
    }

    receive() external payable {}
}
