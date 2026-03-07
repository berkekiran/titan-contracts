// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface IFaucet {
    function setDripAmount(uint256 newDripAmount) external;
    function dripAmount() external view returns (uint256);
    function balance() external view returns (uint256);
}

contract UpdateFaucet is Script {
    address constant FAUCET = 0x7D34B7286d2dC4836e6B0C2761C17b6693e5d241;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== Update Faucet ===");
        console.log("Current drip amount:", IFaucet(FAUCET).dripAmount());
        console.log("Faucet balance:", IFaucet(FAUCET).balance());

        vm.startBroadcast(deployerPrivateKey);

        // Set drip amount to 1 TITAN
        IFaucet(FAUCET).setDripAmount(1 ether);

        vm.stopBroadcast();

        console.log("New drip amount:", IFaucet(FAUCET).dripAmount());
        console.log("Done!");
    }
}
