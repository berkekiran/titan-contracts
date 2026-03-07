// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Deploy
 * @author Titan Team
 * @notice Deployment script for Titan contracts on Sepolia with Uniswap V4
 * @dev Uses existing Uniswap V4 deployment on Sepolia
 */

import "forge-std/Script.sol";
import "../src/TitanToken.sol";
import "../src/Earn.sol";
import "../src/Farm.sol";
import "../src/Governor.sol";
import "../src/StakedTitan.sol";
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

interface IPositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract Deploy is Script {
    // Deployed contract addresses
    TitanToken public titanToken;
    Earn public earn;
    Farm public farm;
    Governor public governor;
    StakedTitan public sTitan;
    Faucet public faucet;

    // Configuration
    uint256 public constant STAKING_REWARD_RATE = 1e15; // 0.001 TITAN per second per token
    uint256 public constant FARM_TITAN_PER_SECOND = 1e18; // 1 TITAN per second
    uint256 public constant PROPOSAL_THRESHOLD = 1_000 * 1e18; // 1K TITAN to propose (lower for testing)
    uint256 public constant VOTING_DELAY = 1; // 1 block delay before voting starts
    uint256 public constant VOTING_PERIOD = 50400; // ~1 week in blocks (assuming 12s blocks)
    uint256 public constant TIMELOCK_DELAY = 1 days;
    uint256 public constant QUORUM_PERCENTAGE = 400; // 4%
    uint256 public constant FAUCET_DRIP_AMOUNT = 100 * 1e18; // 100 TITAN per claim
    uint256 public constant FAUCET_COOLDOWN = 24 hours;
    uint256 public constant FAUCET_INITIAL_BALANCE = 10_000_000 * 1e18; // 10M TITAN
    uint256 public constant STAKING_REWARDS_ALLOCATION = 20_000_000 * 1e18; // 20M TITAN
    uint256 public constant FARM_REWARDS_ALLOCATION = 20_000_000 * 1e18; // 20M TITAN
    uint256 public constant STITAN_REWARD_RATE = 1e10; // ~31.5% APY for sTitan
    uint256 public constant STITAN_INITIAL_REWARDS = 5_000_000 * 1e18; // 5M TITAN for sTitan rewards

    // Uniswap V4 on Sepolia
    address public constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address public constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address public constant UNIVERSAL_ROUTER = 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // WETH on Sepolia
    address public constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // Pool configuration
    uint24 public constant POOL_FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Titan contracts on Sepolia fork...");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy TitanToken
        titanToken = new TitanToken(deployer);
        console.log("TitanToken deployed at:", address(titanToken));

        // 2. Deploy Earn
        earn = new Earn(address(titanToken), STAKING_REWARD_RATE, deployer);
        console.log("Earn deployed at:", address(earn));

        // 3. Deploy Farm
        farm = new Farm(address(titanToken), FARM_TITAN_PER_SECOND, deployer);
        console.log("Farm deployed at:", address(farm));

        // 4. Deploy Governor
        governor = new Governor(
            address(titanToken),
            PROPOSAL_THRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            TIMELOCK_DELAY,
            QUORUM_PERCENTAGE
        );
        console.log("Governor deployed at:", address(governor));

        // 5. Deploy StakedTitan (sTitan)
        sTitan = new StakedTitan(address(titanToken), STITAN_REWARD_RATE, deployer);
        console.log("StakedTitan (sTitan) deployed at:", address(sTitan));

        // 6. Deploy Faucet
        faucet = new Faucet(address(titanToken), FAUCET_DRIP_AMOUNT, FAUCET_COOLDOWN, deployer);
        console.log("Faucet deployed at:", address(faucet));

        // 7. Fund contracts with TITAN
        titanToken.transfer(address(earn), STAKING_REWARDS_ALLOCATION);
        console.log("Funded Earn with:", STAKING_REWARDS_ALLOCATION / 1e18, "TITAN");

        titanToken.transfer(address(farm), FARM_REWARDS_ALLOCATION);
        console.log("Funded Farm with:", FARM_REWARDS_ALLOCATION / 1e18, "TITAN");

        titanToken.transfer(address(faucet), FAUCET_INITIAL_BALANCE);
        console.log("Funded Faucet with:", FAUCET_INITIAL_BALANCE / 1e18, "TITAN");

        titanToken.approve(address(sTitan), STITAN_INITIAL_REWARDS);
        sTitan.depositRewards(STITAN_INITIAL_REWARDS);
        console.log("Funded sTitan with:", STITAN_INITIAL_REWARDS / 1e18, "TITAN rewards");

        vm.stopBroadcast();

        // Log summary
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("Network: Sepolia Fork (Anvil)");
        console.log("Deployer:", deployer);
        console.log("\nTitan Contracts:");
        console.log("TitanToken:", address(titanToken));
        console.log("Earn:", address(earn));
        console.log("StakedTitan:", address(sTitan));
        console.log("Farm:", address(farm));
        console.log("Governor:", address(governor));
        console.log("Faucet:", address(faucet));
        console.log("\nUniswap V4 (Sepolia):");
        console.log("PoolManager:", POOL_MANAGER);
        console.log("UniversalRouter:", UNIVERSAL_ROUTER);
        console.log("PositionManager:", POSITION_MANAGER);
        console.log("Permit2:", PERMIT2);
        console.log("WETH:", WETH);
        console.log("=========================================\n");

        // Write addresses to JSON file
        _writeAddresses();
    }

    function _writeAddresses() internal {
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "network": "sepolia-fork",\n',
                '  "chainId": 31337,\n',
                '  "contracts": {\n',
                '    "titanToken": "',
                vm.toString(address(titanToken)),
                '",\n',
                '    "staking": "',
                vm.toString(address(earn)),
                '",\n',
                '    "farming": "',
                vm.toString(address(farm)),
                '",\n',
                '    "governance": "',
                vm.toString(address(governor)),
                '",\n',
                '    "stakedTitan": "',
                vm.toString(address(sTitan)),
                '",\n',
                '    "faucet": "',
                vm.toString(address(faucet)),
                '",\n',
                '    "poolManager": "',
                vm.toString(POOL_MANAGER),
                '",\n',
                '    "universalRouter": "',
                vm.toString(UNIVERSAL_ROUTER),
                '",\n',
                '    "positionManager": "',
                vm.toString(POSITION_MANAGER),
                '",\n',
                '    "permit2": "',
                vm.toString(PERMIT2),
                '",\n',
                '    "weth": "',
                vm.toString(WETH),
                '"\n',
                "  }\n",
                "}"
            )
        );

        vm.writeFile("deployments.json", json);
        console.log("Addresses written to deployments.json");
    }
}
