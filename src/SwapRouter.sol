// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPoolManager.sol";

/**
 * @title SwapRouter
 * @author Titan Team
 * @notice Simple swap router for Uniswap V4 pools
 * @dev Uses SafeERC20 for secure token transfers
 */
contract SwapRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;

    // Min/max sqrt price limits
    uint160 internal constant MIN_SQRT_PRICE = 4295128739 + 1;
    uint160 internal constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342 - 1;

    struct SwapCallbackData {
        address sender;
        IPoolManager.PoolKey key;
        IPoolManager.SwapParams params;
    }

    /// @notice Error definitions
    error InvalidPoolManager();
    error InvalidAmountIn();
    error InsufficientOutput(uint256 amountOut, uint256 minAmountOut);
    error OnlyPoolManager();
    error InvalidRecipient();

    /// @notice Emitted when tokens are swept
    event TokensSwept(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when ETH is swept
    event EthSwept(address indexed to, uint256 amount);

    /// @notice Emitted when a swap is executed
    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address _poolManager, address _owner) Ownable(_owner) {
        if (_poolManager == address(0)) revert InvalidPoolManager();
        poolManager = IPoolManager(_poolManager);
    }

    /**
     * @notice Swap tokens using a V4 pool
     * @param key The pool key
     * @param zeroForOne Direction of swap (true = currency0 for currency1)
     * @param amountIn Amount of input token
     * @param minAmountOut Minimum amount of output token
     */
    function swap(
        IPoolManager.PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable nonReentrant returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmountIn();

        // Transfer tokens from sender using SafeERC20
        address tokenIn = zeroForOne ? key.currency0 : key.currency1;
        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        // Prepare swap params
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn), // Negative for exact input
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE : MAX_SQRT_PRICE
        });

        // Encode callback data
        bytes memory data = abi.encode(SwapCallbackData({
            sender: msg.sender,
            key: key,
            params: params
        }));

        // Execute swap through unlock
        bytes memory result = poolManager.unlock(data);
        amountOut = abi.decode(result, (uint256));

        if (amountOut < minAmountOut) {
            revert InsufficientOutput(amountOut, minAmountOut);
        }

        // Emit swap event
        address tokenOut = zeroForOne ? key.currency1 : key.currency0;
        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /**
     * @notice Callback from PoolManager during unlock
     */
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();

        SwapCallbackData memory cbData = abi.decode(data, (SwapCallbackData));

        // Execute the swap - returns BalanceDelta which packs two int128 values
        int256 balanceDelta = poolManager.swap(cbData.key, cbData.params, "");

        // Unpack BalanceDelta: upper 128 bits = delta0 (amount0), lower 128 bits = delta1 (amount1)
        int128 delta0 = int128(balanceDelta >> 128);
        int128 delta1 = int128(balanceDelta);

        // Determine token addresses
        address token0 = cbData.key.currency0;
        address token1 = cbData.key.currency1;

        // Handle settlements and takes based on delta signs (from caller's perspective)
        // Positive delta = caller receives from pool (TAKE)
        // Negative delta = caller owes to pool (SETTLE)
        uint256 amountOut = 0;

        // Handle token0 delta
        if (delta0 > 0) {
            // We receive token0 - take it from pool
            uint256 amount = uint256(int256(delta0));
            poolManager.take(token0, cbData.sender, amount);
            if (!cbData.params.zeroForOne) {
                // If swapping 1->0, output is token0
                amountOut = amount;
            }
        } else if (delta0 < 0) {
            // We owe pool token0 - settle it
            uint256 amt0 = uint256(int256(-delta0));
            if (token0 != address(0)) {
                poolManager.sync(token0);
                IERC20(token0).safeTransfer(address(poolManager), amt0);
                poolManager.settle();
            } else {
                poolManager.settle{value: amt0}();
            }
        }

        // Handle token1 delta
        if (delta1 > 0) {
            // We receive token1 - take it from pool
            uint256 amount = uint256(int256(delta1));
            poolManager.take(token1, cbData.sender, amount);
            if (cbData.params.zeroForOne) {
                // If swapping 0->1, output is token1
                amountOut = amount;
            }
        } else if (delta1 < 0) {
            // We owe pool token1 - settle it
            uint256 amt1 = uint256(int256(-delta1));
            if (token1 != address(0)) {
                poolManager.sync(token1);
                IERC20(token1).safeTransfer(address(poolManager), amt1);
                poolManager.settle();
            } else {
                poolManager.settle{value: amt1}();
            }
        }

        return abi.encode(amountOut);
    }

    /**
     * @notice Sweep stuck ERC20 tokens to a recipient
     * @param token The token to sweep
     * @param to The recipient address
     * @param amount The amount to sweep (0 for full balance)
     */
    function sweepToken(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidRecipient();

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 sweepAmount = amount == 0 ? balance : amount;

        if (sweepAmount > 0) {
            IERC20(token).safeTransfer(to, sweepAmount);
            emit TokensSwept(token, to, sweepAmount);
        }
    }

    /**
     * @notice Sweep stuck ETH to a recipient
     * @param to The recipient address
     * @param amount The amount to sweep (0 for full balance)
     */
    function sweepEth(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidRecipient();

        uint256 balance = address(this).balance;
        uint256 sweepAmount = amount == 0 ? balance : amount;

        if (sweepAmount > 0) {
            Address.sendValue(to, sweepAmount);
            emit EthSwept(to, sweepAmount);
        }
    }

    receive() external payable {}
}
