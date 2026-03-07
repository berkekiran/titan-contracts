// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StakedTitan.sol";

contract SetSTitanRewardRate is Script {
    address public constant STAKED_TITAN = 0x4398317E8641E613a92e4af0Ea62eBFf7984818a;
    uint256 public constant NEW_REWARD_RATE = 3e11; // ~1000% APY

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        vm.startBroadcast(pk);

        StakedTitan sTitan = StakedTitan(STAKED_TITAN);

        uint256 oldRate = sTitan.rewardRate();
        console.log("Old reward rate:", oldRate);

        sTitan.setRewardRate(NEW_REWARD_RATE);

        uint256 newRate = sTitan.rewardRate();
        console.log("New reward rate:", newRate);

        uint256 apy = sTitan.currentAPY();
        console.log("New APY:", apy, "%");

        vm.stopBroadcast();
    }
}
