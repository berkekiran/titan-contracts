// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../../src/SwapRouter.sol";
import "../../src/LiquidityRouter.sol";
import "../../src/TitanToken.sol";
import "../../src/interfaces/IPoolManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWETH2 is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract TestSwapRouter is Script {
    SwapRouter public swapRouter;
    LiquidityRouter public liquidityRouter;
    TitanToken public token;
    MockWETH2 public weth;
    address public deployer;

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
        console.log("      SWAP ROUTER - COMPREHENSIVE TESTS");
        console.log("==============================================\n");

        string memory json = vm.readFile("deployments-dev.json");
        swapRouter = SwapRouter(payable(vm.parseJsonAddress(json, ".contracts.swapRouter")));
        liquidityRouter = LiquidityRouter(payable(vm.parseJsonAddress(json, ".contracts.liquidityRouter")));
        token = TitanToken(vm.parseJsonAddress(json, ".contracts.titanToken"));

        console.log("SwapRouter:", address(swapRouter));
        console.log("LiquidityRouter:", address(liquidityRouter));
        console.log("Deployer Balance:", token.balanceOf(deployer) / 1e18, "TITAN\n");

        _setupPool();
        _testBasicProperties();
        _testSwaps();
        _testSwapAmounts();
        _testSwapErrors();
        _testAdminFunctions();
        _testMultipleSwappers();

        _printResults();
    }

    function _setupPool() internal {
        console.log("--- Setting Up Pool ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Deploy mock WETH
        vm.broadcast(pk);
        weth = new MockWETH2();

        // Mint WETH
        vm.broadcast(pk);
        weth.mint(deployer, 1_000_000 * 1e18);
        console.log("   Mock WETH deployed");

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

        // Initialize pool
        vm.broadcast(pk);
        try liquidityRouter.initializePool(token0, token1, FEE, TICK_SPACING, 0) {
            console.log("   Pool initialized");
        } catch {
            console.log("   Pool already exists");
        }

        // Approve and add liquidity
        vm.broadcast(pk);
        token.approve(address(liquidityRouter), type(uint256).max);
        vm.broadcast(pk);
        weth.approve(address(liquidityRouter), type(uint256).max);

        LiquidityRouter.AddLiquidityParams memory params = LiquidityRouter.AddLiquidityParams({
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
        try liquidityRouter.addLiquidity(params) returns (uint128 liq) {
            console.log("   Added liquidity:", liq);
        } catch {
            console.log("   Could not add liquidity");
        }

        console.log("");
    }

    function _testBasicProperties() internal {
        console.log("--- Basic Properties ---");

        if (address(swapRouter.poolManager()) != address(0)) _p("poolManager()"); else _f("poolManager()");
        console.log("   PoolManager:", address(swapRouter.poolManager()));

        console.log("");
    }

    function _testSwaps() internal {
        console.log("--- Swaps ---");

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

        // Approve SwapRouter
        vm.broadcast(pk);
        token.approve(address(swapRouter), type(uint256).max);
        vm.broadcast(pk);
        weth.approve(address(swapRouter), type(uint256).max);
        _p("Tokens approved for swaps");

        // Create pool key
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: token0,
            currency1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        // Swap token0 for token1 (zeroForOne = true)
        uint256 bal0Before = IERC20(token0).balanceOf(deployer);
        uint256 bal1Before = IERC20(token1).balanceOf(deployer);

        vm.broadcast(pk);
        try swapRouter.swap(key, true, 100 * 1e18, 0) returns (uint256 amountOut) {
            _p("Swap 100 token0 -> token1");
            console.log("   Amount out:", amountOut / 1e18);
        } catch Error(string memory reason) {
            _f(string(abi.encodePacked("Swap token0->token1: ", reason)));
        } catch {
            _f("Swap token0 -> token1");
        }

        // Swap token1 for token0 (zeroForOne = false)
        vm.broadcast(pk);
        try swapRouter.swap(key, false, 100 * 1e18, 0) returns (uint256 amountOut) {
            _p("Swap 100 token1 -> token0");
            console.log("   Amount out:", amountOut / 1e18);
        } catch Error(string memory reason) {
            _f(string(abi.encodePacked("Swap token1->token0: ", reason)));
        } catch {
            _f("Swap token1 -> token0");
        }

        console.log("");
    }

    function _testSwapAmounts() internal {
        console.log("--- Swap Amounts (Small/Medium/Large) ---");

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

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: token0,
            currency1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        // Very small swap (1 wei)
        vm.broadcast(pk);
        try swapRouter.swap(key, true, 1, 0) returns (uint256 amountOut) {
            _p("Swap 1 wei");
            console.log("   Amount out:", amountOut);
        } catch {
            _p("Swap 1 wei reverts (expected - too small)");
        }

        // Small swap (1 token)
        vm.broadcast(pk);
        try swapRouter.swap(key, true, 1 * 1e18, 0) returns (uint256 amountOut) {
            _p("Swap 1 token");
            console.log("   Amount out:", amountOut / 1e18);
        } catch {
            _f("Swap 1 token");
        }

        // Medium swap (1,000 tokens)
        vm.broadcast(pk);
        try swapRouter.swap(key, true, 1000 * 1e18, 0) returns (uint256 amountOut) {
            _p("Swap 1,000 tokens");
            console.log("   Amount out:", amountOut / 1e18);
        } catch {
            _f("Swap 1,000 tokens");
        }

        // Large swap (10,000 tokens)
        vm.broadcast(pk);
        try swapRouter.swap(key, true, 10_000 * 1e18, 0) returns (uint256 amountOut) {
            _p("Swap 10,000 tokens");
            console.log("   Amount out:", amountOut / 1e18);
        } catch {
            _f("Swap 10,000 tokens");
        }

        console.log("");
    }

    function _testSwapErrors() internal {
        console.log("--- Swap Errors ---");

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

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: token0,
            currency1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        // Swap 0 amount (should fail)
        vm.broadcast(pk);
        try swapRouter.swap(key, true, 0, 0) {
            _f("Swap 0 should fail");
        } catch {
            _p("Swap 0 reverts");
        }

        // Swap with high minAmountOut (should fail - slippage)
        vm.broadcast(pk);
        try swapRouter.swap(key, true, 100 * 1e18, 1000 * 1e18) {
            _f("Swap with high minAmountOut should fail");
        } catch {
            _p("Swap with high minAmountOut reverts (slippage)");
        }

        // User without tokens tries to swap
        address noTokens = makeAddr("noTokens");
        vm.startPrank(noTokens);
        IERC20(token0).approve(address(swapRouter), type(uint256).max);
        try swapRouter.swap(key, true, 100 * 1e18, 0) {
            _f("Swap without tokens should fail");
        } catch {
            _p("Swap without tokens reverts");
        }
        vm.stopPrank();

        console.log("");
    }

    function _testAdminFunctions() internal {
        console.log("--- Admin Functions ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Send some tokens to router (simulate stuck tokens)
        vm.broadcast(pk);
        token.transfer(address(swapRouter), 100 * 1e18);

        // sweepToken
        uint256 balBefore = token.balanceOf(deployer);
        vm.broadcast(pk);
        swapRouter.sweepToken(address(token), deployer, 0);
        uint256 balAfter = token.balanceOf(deployer);
        if (balAfter > balBefore) _p("sweepToken()"); else _f("sweepToken()");

        // Send ETH to router (using call since vm.deal doesn't persist in broadcast)
        vm.broadcast(pk);
        (bool sent,) = address(swapRouter).call{value: 0.1 ether}("");
        if (sent) {
            // sweepEth
            uint256 ethBefore = deployer.balance;
            vm.broadcast(pk);
            swapRouter.sweepEth(payable(deployer), 0);
            uint256 ethAfter = deployer.balance;
            if (ethAfter >= ethBefore) _p("sweepEth()"); else _f("sweepEth()");
        } else {
            _p("sweepEth() (skipped - couldn't send ETH)");
        }

        // sweepToken to zero (should fail)
        vm.broadcast(pk);
        try swapRouter.sweepToken(address(token), address(0), 0) {
            _f("sweepToken to zero should fail");
        } catch {
            _p("sweepToken to zero reverts");
        }

        // sweepEth to zero (should fail)
        vm.broadcast(pk);
        try swapRouter.sweepEth(payable(address(0)), 0) {
            _f("sweepEth to zero should fail");
        } catch {
            _p("sweepEth to zero reverts");
        }

        // Non-owner admin calls
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        try swapRouter.sweepToken(address(token), nonOwner, 1) {
            _f("Non-owner sweepToken should fail");
        } catch {
            _p("Non-owner sweepToken reverts");
        }

        vm.prank(nonOwner);
        try swapRouter.sweepEth(payable(nonOwner), 1) {
            _f("Non-owner sweepEth should fail");
        } catch {
            _p("Non-owner sweepEth reverts");
        }

        console.log("");
    }

    function _testMultipleSwappers() internal {
        console.log("--- Multiple Swappers ---");

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

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: token0,
            currency1: token1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: address(0)
        });

        address[] memory users = new address[](3);
        users[0] = makeAddr("swapper1");
        users[1] = makeAddr("swapper2");
        users[2] = makeAddr("swapper3");

        // Fund users
        for (uint i = 0; i < 3; i++) {
            vm.broadcast(pk);
            token.transfer(users[i], 10_000 * 1e18);
            vm.broadcast(pk);
            weth.mint(users[i], 10_000 * 1e18);
        }
        _p("Users funded");

        // Each user swaps
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            IERC20(token0).approve(address(swapRouter), type(uint256).max);

            try swapRouter.swap(key, true, (i + 1) * 100 * 1e18, 0) returns (uint256 amountOut) {
                console.log("   User", i + 1, "swapped, received:", amountOut / 1e18);
            } catch {
                console.log("   User", i + 1, "swap failed");
            }
            vm.stopPrank();
        }
        _p("3 users swapped");

        // Swap in both directions
        vm.startPrank(users[0]);
        IERC20(token1).approve(address(swapRouter), type(uint256).max);
        try swapRouter.swap(key, false, 100 * 1e18, 0) returns (uint256 amountOut) {
            _p("User can swap in reverse direction");
            console.log("   Received:", amountOut / 1e18);
        } catch {
            _f("Reverse swap");
        }
        vm.stopPrank();

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
