// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployStakedTitan
 * @notice Deploy the new StakedTitan contract with auto-compounding rewards
 */

import "forge-std/Script.sol";
import "../src/StakedTitan.sol";

contract DeployStakedTitan is Script {
    // Existing TITAN token on Sepolia
    address public constant TITAN_TOKEN = 0xbA6720e72f929318E66AcED4389889640Aee0F6e;

    // Reward rate: ~30% APY
    // 30% / 365 days / 24 hours / 3600 seconds = 9.512e-9 per second
    // Scaled by 1e18 = 9.512e9 = ~1e10
    uint256 public constant REWARD_RATE = 1e10; // ~31.5% APY

    // Initial rewards to fund the contract
    uint256 public constant INITIAL_REWARDS = 1_000_000 * 1e18; // 1M TITAN

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== StakedTitan Deployment ===");
        console.log("Deployer:", deployer);
        console.log("TITAN Token:", TITAN_TOKEN);
        console.log("Reward Rate:", REWARD_RATE);

        // Calculate APY for display
        uint256 apy = (REWARD_RATE * 365 days * 100) / 1e18;
        console.log("Expected APY:", apy, "%");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy StakedTitan
        StakedTitan stakedTitan = new StakedTitan(
            TITAN_TOKEN,
            REWARD_RATE,
            deployer
        );
        console.log("StakedTitan:", address(stakedTitan));

        // Fund with initial rewards
        IERC20 titan = IERC20(TITAN_TOKEN);
        uint256 balance = titan.balanceOf(deployer);

        if (balance >= INITIAL_REWARDS) {
            titan.approve(address(stakedTitan), INITIAL_REWARDS);
            stakedTitan.depositRewards(INITIAL_REWARDS);
            console.log("Funded with:", INITIAL_REWARDS / 1e18, "TITAN");
        } else {
            console.log("Insufficient TITAN to fund. Balance:", balance / 1e18);
            console.log("Fund manually with depositRewards() later");
        }

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("StakedTitan:", address(stakedTitan));
        console.log("\nUpdate titan-app/src/config/index.ts:");
        console.log("stakedTitan:", address(stakedTitan));
    }
}
