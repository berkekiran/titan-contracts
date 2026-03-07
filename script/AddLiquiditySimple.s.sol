// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

interface ILiquidityRouter {
    function addLiquidity(AddLiquidityParams calldata params) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract AddLiquiditySimple is Script {
    address constant LIQUIDITY_ROUTER = 0x11450A1214D485072c1DC0aA82E2547D1ba8040d;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xbA6720e72f929318E66AcED4389889640Aee0F6e;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Adding Liquidity via LiquidityRouter...");
        console.log("Deployer:", deployer);

        // Sort currencies
        address token0 = WETH < TITAN ? WETH : TITAN;
        address token1 = WETH < TITAN ? TITAN : WETH;

        console.log("Token0:", token0);
        console.log("Token1:", token1);

        uint256 ethAmount = 2 ether;
        uint256 titanAmount = 200000 ether;

        // If WETH is token0, amount0 = ethAmount, amount1 = titanAmount
        uint256 amount0 = (token0 == WETH) ? ethAmount : titanAmount;
        uint256 amount1 = (token0 == WETH) ? titanAmount : ethAmount;

        console.log("Amount0:", amount0);
        console.log("Amount1:", amount1);

        vm.startBroadcast(deployerPrivateKey);

        // Wrap ETH to WETH
        console.log("Wrapping ETH...");
        IWETH(WETH).deposit{value: ethAmount}();

        // Approve LiquidityRouter
        console.log("Approving tokens...");
        IERC20(WETH).approve(LIQUIDITY_ROUTER, type(uint256).max);
        IERC20(TITAN).approve(LIQUIDITY_ROUTER, type(uint256).max);

        // Full range ticks
        int24 tickLower = -887220;
        int24 tickUpper = 887220;

        console.log("Adding liquidity...");

        AddLiquidityParams memory params = AddLiquidityParams({
            token0: token0,
            token1: token1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0, // No slippage protection for testing
            amount1Min: 0,
            recipient: deployer
        });

        (uint128 liquidity, uint256 used0, uint256 used1) = ILiquidityRouter(LIQUIDITY_ROUTER).addLiquidity(params);

        console.log("Liquidity added:", liquidity);
        console.log("Amount0 used:", used0);
        console.log("Amount1 used:", used1);

        vm.stopBroadcast();

        console.log("Done!");
    }
}
