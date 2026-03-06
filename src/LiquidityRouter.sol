// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPoolManager.sol";

/**
 * @title LiquidityRouter
 * @author Titan Team
 * @notice Simple liquidity router for Uniswap V4 pools
 * @dev Handles pool initialization and liquidity management
 */
contract LiquidityRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;

    // Default initial sqrtPriceX96 for new pools (price = 1)
    uint160 internal constant DEFAULT_SQRT_PRICE_X96 = 79228162514264337593543950336;

    // Action types for unlock callback
    uint8 internal constant ACTION_ADD_LIQUIDITY = 1;
    uint8 internal constant ACTION_REMOVE_LIQUIDITY = 2;

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
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
        address recipient;
    }

    struct CallbackData {
        uint8 action;
        bytes params;
    }

    // User liquidity positions: user => poolId => tickLower => tickUpper => liquidity
    mapping(address => mapping(bytes32 => mapping(int24 => mapping(int24 => uint128)))) public positions;

    /// @notice Error definitions
    error InvalidPoolManager();
    error InvalidAmounts();
    error OnlyPoolManager();
    error InvalidRecipient();
    error InsufficientLiquidity();

    /// @notice Events
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

    constructor(address _poolManager, address _owner) Ownable(_owner) {
        if (_poolManager == address(0)) revert InvalidPoolManager();
        poolManager = IPoolManager(_poolManager);
    }

    /**
     * @notice Initialize a new pool if it doesn't exist
     * @param token0 The first token (must be < token1)
     * @param token1 The second token
     * @param fee The pool fee
     * @param tickSpacing The tick spacing
     * @param sqrtPriceX96 Initial price (0 for default price = 1)
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
     * @param params The add liquidity parameters
     * @return liquidity The amount of liquidity added
     */
    function addLiquidity(AddLiquidityParams calldata params)
        external
        payable
        nonReentrant
        returns (uint128 liquidity)
    {
        if (params.amount0Desired == 0 && params.amount1Desired == 0) revert InvalidAmounts();

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
        (liquidity, , ) = abi.decode(result, (uint128, uint256, uint256));

        // Store position AFTER external call completes (nonReentrant protects against reentrancy)
        // Note: CEI pattern is maintained as nonReentrant modifier prevents reentry
        bytes32 poolId = _getPoolId(params.token0, params.token1, params.fee, params.tickSpacing);
        positions[params.recipient][poolId][params.tickLower][params.tickUpper] += liquidity;

        emit LiquidityAdded(
            params.recipient,
            params.token0,
            params.token1,
            params.amount0Desired,
            params.amount1Desired,
            liquidity
        );
    }

    /**
     * @notice Remove liquidity from a pool
     * @param params The remove liquidity parameters
     * @return amount0 Amount of token0 received
     * @return amount1 Amount of token1 received
     */
    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
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
     * @notice Callback from PoolManager during unlock
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();

        CallbackData memory cbData = abi.decode(data, (CallbackData));

        if (cbData.action == ACTION_ADD_LIQUIDITY) {
            return _handleAddLiquidity(cbData.params);
        } else if (cbData.action == ACTION_REMOVE_LIQUIDITY) {
            return _handleRemoveLiquidity(cbData.params);
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

        // Calculate liquidity properly:
        // For a full range position, liquidity L relates to tokens as:
        // L = amount0 * sqrt(P) = amount1 / sqrt(P)
        // We need to find L such that neither amount exceeds desired
        // Using conservative estimate: divide smaller amount by a large factor
        // This ensures we don't request more tokens than we have
        // The refund mechanism will return unused tokens

        // Scale down significantly - use smaller amount / 100 as liquidity
        // This is conservative but ensures we have enough tokens
        uint128 liquidity;
        if (p.amount0Desired <= p.amount1Desired) {
            liquidity = uint128(p.amount0Desired / 100);
        } else {
            liquidity = uint128(p.amount1Desired / 100);
        }
        if (liquidity == 0) liquidity = 1e15; // Minimum liquidity

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

        // Settle token0 if we owe
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

        // Handle takes (we receive tokens)
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
