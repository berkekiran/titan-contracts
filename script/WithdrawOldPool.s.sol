// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface ILiquidityRouter {
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

    function removeLiquidity(RemoveLiquidityParams calldata params) external returns (uint256 amount0, uint256 amount1);
    function getPosition(address, address, address, uint24, int24, int24, int24) external view returns (uint128);
}

contract WithdrawOldPool is Script {
    address constant OLD_LIQUIDITY_ROUTER = 0x266E2E67dCe607fcE9aF30b2fb23Fcb070c45299;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xbA6720e72f929318E66AcED4389889640Aee0F6e;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;
    int24 constant TICK_LOWER = -887220;
    int24 constant TICK_UPPER = 887220;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address token0 = WETH;
        address token1 = TITAN;

        console.log("=== Withdraw from OLD LiquidityRouter ===");
        console.log("Old Router:", OLD_LIQUIDITY_ROUTER);
        console.log("Deployer:", deployer);

        uint128 liquidity = ILiquidityRouter(OLD_LIQUIDITY_ROUTER).getPosition(
            deployer, token0, token1, POOL_FEE, TICK_SPACING, TICK_LOWER, TICK_UPPER
        );
        console.log("Current liquidity:", liquidity);

        if (liquidity == 0) {
            console.log("No liquidity to withdraw!");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        ILiquidityRouter.RemoveLiquidityParams memory params = ILiquidityRouter.RemoveLiquidityParams({
            token0: token0,
            token1: token1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            recipient: deployer
        });

        (uint256 amount0, uint256 amount1) = ILiquidityRouter(OLD_LIQUIDITY_ROUTER).removeLiquidity(params);

        console.log("Withdrawn WETH:", amount0);
        console.log("Withdrawn TITAN:", amount1);

        vm.stopBroadcast();

        console.log("Done!");
    }
}
