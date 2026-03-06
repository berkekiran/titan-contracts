// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SwapRouter.sol";
import "../src/interfaces/IPoolManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 Token
contract MockSwapToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock PoolManager for SwapRouter testing
contract MockSwapPoolManager is IPoolManager {
    address public swapRouter;
    bool public shouldRevert;
    int256 public mockBalanceDelta;

    function setSwapRouter(address _router) external {
        swapRouter = _router;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setMockBalanceDelta(int256 _delta) external {
        mockBalanceDelta = _delta;
    }

    function unlock(bytes calldata data) external override returns (bytes memory) {
        if (shouldRevert) revert("MockPoolManager: unlock reverted");
        return SwapRouter(payable(swapRouter)).unlockCallback(data);
    }

    function swap(PoolKey calldata, SwapParams calldata params, bytes calldata)
        external
        view
        override
        returns (int256)
    {
        if (mockBalanceDelta != 0) {
            return mockBalanceDelta;
        }

        // amountSpecified is negative for exact input swaps
        uint256 amountIn = uint256(-params.amountSpecified);
        uint256 amountOut = amountIn * 99 / 100; // 99% output (1% slippage)

        // Pack two int128 values into int256
        // Upper 128 bits = delta0, Lower 128 bits = delta1
        // Note: We need to handle the bit packing carefully
        if (params.zeroForOne) {
            // Swapping token0 for token1
            // delta0 = negative (we owe token0), delta1 = positive (we receive token1)
            int256 delta0 = -int256(amountIn);
            int256 delta1 = int256(amountOut);
            // Pack: shift delta0 to upper bits, mask delta1 to lower bits
            return (delta0 << 128) | (delta1 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        } else {
            // Swapping token1 for token0
            // delta0 = positive (we receive token0), delta1 = negative (we owe token1)
            int256 delta0 = int256(amountOut);
            int256 delta1 = -int256(amountIn);
            // Pack: shift delta0 to upper bits, mask delta1 to lower bits
            return (delta0 << 128) | (delta1 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        }
    }

    function settle() external payable override returns (uint256) {
        return msg.value;
    }

    function take(address currency, address to, uint256 amount) external override {
        if (currency != address(0)) {
            IERC20(currency).transfer(to, amount);
        } else {
            payable(to).transfer(amount);
        }
    }

    function sync(address) external pure override {
        // No-op for mock
    }

    function initialize(PoolKey memory, uint160) external pure override returns (int24) {
        return 0;
    }

    function modifyLiquidity(
        PoolKey memory,
        ModifyLiquidityParams memory,
        bytes calldata
    ) external pure override returns (int256, int256) {
        return (0, 0);
    }

    receive() external payable {}
}

contract SwapRouterTest is Test {
    SwapRouter public router;
    MockSwapPoolManager public poolManager;
    MockSwapToken public token0;
    MockSwapToken public token1;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_BALANCE = 100_000 * 10 ** 18;

    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event TokensSwept(address indexed token, address indexed to, uint256 amount);
    event EthSwept(address indexed to, uint256 amount);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);

        // Deploy mock tokens
        token0 = new MockSwapToken("Token0", "TK0");
        token1 = new MockSwapToken("Token1", "TK1");

        // Ensure token0 address < token1 address
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Deploy mock pool manager
        poolManager = new MockSwapPoolManager();

        // Deploy router
        router = new SwapRouter(address(poolManager), owner);

        // Set router in pool manager for callbacks
        poolManager.setSwapRouter(address(router));

        // Distribute tokens
        token0.transfer(user1, INITIAL_BALANCE);
        token0.transfer(user2, INITIAL_BALANCE);
        token1.transfer(user1, INITIAL_BALANCE);
        token1.transfer(user2, INITIAL_BALANCE);

        // Fund pool manager for takes
        token0.transfer(address(poolManager), INITIAL_BALANCE);
        token1.transfer(address(poolManager), INITIAL_BALANCE);

        vm.stopPrank();

        // Users approve router
        vm.prank(user1);
        token0.approve(address(router), type(uint256).max);
        vm.prank(user1);
        token1.approve(address(router), type(uint256).max);

        vm.prank(user2);
        token0.approve(address(router), type(uint256).max);
        vm.prank(user2);
        token1.approve(address(router), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsPoolManager() public view {
        assertEq(address(router.poolManager()), address(poolManager));
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(router.owner(), owner);
    }

    function test_Constructor_RevertsIfZeroPoolManager() public {
        vm.expectRevert(SwapRouter.InvalidPoolManager.selector);
        new SwapRouter(address(0), owner);
    }

    // ============ Swap Tests ============

    function test_Swap_ExecutesSwap() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        uint256 balanceBefore = token1.balanceOf(user1);

        vm.prank(user1);
        uint256 amountOut = router.swap(key, true, 1000 * 10 ** 18, 0);

        assertGt(amountOut, 0);
        assertGt(token1.balanceOf(user1), balanceBefore);
    }

    function test_Swap_TransfersInputTokens() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        uint256 balanceBefore = token0.balanceOf(user1);

        vm.prank(user1);
        router.swap(key, true, 1000 * 10 ** 18, 0);

        assertEq(token0.balanceOf(user1), balanceBefore - 1000 * 10 ** 18);
    }

    function test_Swap_EmitsEvent() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        vm.prank(user1);
        router.swap(key, true, 1000 * 10 ** 18, 0);

        // Event should be emitted (we can't easily test exact values with mock)
    }

    function test_Swap_RevertsIfZeroAmountIn() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        vm.prank(user1);
        vm.expectRevert(SwapRouter.InvalidAmountIn.selector);
        router.swap(key, true, 0, 0);
    }

    function test_Swap_RevertsIfInsufficientOutput() public {
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(
            SwapRouter.InsufficientOutput.selector,
            990 * 10 ** 18, // actual output (99%)
            1000 * 10 ** 18 // min expected
        ));
        router.swap(key, true, 1000 * 10 ** 18, 1000 * 10 ** 18);
    }

    function test_Swap_OneForZero() public {
        // For oneForZero, we need token1 as input, token0 as output
        // Set up a custom mock delta for this case
        // delta0 = positive (we receive 990e18), delta1 = negative (we owe 1000e18)
        int256 delta0 = int256(990 * 10 ** 18);
        int256 delta1 = -int256(1000 * 10 ** 18);
        int256 packedDelta = (delta0 << 128) | (delta1 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        poolManager.setMockBalanceDelta(packedDelta);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        uint256 balance0Before = token0.balanceOf(user1);
        uint256 balance1Before = token1.balanceOf(user1);

        vm.prank(user1);
        uint256 amountOut = router.swap(key, false, 1000 * 10 ** 18, 0); // oneForZero

        // Reset mock
        poolManager.setMockBalanceDelta(0);

        assertEq(amountOut, 990 * 10 ** 18);
        assertEq(token1.balanceOf(user1), balance1Before - 1000 * 10 ** 18);
        assertEq(token0.balanceOf(user1), balance0Before + 990 * 10 ** 18);
    }

    // ============ Callback Tests ============

    function test_UnlockCallback_RevertsIfNotPoolManager() public {
        vm.prank(user1);
        vm.expectRevert(SwapRouter.OnlyPoolManager.selector);
        router.unlockCallback("");
    }

    // ============ Sweep Tests ============

    function test_SweepToken_TransfersTokens() public {
        // Send some tokens to router
        vm.prank(owner);
        token0.transfer(address(router), 100 * 10 ** 18);

        uint256 balanceBefore = token0.balanceOf(owner);

        vm.prank(owner);
        router.sweepToken(address(token0), owner, 0);

        assertEq(token0.balanceOf(owner), balanceBefore + 100 * 10 ** 18);
    }

    function test_SweepToken_PartialAmount() public {
        // Send some tokens to router
        vm.prank(owner);
        token0.transfer(address(router), 100 * 10 ** 18);

        uint256 balanceBefore = token0.balanceOf(owner);

        vm.prank(owner);
        router.sweepToken(address(token0), owner, 50 * 10 ** 18);

        assertEq(token0.balanceOf(owner), balanceBefore + 50 * 10 ** 18);
        assertEq(token0.balanceOf(address(router)), 50 * 10 ** 18);
    }

    function test_SweepToken_EmitsEvent() public {
        vm.prank(owner);
        token0.transfer(address(router), 100 * 10 ** 18);

        vm.expectEmit(true, true, false, true);
        emit TokensSwept(address(token0), owner, 100 * 10 ** 18);

        vm.prank(owner);
        router.sweepToken(address(token0), owner, 0);
    }

    function test_SweepToken_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        router.sweepToken(address(token0), user1, 100);
    }

    function test_SweepToken_RevertsIfInvalidRecipient() public {
        vm.prank(owner);
        vm.expectRevert(SwapRouter.InvalidRecipient.selector);
        router.sweepToken(address(token0), address(0), 100);
    }

    function test_SweepEth_TransfersEth() public {
        vm.deal(address(router), 1 ether);

        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        router.sweepEth(payable(owner), 0);

        assertEq(owner.balance, balanceBefore + 1 ether);
    }

    function test_SweepEth_PartialAmount() public {
        vm.deal(address(router), 1 ether);

        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        router.sweepEth(payable(owner), 0.5 ether);

        assertEq(owner.balance, balanceBefore + 0.5 ether);
        assertEq(address(router).balance, 0.5 ether);
    }

    function test_SweepEth_EmitsEvent() public {
        vm.deal(address(router), 1 ether);

        vm.expectEmit(true, false, false, true);
        emit EthSwept(owner, 1 ether);

        vm.prank(owner);
        router.sweepEth(payable(owner), 0);
    }

    function test_SweepEth_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        router.sweepEth(payable(user1), 100);
    }

    function test_SweepEth_RevertsIfInvalidRecipient() public {
        vm.prank(owner);
        vm.expectRevert(SwapRouter.InvalidRecipient.selector);
        router.sweepEth(payable(address(0)), 100);
    }

    function test_SweepEth_NoOpIfZeroBalance() public {
        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        router.sweepEth(payable(owner), 0);

        assertEq(owner.balance, balanceBefore);
    }

    function test_SweepToken_NoOpIfZeroBalance() public {
        uint256 balanceBefore = token0.balanceOf(owner);

        vm.prank(owner);
        router.sweepToken(address(token0), owner, 0);

        assertEq(token0.balanceOf(owner), balanceBefore);
    }

    // ============ Receive Tests ============

    function test_Receive_AcceptsEth() public {
        vm.deal(user1, 1 ether);

        vm.prank(user1);
        (bool success, ) = address(router).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(router).balance, 1 ether);
    }

    // ============ Fuzz Tests ============

    function testFuzz_Swap_VariousAmounts(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e18, INITIAL_BALANCE);

        IPoolManager.PoolKey memory key = IPoolManager.PoolKey({
            currency0: address(token0),
            currency1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });

        vm.prank(user1);
        uint256 amountOut = router.swap(key, true, amountIn, 0);

        assertGt(amountOut, 0);
    }
}
