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

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
}

interface IPositionManager {
    function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable;
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract InitializePoolV4 is Script {
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant TITAN = 0xbA6720e72f929318E66AcED4389889640Aee0F6e;

    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Initializing V4 Pool...");
        console.log("Deployer:", deployer);

        // Sort currencies (WETH < TITAN alphabetically)
        address currency0 = WETH < TITAN ? WETH : TITAN;
        address currency1 = WETH < TITAN ? TITAN : WETH;

        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);

        // Initial price: 1 WETH = 50000 TITAN
        // sqrtPriceX96 = sqrt(price) * 2^96
        // sqrt(50000) * 2^96 ≈ 223.6 * 2^96
        // Using a standard value that's within valid range
        uint160 sqrtPriceX96 = 17715303921927178774990765309952; // ~50000 price ratio

        vm.startBroadcast(deployerPrivateKey);

        // Initialize pool
        IPoolManager.PoolKey memory poolKey = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        int24 tick = IPoolManager(POOL_MANAGER).initialize(poolKey, sqrtPriceX96);
        console.log("Pool initialized at tick:", tick);

        vm.stopBroadcast();

        console.log("Pool initialized successfully!");
    }
}
