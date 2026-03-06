// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IPositionManager {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
}

contract AddBigLiquidity is Script {
    // Uniswap V4 on Sepolia
    address constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // Pool config
    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    // V4 Actions from Actions.sol
    uint8 constant MINT_POSITION = 2;      // Actions.MINT_POSITION
    uint8 constant SETTLE_PAIR = 13;       // Actions.SETTLE_PAIR

    // Liquidity amounts
    uint256 constant WETH_AMOUNT = 0.1 ether;        // 0.1 WETH
    uint256 constant TITAN_AMOUNT = 5_000 ether;     // 5K TITAN

    function run() external {
        // Get TITAN address from env or use default
        address TITAN = vm.envOr("TITAN_ADDRESS", address(0x20C687CA320d8174f8216E036F11506fa47AF80B));
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("    Adding Big Liquidity to V4 Pool");
        console.log("========================================");
        console.log("Deployer:", deployer);

        // Sort currencies (WETH < TITAN on Sepolia)
        address currency0 = WETH < TITAN ? WETH : TITAN;
        address currency1 = WETH < TITAN ? TITAN : WETH;
        bool wethIsCurrency0 = currency0 == WETH;

        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);
        console.log("WETH is currency0:", wethIsCurrency0);

        uint256 amount0 = wethIsCurrency0 ? WETH_AMOUNT : TITAN_AMOUNT;
        uint256 amount1 = wethIsCurrency0 ? TITAN_AMOUNT : WETH_AMOUNT;

        console.log("Amount0:", amount0 / 1e18);
        console.log("Amount1:", amount1 / 1e18);

        vm.startBroadcast(deployerPrivateKey);

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: WETH_AMOUNT}();
        console.log("Wrapped", WETH_AMOUNT / 1e18, "ETH to WETH");

        // Approvals
        IERC20(WETH).approve(PERMIT2, type(uint256).max);
        IERC20(TITAN).approve(PERMIT2, type(uint256).max);
        IERC20(WETH).approve(POSITION_MANAGER, type(uint256).max);
        IERC20(TITAN).approve(POSITION_MANAGER, type(uint256).max);

        IPermit2(PERMIT2).approve(WETH, POSITION_MANAGER, type(uint160).max, type(uint48).max);
        IPermit2(PERMIT2).approve(TITAN, POSITION_MANAGER, type(uint160).max, type(uint48).max);

        console.log("Approvals done");

        // Narrow range around current tick (~92100) for concentrated liquidity
        // Must be divisible by tickSpacing=60
        int24 tickLower = 90000;  // Close to current tick
        int24 tickUpper = 94200;  // Close to current tick

        // Encode actions: MINT_POSITION + SETTLE_PAIR
        bytes memory actions = abi.encodePacked(
            MINT_POSITION,
            SETTLE_PAIR
        );

        // MINT_POSITION params matching frontend format:
        // (PoolKey tuple, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData)
        // PoolKey = (currency0, currency1, fee, tickSpacing, hooks)
        bytes memory mintParams = abi.encode(
            // PoolKey as a struct/tuple
            currency0,
            currency1,
            uint24(POOL_FEE),
            int24(TICK_SPACING),
            address(0), // hooks
            // Other params
            int24(tickLower),
            int24(tickUpper),
            uint256(1e18), // liquidity amount (1 unit)
            uint128(amount0),
            uint128(amount1),
            deployer, // recipient
            bytes("") // hookData
        );

        // SETTLE_PAIR params: (currency0, currency1)
        bytes memory settleParams = abi.encode(currency0, currency1);

        // Params array
        bytes[] memory params = new bytes[](2);
        params[0] = mintParams;
        params[1] = settleParams;

        // Encode full payload
        bytes memory payload = abi.encode(actions, params);

        console.log("Calling modifyLiquidities...");

        // Execute
        IPositionManager(POSITION_MANAGER).modifyLiquidities(
            payload,
            block.timestamp + 3600
        );

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("    LIQUIDITY ADDED SUCCESSFULLY!");
        console.log("========================================");
        console.log("WETH:", WETH_AMOUNT / 1e18);
        console.log("TITAN:", TITAN_AMOUNT / 1e18);
        console.log("========================================");
    }
}
