// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILiquidityRouter {
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

    function addLiquidity(AddLiquidityParams calldata params) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function removeLiquidity(RemoveLiquidityParams calldata params) external returns (uint256 amount0, uint256 amount1);
    function getPosition(address owner, address token0, address token1, uint24 fee, int24 tickSpacing, int24 tickLower, int24 tickUpper) external view returns (uint128 liquidity);
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function withdraw(uint256) external;
}

contract ResetPoolLiquidity is Script {
    address constant LIQUIDITY_ROUTER = 0x266E2E67dCe607fcE9aF30b2fb23Fcb070c45299;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xbA6720e72f929318E66AcED4389889640Aee0F6e;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;
    int24 constant TICK_LOWER = -887220;
    int24 constant TICK_UPPER = 887220;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Sort tokens
        address token0 = WETH < TITAN ? WETH : TITAN;
        address token1 = WETH < TITAN ? TITAN : WETH;

        console.log("=== Reset Pool Liquidity ===");
        console.log("Deployer:", deployer);
        console.log("Token0 (WETH):", token0);
        console.log("Token1 (TITAN):", token1);

        // Check current liquidity
        uint128 currentLiquidity = ILiquidityRouter(LIQUIDITY_ROUTER).getPosition(
            deployer, token0, token1, POOL_FEE, TICK_SPACING, TICK_LOWER, TICK_UPPER
        );
        console.log("Current liquidity:", currentLiquidity);

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Remove all existing liquidity
        if (currentLiquidity > 0) {
            console.log("Removing existing liquidity...");

            ILiquidityRouter.RemoveLiquidityParams memory removeParams = ILiquidityRouter.RemoveLiquidityParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE,
                tickSpacing: TICK_SPACING,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                liquidity: currentLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer
            });

            (uint256 removed0, uint256 removed1) = ILiquidityRouter(LIQUIDITY_ROUTER).removeLiquidity(removeParams);
            console.log("Removed WETH:", removed0);
            console.log("Removed TITAN:", removed1);
        }

        // Step 2: Add new liquidity with desired ratio
        // Target: 1 TITAN = 0.00005 ETH (= $0.10 when ETH = $2000)
        // This means 1 ETH = 20,000 TITAN
        // For 2 ETH, we need 40,000 TITAN

        uint256 ethAmount = 2 ether;
        uint256 titanAmount = 40000 ether; // 2 ETH * 20000 TITAN/ETH

        console.log("Adding new liquidity...");
        console.log("ETH amount:", ethAmount);
        console.log("TITAN amount:", titanAmount);

        // Wrap ETH
        IWETH(WETH).deposit{value: ethAmount}();

        // Approve
        IERC20(WETH).approve(LIQUIDITY_ROUTER, type(uint256).max);
        IERC20(TITAN).approve(LIQUIDITY_ROUTER, type(uint256).max);

        // amount0 = WETH, amount1 = TITAN (since WETH < TITAN)
        ILiquidityRouter.AddLiquidityParams memory addParams = ILiquidityRouter.AddLiquidityParams({
            token0: token0,
            token1: token1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: ethAmount,
            amount1Desired: titanAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: deployer
        });

        (uint128 newLiquidity, uint256 used0, uint256 used1) = ILiquidityRouter(LIQUIDITY_ROUTER).addLiquidity(addParams);

        console.log("=== Results ===");
        console.log("New liquidity:", newLiquidity);
        console.log("WETH used:", used0);
        console.log("TITAN used:", used1);

        // Calculate effective price
        if (used0 > 0) {
            console.log("Effective price (TITAN per ETH):", used1 / used0);
        }

        vm.stopBroadcast();

        console.log("Done!");
    }
}
