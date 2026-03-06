// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeploySimple
 * @notice Simplified deployment - just contracts and pool initialization
 */

import "forge-std/Script.sol";
import "../src/TitanToken.sol";
import "../src/Earn.sol";
import "../src/Farm.sol";
import "../src/Governor.sol";
import "../src/Faucet.sol";

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

contract DeploySimple is Script {
    TitanToken public titanToken;
    Earn public earn;
    Farm public farm;
    Governor public governor;
    Faucet public faucet;

    // Configuration
    uint256 public constant STAKING_REWARD_RATE = 1e15;
    uint256 public constant FARM_TITAN_PER_SECOND = 1e18;
    uint256 public constant PROPOSAL_THRESHOLD = 1_000 * 1e18;
    uint256 public constant VOTING_DELAY = 1; // 1 block delay
    uint256 public constant VOTING_PERIOD = 50400; // ~1 week in blocks
    uint256 public constant TIMELOCK_DELAY = 1 days;
    uint256 public constant QUORUM_PERCENTAGE = 400;
    uint256 public constant FAUCET_DRIP_AMOUNT = 100 * 1e18;
    uint256 public constant FAUCET_COOLDOWN = 24 hours;
    uint256 public constant FAUCET_INITIAL_BALANCE = 10_000_000 * 1e18;
    uint256 public constant STAKING_REWARDS_ALLOCATION = 20_000_000 * 1e18;
    uint256 public constant FARM_REWARDS_ALLOCATION = 20_000_000 * 1e18;

    // Uniswap V4 on Sepolia
    address public constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address public constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // Pool configuration
    uint24 public constant POOL_FEE = 3000;
    int24 public constant TICK_SPACING = 60;

    // 1 TITAN = 0.0001 ETH
    uint160 public constant INITIAL_SQRT_PRICE = 7922816251426433759354395034;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Titan Simple Deployment ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts
        titanToken = new TitanToken(deployer);
        console.log("TitanToken:", address(titanToken));

        earn = new Earn(address(titanToken), STAKING_REWARD_RATE, deployer);
        console.log("Earn:", address(earn));

        farm = new Farm(address(titanToken), FARM_TITAN_PER_SECOND, deployer);
        console.log("Farm:", address(farm));

        governor = new Governor(
            address(titanToken),
            PROPOSAL_THRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            TIMELOCK_DELAY,
            QUORUM_PERCENTAGE
        );
        console.log("Governor:", address(governor));

        faucet = new Faucet(address(titanToken), FAUCET_DRIP_AMOUNT, FAUCET_COOLDOWN, deployer);
        console.log("Faucet:", address(faucet));

        // Fund contracts
        titanToken.transfer(address(earn), STAKING_REWARDS_ALLOCATION);
        titanToken.transfer(address(farm), FARM_REWARDS_ALLOCATION);
        titanToken.transfer(address(faucet), FAUCET_INITIAL_BALANCE);
        console.log("Funded contracts");

        // Initialize V4 Pool
        address currency0;
        address currency1;
        if (uint160(address(titanToken)) < uint160(WETH)) {
            currency0 = address(titanToken);
            currency1 = WETH;
        } else {
            currency0 = WETH;
            currency1 = address(titanToken);
        }

        IPoolManager.PoolKey memory poolKey = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        int24 tick = IPoolManager(POOL_MANAGER).initialize(poolKey, INITIAL_SQRT_PRICE);
        console.log("Pool initialized at tick:", tick);

        vm.stopBroadcast();

        // Summary
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("TitanToken:", address(titanToken));
        console.log("Earn:", address(earn));
        console.log("Farm:", address(farm));
        console.log("Governor:", address(governor));
        console.log("Faucet:", address(faucet));
        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);

        _writeAddresses(currency0, currency1);
    }

    function _writeAddresses(address currency0, address currency1) internal {
        string memory json = string(
            abi.encodePacked(
                '{\n',
                '  "titanToken": "', vm.toString(address(titanToken)), '",\n',
                '  "staking": "', vm.toString(address(earn)), '",\n',
                '  "farming": "', vm.toString(address(farm)), '",\n',
                '  "governance": "', vm.toString(address(governor)), '",\n',
                '  "faucet": "', vm.toString(address(faucet)), '",\n',
                '  "currency0": "', vm.toString(currency0), '",\n',
                '  "currency1": "', vm.toString(currency1), '"\n',
                '}'
            )
        );
        vm.writeFile("deployments-simple.json", json);
    }
}
