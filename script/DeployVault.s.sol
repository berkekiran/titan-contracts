// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/TitanUSD.sol";
import "../src/Vault.sol";

contract DeployVault is Script {
    // TITAN price: $0.10 = 10000000 (8 decimals)
    uint256 public constant INITIAL_TITAN_PRICE = 10000000;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // Read TITAN token address from deployments
        address titanToken = 0xbA6720e72f929318E66AcED4389889640Aee0F6e; // Sepolia TITAN

        console.log("========================================");
        console.log("       DEPLOYING VAULT SYSTEM");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("TITAN Token:", titanToken);

        vm.startBroadcast(pk);

        // 1. Deploy TitanUSD
        TitanUSD tusd = new TitanUSD(deployer);
        console.log("TitanUSD deployed:", address(tusd));

        // 2. Deploy Vault
        Vault vault = new Vault(
            titanToken,
            address(tusd),
            INITIAL_TITAN_PRICE,
            deployer
        );
        console.log("Vault deployed:", address(vault));

        // 3. Authorize Vault to mint tUSD
        tusd.setMinter(address(vault), true);
        console.log("Vault authorized as minter");

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("         DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("TitanUSD (tUSD):", address(tusd));
        console.log("Vault:", address(vault));
        console.log("Initial TITAN Price: $0.10");
        console.log("MCR: 150%");
        console.log("Liquidation Threshold: 110%");
        console.log("========================================");
    }
}
