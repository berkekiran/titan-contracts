// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SetupAll
 * @notice Complete setup script for Titan development environment
 * @dev Deploys all contracts, initializes V4 pool, and adds initial liquidity
 */

import "forge-std/Script.sol";
import "../src/TitanToken.sol";
import "../src/Earn.sol";
import "../src/Governor.sol";
import "../src/Faucet.sol";
import "../src/SwapRouter.sol";
import "../src/StakedTitan.sol";
import "../src/LiquidityRouter.sol";

interface IPositionManagerScript {
    function initializePool(
        IPoolManager.PoolKey calldata key,
        uint160 sqrtPriceX96
    ) external payable returns (int24 tick);

    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20Ext {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract SetupAll is Script {
    // ============ Deployed Contracts ============
    TitanToken public titanToken;
    Earn public earn;
    StakedTitan public sTitan;
    Governor public governor;
    Faucet public faucet;
    SwapRouter public swapRouter;
    LiquidityRouter public liquidityRouter;

    // ============ Configuration ============
    uint256 public constant STAKING_REWARD_RATE = 1e15;
    uint256 public constant STITAN_REWARD_RATE = 1e10; // ~31.5% APY
    uint256 public constant PROPOSAL_THRESHOLD = 1_000 * 1e18;
    uint256 public constant VOTING_DELAY = 1; // 1 block delay
    uint256 public constant VOTING_PERIOD = 50400; // ~1 week in blocks
    uint256 public constant TIMELOCK_DELAY = 1 days;
    uint256 public constant QUORUM_PERCENTAGE = 400;
    uint256 public constant FAUCET_DRIP_AMOUNT = 100 * 1e18;
    uint256 public constant FAUCET_COOLDOWN = 24 hours;

    // Allocations
    uint256 public constant FAUCET_ALLOCATION = 10_000_000 * 1e18;
    uint256 public constant STAKING_ALLOCATION = 20_000_000 * 1e18;

    // Initial liquidity
    uint256 public constant INITIAL_TITAN_LIQUIDITY = 25_000 * 1e18;
    uint256 public constant INITIAL_ETH_LIQUIDITY = 0.5 ether;

    // ============ Uniswap V4 on Sepolia ============
    address public constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address public constant POSITION_MANAGER = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address public constant UNIVERSAL_ROUTER = 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b;
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant STATE_VIEW = 0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C;
    address public constant QUOTER = 0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227;
    address public constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // Pool config
    uint24 public constant POOL_FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;

    // sqrtPriceX96 for 1 TITAN = 0.0001 ETH
    uint160 public constant SQRT_PRICE_TITAN_IS_0 = 792281625142643375935439503;
    uint160 public constant SQRT_PRICE_WETH_IS_0 = 7922816251426433759354395033600;

    function run() external {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("       TITAN COMPLETE SETUP");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("ETH Balance:", deployer.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // ========== PHASE 1: Deploy Titan Contracts ==========
        _deployContracts(deployer);

        // ========== PHASE 2: Fund Contracts ==========
        _fundContracts();

        // ========== PHASE 3: Initialize V4 Pool ==========
        (address currency0, address currency1) = _initializePool();

        // ========== PHASE 4: Add Initial Liquidity ==========
        _addLiquidity(deployer, currency0, currency1);

        vm.stopBroadcast();

        // ========== Write Deployment Info ==========
        _writeDeploymentInfo(currency0, currency1);

        _printSummary(currency0, currency1);
    }

    function _deployContracts(address deployer) internal {
        console.log("\n--- Deploying Contracts ---");

        titanToken = new TitanToken(deployer);
        console.log("TitanToken:", address(titanToken));

        earn = new Earn(address(titanToken), STAKING_REWARD_RATE, deployer);
        console.log("Earn:", address(earn));

        sTitan = new StakedTitan(address(titanToken), STITAN_REWARD_RATE, deployer);
        console.log("StakedTitan:", address(sTitan));

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

        swapRouter = new SwapRouter(POOL_MANAGER, deployer);
        console.log("SwapRouter:", address(swapRouter));

        liquidityRouter = new LiquidityRouter(POOL_MANAGER, STATE_VIEW, deployer);
        console.log("LiquidityRouter:", address(liquidityRouter));
    }

    function _fundContracts() internal {
        console.log("\n--- Funding Contracts ---");

        titanToken.transfer(address(faucet), FAUCET_ALLOCATION);
        console.log("Faucet funded:", FAUCET_ALLOCATION / 1e18, "TITAN");

        titanToken.transfer(address(earn), STAKING_ALLOCATION);
        console.log("Earn funded:", STAKING_ALLOCATION / 1e18, "TITAN");
    }

    function _initializePool() internal returns (address currency0, address currency1) {
        console.log("\n--- Initializing V4 Pool ---");

        // Sort tokens
        if (uint160(address(titanToken)) < uint160(WETH)) {
            currency0 = address(titanToken);
            currency1 = WETH;
        } else {
            currency0 = WETH;
            currency1 = address(titanToken);
        }

        console.log("Currency0:", currency0);
        console.log("Currency1:", currency1);

        bool titanIsCurrency0 = currency0 == address(titanToken);
        uint160 sqrtPriceX96 = titanIsCurrency0 ? SQRT_PRICE_TITAN_IS_0 : SQRT_PRICE_WETH_IS_0;

        IPoolManager.PoolKey memory poolKey = IPoolManager.PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        // Initialize via PoolManager
        try IPoolManager(POOL_MANAGER).initialize(poolKey, sqrtPriceX96) returns (int24 tick) {
            console.log("Pool initialized at tick:", tick);
        } catch {
            console.log("Pool may already be initialized");
        }

        return (currency0, currency1);
    }

    function _addLiquidity(address deployer, address currency0, address currency1) internal {
        console.log("\n--- Setting Up for Liquidity ---");

        // Wrap some ETH to WETH for the deployer to use
        IWETH(WETH).deposit{value: INITIAL_ETH_LIQUIDITY}();
        console.log("Wrapped", INITIAL_ETH_LIQUIDITY / 1e18, "ETH to WETH");

        // Approve tokens to Permit2
        IERC20Ext(address(titanToken)).approve(PERMIT2, type(uint256).max);
        IWETH(WETH).approve(PERMIT2, type(uint256).max);

        // Also approve directly to PositionManager
        IERC20Ext(address(titanToken)).approve(POSITION_MANAGER, type(uint256).max);
        IWETH(WETH).approve(POSITION_MANAGER, type(uint256).max);

        // Approve Permit2 to PositionManager
        IPermit2(PERMIT2).approve(address(titanToken), POSITION_MANAGER, type(uint160).max, type(uint48).max);
        IPermit2(PERMIT2).approve(WETH, POSITION_MANAGER, type(uint160).max, type(uint48).max);

        // Also approve to UniversalRouter for swaps
        IERC20Ext(address(titanToken)).approve(UNIVERSAL_ROUTER, type(uint256).max);
        IWETH(WETH).approve(UNIVERSAL_ROUTER, type(uint256).max);
        IPermit2(PERMIT2).approve(address(titanToken), UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);

        // Approve to LiquidityRouter
        IERC20Ext(address(titanToken)).approve(address(liquidityRouter), type(uint256).max);
        IWETH(WETH).approve(address(liquidityRouter), type(uint256).max);

        console.log("All approvals complete");
        console.log("WETH balance:", IWETH(WETH).balanceOf(deployer) / 1e18);
        console.log("TITAN balance:", IERC20Ext(address(titanToken)).balanceOf(deployer) / 1e18);
        console.log("");
        console.log("Pool is ready! Add liquidity via the app.");
    }

    function _writeDeploymentInfo(address currency0, address currency1) internal {
        string memory json = string(
            abi.encodePacked(
                '{\n',
                '  "network": "sepolia-fork",\n',
                '  "chainId": 31337,\n',
                '  "timestamp": "', vm.toString(block.timestamp), '",\n',
                '  "contracts": {\n',
                '    "titanToken": "', vm.toString(address(titanToken)), '",\n',
                '    "staking": "', vm.toString(address(earn)), '",\n',
                '    "stakedTitan": "', vm.toString(address(sTitan)), '",\n',
                '    "governance": "', vm.toString(address(governor)), '",\n',
                '    "faucet": "', vm.toString(address(faucet)), '",\n',
                '    "swapRouter": "', vm.toString(address(swapRouter)), '",\n',
                '    "liquidityRouter": "', vm.toString(address(liquidityRouter)), '"\n',
                '  },\n',
                '  "uniswapV4": {\n',
                '    "poolManager": "', vm.toString(POOL_MANAGER), '",\n',
                '    "positionManager": "', vm.toString(POSITION_MANAGER), '",\n',
                '    "universalRouter": "', vm.toString(UNIVERSAL_ROUTER), '",\n',
                '    "permit2": "', vm.toString(PERMIT2), '",\n',
                '    "stateView": "', vm.toString(STATE_VIEW), '",\n',
                '    "quoter": "', vm.toString(QUOTER), '",\n',
                '    "weth": "', vm.toString(WETH), '"\n',
                '  },\n',
                '  "pool": {\n',
                '    "currency0": "', vm.toString(currency0), '",\n',
                '    "currency1": "', vm.toString(currency1), '",\n',
                '    "fee": 3000,\n',
                '    "tickSpacing": 60,\n',
                '    "hooks": "0x0000000000000000000000000000000000000000"\n',
                '  }\n',
                '}'
            )
        );

        vm.writeFile("deployments-dev.json", json);
    }

    function _printSummary(address currency0, address currency1) internal view {
        console.log("\n========================================");
        console.log("         SETUP COMPLETE!");
        console.log("========================================");
        console.log("\n--- Titan Contracts ---");
        console.log("TitanToken:  ", address(titanToken));
        console.log("Earn:        ", address(earn));
        console.log("StakedTitan: ", address(sTitan));
        console.log("Governor:    ", address(governor));
        console.log("Faucet:      ", address(faucet));
        console.log("SwapRouter:  ", address(swapRouter));
        console.log("LiqRouter:   ", address(liquidityRouter));
        console.log("\n--- Pool ---");
        console.log("Currency0:   ", currency0);
        console.log("Currency1:   ", currency1);
        console.log("Fee:          0.3%");
        console.log("\n--- Balances ---");
        console.log("Faucet TITAN:", IERC20Ext(address(titanToken)).balanceOf(address(faucet)) / 1e18);
        console.log("Earn TITAN:", IERC20Ext(address(titanToken)).balanceOf(address(earn)) / 1e18);
        console.log("\nDeployment info written to: deployments-dev.json");
        console.log("========================================\n");
    }
}
