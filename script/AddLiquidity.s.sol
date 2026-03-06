// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPositionManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    function mint(
        PoolKey calldata poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address owner,
        bytes calldata hookData
    ) external payable returns (uint256 tokenId, uint128 amount0, uint128 amount1);

    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract AddLiquidity is Script {
    // Addresses
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xf825ac88B042e9E31Ce18bAaE18EF8c31Eae7C8f;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Adding liquidity...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Wrap some ETH to WETH
        uint256 wethAmount = 10 ether;
        IWETH(WETH).deposit{value: wethAmount}();
        console.log("Wrapped", wethAmount / 1e18, "ETH to WETH");

        // Approve tokens to Permit2
        IERC20(WETH).approve(PERMIT2, type(uint256).max);
        IERC20(TITAN).approve(PERMIT2, type(uint256).max);
        console.log("Approved tokens to Permit2");

        // Approve Permit2 to PositionManager
        IPermit2(PERMIT2).approve(WETH, POSITION_MANAGER, type(uint160).max, uint48(block.timestamp + 365 days));
        IPermit2(PERMIT2).approve(TITAN, POSITION_MANAGER, type(uint160).max, uint48(block.timestamp + 365 days));
        console.log("Approved Permit2 to PositionManager");

        // Also direct approve to PositionManager (fallback)
        IERC20(WETH).approve(POSITION_MANAGER, type(uint256).max);
        IERC20(TITAN).approve(POSITION_MANAGER, type(uint256).max);
        console.log("Direct approved to PositionManager");

        vm.stopBroadcast();

        console.log("Liquidity setup complete - use the app to add liquidity via UI");
    }
}
