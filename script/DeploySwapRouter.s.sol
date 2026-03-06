// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SwapRouter.sol";

contract DeploySwapRouter is Script {
    function run() external {
        uint256 pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(pk);
        address poolManager = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

        vm.startBroadcast(pk);

        SwapRouter router = new SwapRouter(poolManager, deployer);
        console.log("SwapRouter deployed at:", address(router));

        vm.stopBroadcast();
    }
}
