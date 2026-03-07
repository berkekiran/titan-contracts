// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LiquidityRouter.sol";
import "../src/interfaces/IPoolManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 Token
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock PoolManager for testing
contract MockPoolManager is IPoolManager {
    address public liquidityRouter;
    bool public shouldRevert;
    int24 public mockTick = 100;
    int256 public mockCallerDelta;
    int256 public mockFeesAccrued;

    mapping(bytes32 => bool) public initializedPools;

    function setLiquidityRouter(address _router) external {
        liquidityRouter = _router;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setMockCallerDelta(int256 _delta) external {
        mockCallerDelta = _delta;
    }

    function unlock(bytes calldata data) external override returns (bytes memory) {
        if (shouldRevert) revert("MockPoolManager: unlock reverted");
        // Call back to the router
        return LiquidityRouter(payable(liquidityRouter)).unlockCallback(data);
    }

    function swap(PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        override
        returns (int256)
    {
        // Return a mock balance delta
        // Positive = caller receives, negative = caller owes
        return int256(uint256(100e18)) << 128 | int256(-int256(uint256(100e18)));
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

    function initialize(PoolKey memory key, uint160) external override returns (int24 tick) {
        bytes32 poolId = keccak256(abi.encode(key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks));
        initializedPools[poolId] = true;
        return mockTick;
    }

    function modifyLiquidity(
        PoolKey memory,
        ModifyLiquidityParams memory params,
        bytes calldata
    ) external view override returns (int256 callerDelta, int256 feesAccrued) {
        // If adding liquidity (positive delta), return negative caller delta (caller owes)
        // If removing liquidity (negative delta), return positive caller delta (caller receives)
        if (params.liquidityDelta > 0) {
            // Adding liquidity - caller owes tokens
            // Pack two int128 into int256: delta0 in upper 128 bits, delta1 in lower 128 bits
            int128 delta0 = -int128(int256(params.liquidityDelta / 100)); // Small amounts for testing
            int128 delta1 = -int128(int256(params.liquidityDelta / 100));
            callerDelta = (int256(delta0) << 128) | int256(uint256(uint128(delta1)));
        } else {
            // Removing liquidity - caller receives tokens
            int128 delta0 = int128(-params.liquidityDelta / 100);
            int128 delta1 = int128(-params.liquidityDelta / 100);
            callerDelta = (int256(delta0) << 128) | int256(uint256(uint128(delta1)));
        }
        feesAccrued = mockFeesAccrued;
    }

    receive() external payable {}
}

contract LiquidityRouterTest is Test {
    LiquidityRouter public router;
    MockPoolManager public poolManager;
    MockToken public token0;
    MockToken public token1;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_BALANCE = 100_000 * 10 ** 18;

    event PoolInitialized(address indexed token0, address indexed token1, uint24 fee, int24 tick);
    event LiquidityAdded(
        address indexed provider,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity
    );
    event LiquidityRemoved(
        address indexed provider,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity
    );

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);

        // Deploy mock tokens (ensure token0 < token1)
        token0 = new MockToken("Token0", "TK0");
        token1 = new MockToken("Token1", "TK1");

        // Ensure token0 address < token1 address
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Deploy mock pool manager
        poolManager = new MockPoolManager();

        // Deploy router
        router = new LiquidityRouter(address(poolManager), owner);

        // Set router in pool manager for callbacks
        poolManager.setLiquidityRouter(address(router));

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
        vm.expectRevert(LiquidityRouter.InvalidPoolManager.selector);
        new LiquidityRouter(address(0), owner);
    }

    // ============ Initialize Pool Tests ============

    function test_InitializePool_CreatesPool() public {
        int24 tick = router.initializePool(
            address(token0),
            address(token1),
            3000,
            60,
            0 // Default price
        );

        assertEq(tick, 100); // Mock returns 100
    }

    function test_InitializePool_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit PoolInitialized(address(token0), address(token1), 3000, 100);

        router.initializePool(address(token0), address(token1), 3000, 60, 0);
    }

    function test_InitializePool_WithCustomPrice() public {
        uint160 customPrice = 79228162514264337593543950336; // 1:1 price

        int24 tick = router.initializePool(
            address(token0),
            address(token1),
            3000,
            60,
            customPrice
        );

        assertEq(tick, 100);
    }

    // ============ Add Liquidity Tests ============

    function test_AddLiquidity_AddsPosition() public {
        LiquidityRouter.AddLiquidityParams memory params = LiquidityRouter.AddLiquidityParams({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 1000 * 10 ** 18,
            amount1Desired: 1000 * 10 ** 18,
            recipient: user1
        });

        vm.prank(user1);
        uint128 liquidity = router.addLiquidity(params);

        assertGt(liquidity, 0);
    }

    function test_AddLiquidity_StoresPosition() public {
        LiquidityRouter.AddLiquidityParams memory params = LiquidityRouter.AddLiquidityParams({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 1000 * 10 ** 18,
            amount1Desired: 1000 * 10 ** 18,
            recipient: user1
        });

        vm.prank(user1);
        uint128 liquidityAdded = router.addLiquidity(params);

        uint128 position = router.getPosition(
            user1,
            address(token0),
            address(token1),
            3000,
            60,
            -120,
            120
        );

        assertEq(position, liquidityAdded);
    }

    function test_AddLiquidity_RevertsIfZeroAmounts() public {
        LiquidityRouter.AddLiquidityParams memory params = LiquidityRouter.AddLiquidityParams({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 0,
            amount1Desired: 0,
            recipient: user1
        });

        vm.prank(user1);
        vm.expectRevert(LiquidityRouter.InvalidAmounts.selector);
        router.addLiquidity(params);
    }

    // ============ Remove Liquidity Tests ============

    function test_RemoveLiquidity_RemovesPosition() public {
        // First add liquidity
        LiquidityRouter.AddLiquidityParams memory addParams = LiquidityRouter.AddLiquidityParams({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 1000 * 10 ** 18,
            amount1Desired: 1000 * 10 ** 18,
            recipient: user1
        });

        vm.prank(user1);
        uint128 liquidityAdded = router.addLiquidity(addParams);

        // Then remove liquidity
        LiquidityRouter.RemoveLiquidityParams memory removeParams = LiquidityRouter.RemoveLiquidityParams({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            liquidity: liquidityAdded,
            recipient: user1
        });

        vm.prank(user1);
        (uint256 amount0, uint256 amount1) = router.removeLiquidity(removeParams);

        assertGe(amount0, 0);
        assertGe(amount1, 0);

        uint128 remainingPosition = router.getPosition(
            user1,
            address(token0),
            address(token1),
            3000,
            60,
            -120,
            120
        );

        assertEq(remainingPosition, 0);
    }

    function test_RemoveLiquidity_RevertsIfInsufficientLiquidity() public {
        LiquidityRouter.RemoveLiquidityParams memory params = LiquidityRouter.RemoveLiquidityParams({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            liquidity: 1000,
            recipient: user1
        });

        vm.prank(user1);
        vm.expectRevert(LiquidityRouter.InsufficientLiquidity.selector);
        router.removeLiquidity(params);
    }

    // ============ Callback Tests ============

    function test_UnlockCallback_RevertsIfNotPoolManager() public {
        vm.prank(user1);
        vm.expectRevert(LiquidityRouter.OnlyPoolManager.selector);
        router.unlockCallback("");
    }

    // ============ Sweep Tests ============

    function test_SweepToken_TransfersTokens() public {
        // Send some tokens to router
        vm.prank(owner);
        token0.transfer(address(router), 100 * 10 ** 18);

        uint256 balanceBefore = token0.balanceOf(owner);

        vm.prank(owner);
        router.sweepToken(address(token0), owner, 0); // 0 = full balance

        assertEq(token0.balanceOf(owner), balanceBefore + 100 * 10 ** 18);
    }

    function test_SweepToken_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        router.sweepToken(address(token0), user1, 100);
    }

    function test_SweepToken_RevertsIfInvalidRecipient() public {
        vm.prank(owner);
        vm.expectRevert(LiquidityRouter.InvalidRecipient.selector);
        router.sweepToken(address(token0), address(0), 100);
    }

    function test_SweepEth_TransfersEth() public {
        // Send ETH to router
        vm.deal(address(router), 1 ether);

        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        router.sweepEth(payable(owner), 0); // 0 = full balance

        assertEq(owner.balance, balanceBefore + 1 ether);
    }

    function test_SweepEth_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        router.sweepEth(payable(user1), 100);
    }

    function test_SweepEth_RevertsIfInvalidRecipient() public {
        vm.prank(owner);
        vm.expectRevert(LiquidityRouter.InvalidRecipient.selector);
        router.sweepEth(payable(address(0)), 100);
    }

    // ============ Receive Tests ============

    function test_Receive_AcceptsEth() public {
        vm.deal(user1, 1 ether);

        vm.prank(user1);
        (bool success, ) = address(router).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(router).balance, 1 ether);
    }

    // ============ GetPosition Tests ============

    function test_GetPosition_ReturnsZeroForNoPosition() public view {
        uint128 position = router.getPosition(
            user1,
            address(token0),
            address(token1),
            3000,
            60,
            -120,
            120
        );

        assertEq(position, 0);
    }

    // ============ Native ETH Tests ============

    function test_AddLiquidity_WithNativeETH_Token0() public {
        // Token0 = native ETH (address(0)), token1 = token
        // Ensure address(0) < address(token1)
        address nativeEth = address(0);

        // Fund user with ETH
        vm.deal(user1, 10 ether);

        LiquidityRouter.AddLiquidityParams memory params = LiquidityRouter.AddLiquidityParams({
            token0: nativeEth,
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 1 ether,
            amount1Desired: 1000 * 10 ** 18,
            recipient: user1
        });

        vm.prank(user1);
        uint128 liquidity = router.addLiquidity{value: 1 ether}(params);

        assertGt(liquidity, 0);
    }

    function test_AddLiquidity_WithAmount1Greater() public {
        LiquidityRouter.AddLiquidityParams memory params = LiquidityRouter.AddLiquidityParams({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            tickSpacing: 60,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 500 * 10 ** 18,
            amount1Desired: 1000 * 10 ** 18, // amount1 > amount0
            recipient: user1
        });

        vm.prank(user1);
        uint128 liquidity = router.addLiquidity(params);

        assertGt(liquidity, 0);
    }

    function test_SweepToken_PartialAmount() public {
        // Send some tokens to router
        vm.prank(owner);
        token0.transfer(address(router), 100 * 10 ** 18);

        uint256 balanceBefore = token0.balanceOf(owner);

        vm.prank(owner);
        router.sweepToken(address(token0), owner, 50 * 10 ** 18);

        assertEq(token0.balanceOf(owner), balanceBefore + 50 * 10 ** 18);
    }

    function test_SweepEth_PartialAmount() public {
        vm.deal(address(router), 1 ether);

        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        router.sweepEth(payable(owner), 0.5 ether);

        assertEq(owner.balance, balanceBefore + 0.5 ether);
    }
}
