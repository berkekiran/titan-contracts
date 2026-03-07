// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }
}

interface ISwapRouter {
    function swap(
        IPoolManager.PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minAmountOut
    ) external payable returns (uint256 amountOut);
}

interface IStateView {
    function getSlot0(bytes32 poolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
    function getLiquidity(bytes32 poolId) external view returns (uint128 liquidity);
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract BuyTitanToFixPrice is Script {
    address constant SWAP_ROUTER = 0x77a76b5eEC937361b8F05c15860AE81d9fe23b0E;
    address constant STATE_VIEW = 0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xbA6720e72f929318E66AcED4389889640Aee0F6e;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Sort tokens: WETH < TITAN, so WETH is currency0, TITAN is currency1
        address currency0 = WETH;
        address currency1 = TITAN;

        // Calculate poolId
        bytes32 poolId = keccak256(abi.encode(currency0, currency1, POOL_FEE, TICK_SPACING, address(0)));

        console.log("=== Buy TITAN to Fix Price ===");
        console.log("Deployer:", deployer);

        // Get current pool state
        (uint160 sqrtPriceX96, int24 tick, , ) = IStateView(STATE_VIEW).getSlot0(poolId);
        uint128 liquidity = IStateView(STATE_VIEW).getLiquidity(poolId);

        console.log("Current sqrtPriceX96:", sqrtPriceX96);
        console.log("Current tick:", tick);
        console.log("Current liquidity:", liquidity);

        // Current: ~46,000 TITAN per ETH (1 TITAN = ~$0.04)
        // Target: ~20,000 TITAN per ETH (1 TITAN = $0.10)
        // We need to BUY TITAN (sell WETH) to decrease the price ratio

        // zeroForOne = true means we're selling token0 (WETH) for token1 (TITAN)
        uint256 wethToSell = 0.15 ether;

        console.log("Buying TITAN to move price...");
        console.log("WETH to sell:", wethToSell);

        vm.startBroadcast(deployerPrivateKey);

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: wethToSell}();

        // Approve SwapRouter
        IERC20(WETH).approve(SWAP_ROUTER, type(uint256).max);

        // Create pool key
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        // Swap WETH -> TITAN (zeroForOne = true, selling WETH for TITAN)
        uint256 titanReceived = ISwapRouter(SWAP_ROUTER).swap(
            key,
            true, // zeroForOne = true, selling WETH (currency0) for TITAN (currency1)
            wethToSell,
            0 // No slippage protection
        );

        console.log("TITAN received:", titanReceived);

        vm.stopBroadcast();

        // Check new price
        (sqrtPriceX96, tick, , ) = IStateView(STATE_VIEW).getSlot0(poolId);
        console.log("New sqrtPriceX96:", sqrtPriceX96);
        console.log("New tick:", tick);

        // Calculate approximate price
        // tick ~= log(price) / log(1.0001)
        // For tick 100,000: price ≈ 22,000 TITAN/ETH
        // For tick 95,000: price ≈ 13,000 TITAN/ETH
        // For tick 99,700: price ≈ 20,000 TITAN/ETH (target)

        console.log("Done! Check swap UI for new price.");
    }
}
