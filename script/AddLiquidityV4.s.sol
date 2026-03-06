// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
}

interface IPositionManager {
    function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract AddLiquidityV4 is Script {
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xf825ac88B042e9E31Ce18bAaE18EF8c31Eae7C8f;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    // V4 Actions
    uint8 constant MINT_POSITION = 1;
    uint8 constant SETTLE_PAIR = 13;
    uint8 constant CLOSE_CURRENCY = 17;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Adding V4 Liquidity...");
        console.log("Deployer:", deployer);

        // Sort currencies
        address currency0 = WETH < TITAN ? WETH : TITAN;
        address currency1 = WETH < TITAN ? TITAN : WETH;

        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);

        uint256 amount0 = 10 ether;
        uint256 amount1 = 100_000 ether; // 100k TITAN

        vm.startBroadcast(deployerPrivateKey);

        // Wrap ETH
        IWETH(WETH).deposit{value: amount0}();

        // Approve tokens
        IERC20(WETH).approve(PERMIT2, type(uint256).max);
        IERC20(TITAN).approve(PERMIT2, type(uint256).max);
        IERC20(WETH).approve(POSITION_MANAGER, type(uint256).max);
        IERC20(TITAN).approve(POSITION_MANAGER, type(uint256).max);

        IPermit2(PERMIT2).approve(WETH, POSITION_MANAGER, type(uint160).max, uint48(block.timestamp + 365 days));
        IPermit2(PERMIT2).approve(TITAN, POSITION_MANAGER, type(uint160).max, uint48(block.timestamp + 365 days));

        // Encode PoolKey
        bytes memory poolKey = abi.encode(
            currency0,
            currency1,
            POOL_FEE,
            TICK_SPACING,
            address(0) // no hooks
        );

        // Full range ticks for 60 tick spacing
        int24 tickLower = -887220;
        int24 tickUpper = 887220;

        // Encode MINT_POSITION params
        bytes memory mintParams = abi.encode(
            currency0,
            currency1,
            POOL_FEE,
            TICK_SPACING,
            address(0), // hooks
            tickLower,
            tickUpper,
            uint256(1000000 ether), // liquidity
            uint128(amount0),
            uint128(amount1),
            deployer, // owner
            bytes("") // hookData
        );

        // Encode actions
        bytes memory actions = abi.encodePacked(
            MINT_POSITION,
            CLOSE_CURRENCY,
            CLOSE_CURRENCY
        );

        // Encode params array
        bytes[] memory params = new bytes[](3);
        params[0] = mintParams;
        params[1] = abi.encode(currency0);
        params[2] = abi.encode(currency1);

        // Encode full payload
        bytes memory payload = abi.encode(actions, params);

        // Call modifyLiquidities
        IPositionManager(POSITION_MANAGER).modifyLiquidities{value: amount0}(
            payload,
            block.timestamp + 3600
        );

        vm.stopBroadcast();

        console.log("Liquidity added successfully!");
    }
}
