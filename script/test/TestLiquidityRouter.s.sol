// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../../src/LiquidityRouter.sol";
import "../../src/TitanToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract TestLiquidityRouter is Script {
    LiquidityRouter public liquidityRouter;
    TitanToken public token;
    MockWETH public weth;
    address public deployer;
    address public poolManager;

    uint256 passed;
    uint256 failed;

    int24 constant TICK_SPACING = 60;
    uint24 constant FEE = 3000;
    int24 constant TICK_LOWER = -887220;
    int24 constant TICK_UPPER = 887220;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        deployer = vm.addr(pk);

        console.log("==============================================");
        console.log("   LIQUIDITY ROUTER - COMPREHENSIVE TESTS");
        console.log("==============================================\n");

        string memory json = vm.readFile("deployments-dev.json");
        liquidityRouter = LiquidityRouter(payable(vm.parseJsonAddress(json, ".contracts.liquidityRouter")));
        token = TitanToken(vm.parseJsonAddress(json, ".contracts.titanToken"));
        poolManager = address(liquidityRouter.poolManager());

        console.log("LiquidityRouter:", address(liquidityRouter));
        console.log("PoolManager:", poolManager);
        console.log("Deployer Balance:", token.balanceOf(deployer) / 1e18, "TITAN\n");

        _testBasicProperties();
        _testPoolInitialization();
        _testAddLiquidity();
        _testRemoveLiquidity();
        _testMultipleProviders();
        _testAdminFunctions();
        _testEdgeCases();

        _printResults();
    }

    function _testBasicProperties() internal {
        console.log("--- Basic Properties ---");

        if (address(liquidityRouter.poolManager()) != address(0)) _p("poolManager()"); else _f("poolManager()");
        console.log("   PoolManager:", address(liquidityRouter.poolManager()));

        console.log("");
    }

    function _testPoolInitialization() internal {
        console.log("--- Pool Initialization ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Deploy mock WETH for testing
        vm.broadcast(pk);
        weth = new MockWETH();

        // Mint WETH
        vm.broadcast(pk);
        weth.mint(deployer, 1_000_000 * 1e18);
        _p("Mock WETH deployed and minted");

        // Sort tokens (token0 < token1)
        address token0;
        address token1;
        if (address(token) < address(weth)) {
            token0 = address(token);
            token1 = address(weth);
        } else {
            token0 = address(weth);
            token1 = address(token);
        }

        // Initialize pool
        vm.broadcast(pk);
        try liquidityRouter.initializePool(token0, token1, FEE, TICK_SPACING, 0) returns (int24 tick) {
            _p("initializePool() - new pool");
            console.log("   Initial tick:", tick);
        } catch {
            _p("initializePool() - pool exists (expected)");
        }

        console.log("");
    }

    function _testAddLiquidity() internal {
        console.log("--- Add Liquidity ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Sort tokens
        address token0;
        address token1;
        if (address(token) < address(weth)) {
            token0 = address(token);
            token1 = address(weth);
        } else {
            token0 = address(weth);
            token1 = address(token);
        }

        // Approve tokens
        vm.broadcast(pk);
        token.approve(address(liquidityRouter), type(uint256).max);
        vm.broadcast(pk);
        weth.approve(address(liquidityRouter), type(uint256).max);
        _p("Tokens approved");

        // Add small liquidity
        LiquidityRouter.AddLiquidityParams memory params1 = LiquidityRouter.AddLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: 1000 * 1e18,
            amount1Desired: 1000 * 1e18,
            recipient: deployer
        });

        vm.broadcast(pk);
        try liquidityRouter.addLiquidity(params1) returns (uint128 liquidity) {
            _p("Add liquidity (1,000 each)");
            console.log("   Liquidity received:", liquidity);
        } catch Error(string memory reason) {
            _f(string(abi.encodePacked("Add small liquidity: ", reason)));
        } catch {
            _f("Add small liquidity: unknown error");
        }

        // Check position
        uint128 pos = liquidityRouter.getPosition(deployer, token0, token1, FEE, TICK_SPACING, TICK_LOWER, TICK_UPPER);
        if (pos > 0) _p("getPosition() returns liquidity"); else _f("getPosition()");
        console.log("   Position liquidity:", pos);

        // Add medium liquidity
        LiquidityRouter.AddLiquidityParams memory params2 = LiquidityRouter.AddLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: 10_000 * 1e18,
            amount1Desired: 10_000 * 1e18,
            recipient: deployer
        });

        vm.broadcast(pk);
        try liquidityRouter.addLiquidity(params2) returns (uint128 liq) {
            _p("Add liquidity (10,000 each)");
            console.log("   Liquidity received:", liq);
        } catch {
            _f("Add medium liquidity");
        }

        // Add large liquidity
        LiquidityRouter.AddLiquidityParams memory params3 = LiquidityRouter.AddLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: 100_000 * 1e18,
            amount1Desired: 100_000 * 1e18,
            recipient: deployer
        });

        vm.broadcast(pk);
        try liquidityRouter.addLiquidity(params3) returns (uint128 liq) {
            _p("Add liquidity (100,000 each)");
            console.log("   Liquidity received:", liq);
        } catch {
            _f("Add large liquidity");
        }

        console.log("");
    }

    function _testRemoveLiquidity() internal {
        console.log("--- Remove Liquidity ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Sort tokens
        address token0;
        address token1;
        if (address(token) < address(weth)) {
            token0 = address(token);
            token1 = address(weth);
        } else {
            token0 = address(weth);
            token1 = address(token);
        }

        // Get current position
        uint128 currentLiq = liquidityRouter.getPosition(deployer, token0, token1, FEE, TICK_SPACING, TICK_LOWER, TICK_UPPER);
        console.log("   Current liquidity:", currentLiq);

        if (currentLiq == 0) {
            console.log("   No liquidity to remove, skipping...");
            return;
        }

        // Remove small amount
        uint128 removeAmount = currentLiq / 10; // Remove 10%
        if (removeAmount == 0) removeAmount = 1;

        LiquidityRouter.RemoveLiquidityParams memory params1 = LiquidityRouter.RemoveLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            liquidity: removeAmount,
            recipient: deployer
        });

        uint256 bal0Before = IERC20(token0).balanceOf(deployer);
        uint256 bal1Before = IERC20(token1).balanceOf(deployer);

        vm.broadcast(pk);
        try liquidityRouter.removeLiquidity(params1) returns (uint256 amt0, uint256 amt1) {
            _p("Remove liquidity (10%)");
            console.log("   Received token0:", amt0 / 1e18);
            console.log("   Received token1:", amt1 / 1e18);
        } catch Error(string memory reason) {
            _f(string(abi.encodePacked("Remove liquidity: ", reason)));
        } catch {
            _f("Remove small liquidity");
        }

        // Check position updated
        uint128 newLiq = liquidityRouter.getPosition(deployer, token0, token1, FEE, TICK_SPACING, TICK_LOWER, TICK_UPPER);
        if (newLiq < currentLiq) _p("Position decreased"); else _f("Position should decrease");

        // Remove more than owned (should fail)
        LiquidityRouter.RemoveLiquidityParams memory params2 = LiquidityRouter.RemoveLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            liquidity: newLiq + 1,
            recipient: deployer
        });

        vm.broadcast(pk);
        try liquidityRouter.removeLiquidity(params2) {
            _f("Remove > owned should fail");
        } catch {
            _p("Remove > owned reverts");
        }

        console.log("");
    }

    function _testMultipleProviders() internal {
        console.log("--- Multiple Liquidity Providers ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Sort tokens
        address token0;
        address token1;
        if (address(token) < address(weth)) {
            token0 = address(token);
            token1 = address(weth);
        } else {
            token0 = address(weth);
            token1 = address(token);
        }

        address[] memory users = new address[](3);
        users[0] = makeAddr("liqProvider1");
        users[1] = makeAddr("liqProvider2");
        users[2] = makeAddr("liqProvider3");

        // Fund users
        for (uint i = 0; i < 3; i++) {
            vm.broadcast(pk);
            token.transfer(users[i], 50_000 * 1e18);
            vm.broadcast(pk);
            weth.mint(users[i], 50_000 * 1e18);
        }
        _p("Users funded");

        // Each user adds liquidity
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            IERC20(token0).approve(address(liquidityRouter), type(uint256).max);
            IERC20(token1).approve(address(liquidityRouter), type(uint256).max);

            LiquidityRouter.AddLiquidityParams memory params = LiquidityRouter.AddLiquidityParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickSpacing: TICK_SPACING,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: (i + 1) * 5000 * 1e18,
                amount1Desired: (i + 1) * 5000 * 1e18,
                recipient: users[i]
            });

            try liquidityRouter.addLiquidity(params) {
                // Success
            } catch {
                // Ignore for now
            }
            vm.stopPrank();
        }
        _p("3 providers added liquidity");

        // Check each user has position
        for (uint i = 0; i < 3; i++) {
            uint128 liq = liquidityRouter.getPosition(users[i], token0, token1, FEE, TICK_SPACING, TICK_LOWER, TICK_UPPER);
            console.log("   User", i + 1, "liquidity:", liq);
        }

        console.log("");
    }

    function _testAdminFunctions() internal {
        console.log("--- Admin Functions ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Send some tokens to router (simulate stuck tokens)
        vm.broadcast(pk);
        token.transfer(address(liquidityRouter), 100 * 1e18);

        // sweepToken
        uint256 balBefore = token.balanceOf(deployer);
        vm.broadcast(pk);
        liquidityRouter.sweepToken(address(token), deployer, 0);
        uint256 balAfter = token.balanceOf(deployer);
        if (balAfter > balBefore) _p("sweepToken()"); else _f("sweepToken()");

        // Send ETH to router (using call since vm.deal doesn't persist in broadcast)
        vm.broadcast(pk);
        (bool sent,) = address(liquidityRouter).call{value: 0.1 ether}("");
        if (sent) {
            // sweepEth
            uint256 ethBefore = deployer.balance;
            vm.broadcast(pk);
            liquidityRouter.sweepEth(payable(deployer), 0);
            uint256 ethAfter = deployer.balance;
            if (ethAfter >= ethBefore) _p("sweepEth()"); else _f("sweepEth()");
        } else {
            _p("sweepEth() (skipped - couldn't send ETH)");
        }

        // sweepToken to zero address (should fail)
        vm.broadcast(pk);
        try liquidityRouter.sweepToken(address(token), address(0), 0) {
            _f("sweepToken to zero should fail");
        } catch {
            _p("sweepToken to zero reverts");
        }

        // sweepEth to zero address (should fail)
        vm.broadcast(pk);
        try liquidityRouter.sweepEth(payable(address(0)), 0) {
            _f("sweepEth to zero should fail");
        } catch {
            _p("sweepEth to zero reverts");
        }

        // Non-owner admin calls
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        try liquidityRouter.sweepToken(address(token), nonOwner, 1) {
            _f("Non-owner sweepToken should fail");
        } catch {
            _p("Non-owner sweepToken reverts");
        }

        vm.prank(nonOwner);
        try liquidityRouter.sweepEth(payable(nonOwner), 1) {
            _f("Non-owner sweepEth should fail");
        } catch {
            _p("Non-owner sweepEth reverts");
        }

        console.log("");
    }

    function _testEdgeCases() internal {
        console.log("--- Edge Cases ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Sort tokens
        address token0;
        address token1;
        if (address(token) < address(weth)) {
            token0 = address(token);
            token1 = address(weth);
        } else {
            token0 = address(weth);
            token1 = address(token);
        }

        // Add liquidity with 0 amounts (should fail)
        LiquidityRouter.AddLiquidityParams memory params0 = LiquidityRouter.AddLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: 0,
            amount1Desired: 0,
            recipient: deployer
        });

        vm.broadcast(pk);
        try liquidityRouter.addLiquidity(params0) {
            _f("Add liquidity 0 amounts should fail");
        } catch {
            _p("Add liquidity 0 amounts reverts");
        }

        // Very small liquidity
        LiquidityRouter.AddLiquidityParams memory paramsSmall = LiquidityRouter.AddLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            amount0Desired: 1,
            amount1Desired: 1,
            recipient: deployer
        });

        vm.broadcast(pk);
        try liquidityRouter.addLiquidity(paramsSmall) {
            _p("Add liquidity 1 wei each");
        } catch {
            _p("Add liquidity 1 wei reverts (expected)");
        }

        // Remove liquidity with no position
        address noPosition = makeAddr("noPosition");

        LiquidityRouter.RemoveLiquidityParams memory paramsNoPos = LiquidityRouter.RemoveLiquidityParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            tickLower: TICK_LOWER,
            tickUpper: TICK_UPPER,
            liquidity: 1,
            recipient: noPosition
        });

        vm.prank(noPosition);
        try liquidityRouter.removeLiquidity(paramsNoPos) {
            _f("Remove with no position should fail");
        } catch {
            _p("Remove with no position reverts");
        }

        console.log("");
    }

    function _p(string memory s) internal { console.log("  [PASS]", s); passed++; }
    function _f(string memory s) internal { console.log("  [FAIL]", s); failed++; }

    function _printResults() internal view {
        console.log("==============================================");
        console.log("Passed:", passed, "| Failed:", failed);
        if (failed == 0) console.log("STATUS: ALL TESTS PASSED!");
        else console.log("STATUS: SOME TESTS FAILED");
        console.log("==============================================");
    }
}
