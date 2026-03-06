// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployV4
 * @author Titan Team
 * @notice Production deployment script for Titan with Uniswap V4 on Sepolia
 * @dev Deploys contracts, initializes V4 pool, and adds initial liquidity
 */

import "forge-std/Script.sol";
import "../src/TitanToken.sol";
import "../src/Earn.sol";
import "../src/Farm.sol";
import "../src/Governor.sol";
import "../src/Faucet.sol";

// Uniswap V4 interfaces
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
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}

interface IPoolInitializer {
    function initializePool(
        IPoolManager.PoolKey calldata key,
        uint160 sqrtPriceX96
    ) external returns (int24 tick);
}

interface IAllowanceTransfer {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20Minimal {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract DeployV4 is Script {
    // Deployed contract addresses
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

    // Initial liquidity
    uint256 public constant INITIAL_TITAN_LIQUIDITY = 1_000_000 * 1e18; // 1M TITAN
    uint256 public constant INITIAL_ETH_LIQUIDITY = 100 ether; // 100 ETH

    // Uniswap V4 on Sepolia
    address public constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address public constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address public constant UNIVERSAL_ROUTER = 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant STATE_VIEW = 0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C;
    address public constant QUOTER = 0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227;

    // WETH on Sepolia
    address public constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // Pool configuration - 0.3% fee, 60 tick spacing (standard for 0.3%)
    uint24 public constant POOL_FEE = 3000;
    int24 public constant TICK_SPACING = 60;
    address public constant NO_HOOKS = address(0);

    // Starting price: 1 TITAN = 0.0001 ETH (sqrtPriceX96 for this ratio)
    // sqrt(0.0001) * 2^96 = 7922816251426433759354395034 (approximately)
    uint160 public constant INITIAL_SQRT_PRICE = 7922816251426433759354395034;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Titan V4 Production Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Deployer ETH balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // ========== PHASE 1: Deploy Titan Contracts ==========
        console.log("\n--- Phase 1: Deploying Titan Contracts ---");

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
        console.log("Funded Earn, Farm, and Faucet");

        // ========== PHASE 2: Initialize V4 Pool ==========
        console.log("\n--- Phase 2: Initializing V4 Pool ---");

        // Sort tokens (currency0 < currency1)
        address currency0;
        address currency1;
        if (uint160(address(titanToken)) < uint160(WETH)) {
            currency0 = address(titanToken);
            currency1 = WETH;
        } else {
            currency0 = WETH;
            currency1 = address(titanToken);
        }
        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);

        // Create PoolKey
        IPoolManager.PoolKey memory poolKey = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: NO_HOOKS
        });

        // Initialize the pool
        int24 tick = IPoolManager(POOL_MANAGER).initialize(poolKey, INITIAL_SQRT_PRICE);
        console.log("Pool initialized at tick:", tick);

        // ========== PHASE 3: Add Initial Liquidity ==========
        console.log("\n--- Phase 3: Adding Initial Liquidity ---");

        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: INITIAL_ETH_LIQUIDITY}();
        console.log("Wrapped", INITIAL_ETH_LIQUIDITY / 1e18, "ETH to WETH");

        // Approve tokens to Permit2
        IERC20Minimal(address(titanToken)).approve(PERMIT2, type(uint256).max);
        IWETH(WETH).approve(PERMIT2, type(uint256).max);
        console.log("Approved tokens to Permit2");

        // Approve Permit2 to PositionManager
        IAllowanceTransfer(PERMIT2).approve(
            address(titanToken),
            POSITION_MANAGER,
            type(uint160).max,
            type(uint48).max
        );
        IAllowanceTransfer(PERMIT2).approve(
            WETH,
            POSITION_MANAGER,
            type(uint160).max,
            type(uint48).max
        );
        console.log("Approved Permit2 to PositionManager");

        // Add liquidity via PositionManager multicall
        // For simplicity, we'll use a wide range position
        int24 tickLower = -887220; // Near minimum
        int24 tickUpper = 887220;  // Near maximum

        // Encode actions for minting position
        // Actions: MINT_POSITION (2), SETTLE_PAIR (13)
        bytes memory actions = abi.encodePacked(uint8(2), uint8(13));

        // Encode parameters
        bytes[] memory params = new bytes[](2);

        // MINT_POSITION params
        params[0] = abi.encode(
            poolKey,
            tickLower,
            tickUpper,
            uint256(1e21), // liquidity amount (large position)
            INITIAL_TITAN_LIQUIDITY,
            INITIAL_ETH_LIQUIDITY,
            deployer,
            bytes("")
        );

        // SETTLE_PAIR params
        params[1] = abi.encode(currency0, currency1);

        // Create multicall data
        bytes[] memory multicallData = new bytes[](2);

        // First call: initialize pool (in case not initialized)
        multicallData[0] = abi.encodeWithSelector(
            IPoolInitializer.initializePool.selector,
            poolKey,
            INITIAL_SQRT_PRICE
        );

        // Second call: modify liquidities
        multicallData[1] = abi.encodeWithSignature(
            "modifyLiquidities(bytes,uint256)",
            abi.encode(actions, params),
            block.timestamp + 3600
        );

        // Execute - try/catch in case pool already initialized
        try IPositionManager(POSITION_MANAGER).multicall(multicallData) {
            console.log("Liquidity added successfully");
        } catch {
            // Try just adding liquidity
            bytes[] memory liquidityOnly = new bytes[](1);
            liquidityOnly[0] = multicallData[1];
            try IPositionManager(POSITION_MANAGER).multicall(liquidityOnly) {
                console.log("Liquidity added (pool was already initialized)");
            } catch Error(string memory reason) {
                console.log("Failed to add liquidity:", reason);
            }
        }

        vm.stopBroadcast();

        // ========== Summary ==========
        console.log("\n========== DEPLOYMENT COMPLETE ==========");
        console.log("Network: Sepolia Fork");
        console.log("\n--- Titan Contracts ---");
        console.log("TitanToken:", address(titanToken));
        console.log("Earn:", address(earn));
        console.log("Farm:", address(farm));
        console.log("Governor:", address(governor));
        console.log("Faucet:", address(faucet));
        console.log("\n--- Uniswap V4 ---");
        console.log("PoolManager:", POOL_MANAGER);
        console.log("PositionManager:", POSITION_MANAGER);
        console.log("UniversalRouter:", UNIVERSAL_ROUTER);
        console.log("Permit2:", PERMIT2);
        console.log("StateView:", STATE_VIEW);
        console.log("Quoter:", QUOTER);
        console.log("\n--- Pool ---");
        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);
        console.log("Fee:", POOL_FEE);
        console.log("TickSpacing:", TICK_SPACING);
        console.log("==========================================\n");

        _writeAddresses(currency0, currency1);
    }

    function _writeAddresses(address currency0, address currency1) internal {
        string memory json = string(
            abi.encodePacked(
                '{\n',
                '  "network": "sepolia-fork",\n',
                '  "chainId": 31337,\n',
                '  "contracts": {\n',
                '    "titanToken": "', vm.toString(address(titanToken)), '",\n',
                '    "staking": "', vm.toString(address(earn)), '",\n',
                '    "farming": "', vm.toString(address(farm)), '",\n',
                '    "governance": "', vm.toString(address(governor)), '",\n',
                '    "faucet": "', vm.toString(address(faucet)), '",\n',
                '    "poolManager": "', vm.toString(POOL_MANAGER), '",\n',
                '    "universalRouter": "', vm.toString(UNIVERSAL_ROUTER), '",\n',
                '    "positionManager": "', vm.toString(POSITION_MANAGER), '",\n',
                '    "permit2": "', vm.toString(PERMIT2), '",\n',
                '    "stateView": "', vm.toString(STATE_VIEW), '",\n',
                '    "quoter": "', vm.toString(QUOTER), '",\n',
                '    "weth": "', vm.toString(WETH), '"\n',
                '  },\n',
                '  "pool": {\n',
                '    "currency0": "', vm.toString(currency0), '",\n',
                '    "currency1": "', vm.toString(currency1), '",\n',
                '    "fee": ', vm.toString(POOL_FEE), ',\n',
                '    "tickSpacing": ', vm.toString(int256(TICK_SPACING)), ',\n',
                '    "hooks": "0x0000000000000000000000000000000000000000"\n',
                '  }\n',
                '}'
            )
        );

        vm.writeFile("deployments-v4.json", json);
        console.log("Addresses written to deployments-v4.json");
    }
}
