// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TitanToken.sol";

contract TitanTokenTest is Test {
    TitanToken public token;
    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    event TokensMinted(address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.prank(owner);
        token = new TitanToken(owner);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectName() public view {
        assertEq(token.name(), "Titan Token");
    }

    function test_Constructor_SetsCorrectSymbol() public view {
        assertEq(token.symbol(), "TITAN");
    }

    function test_Constructor_SetsCorrectDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_Constructor_SetsCorrectOwner() public view {
        assertEq(token.owner(), owner);
    }

    function test_Constructor_MintsInitialSupplyToOwner() public view {
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function test_Constructor_SetsCorrectTotalSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_Constructor_InitialSupplyConstant() public view {
        assertEq(token.INITIAL_SUPPLY(), INITIAL_SUPPLY);
    }

    function test_Constructor_MaxSupplyConstant() public view {
        assertEq(token.MAX_SUPPLY(), MAX_SUPPLY);
    }

    // ============ Mint Tests ============

    function test_Mint_OwnerCanMint() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function test_Mint_EmitsTokensMintedEvent() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user1, mintAmount);

        vm.prank(owner);
        token.mint(user1, mintAmount);
    }

    function test_Mint_RevertsIfNotOwner() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        token.mint(user1, mintAmount);
    }

    function test_Mint_RevertsIfZeroAddress() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        vm.expectRevert(TitanToken.MintToZeroAddress.selector);
        token.mint(address(0), mintAmount);
    }

    function test_Mint_RevertsIfZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(TitanToken.MintAmountZero.selector);
        token.mint(user1, 0);
    }

    function test_Mint_RevertsIfExceedsMaxSupply() public {
        uint256 mintAmount = MAX_SUPPLY; // This exceeds when added to initial supply

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                TitanToken.MaxSupplyExceeded.selector,
                mintAmount,
                MAX_SUPPLY - INITIAL_SUPPLY
            )
        );
        token.mint(user1, mintAmount);
    }

    function test_Mint_CanMintUpToMaxSupply() public {
        uint256 mintAmount = MAX_SUPPLY - INITIAL_SUPPLY;

        vm.prank(owner);
        token.mint(user1, mintAmount);

        assertEq(token.totalSupply(), MAX_SUPPLY);
        assertEq(token.balanceOf(user1), mintAmount);
    }

    function testFuzz_Mint_VariousAmounts(uint256 amount) public {
        uint256 maxMintable = MAX_SUPPLY - INITIAL_SUPPLY;
        vm.assume(amount > 0 && amount <= maxMintable);

        vm.prank(owner);
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
    }

    // ============ Burn Tests ============

    function test_Burn_UserCanBurnOwnTokens() public {
        uint256 burnAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(user1, burnAmount);

        vm.prank(user1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }

    function test_Burn_RevertsIfInsufficientBalance() public {
        uint256 burnAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        vm.expectRevert();
        token.burn(burnAmount);
    }

    function test_BurnFrom_WithAllowance() public {
        uint256 burnAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(user1, burnAmount);

        vm.prank(user1);
        token.approve(user2, burnAmount);

        vm.prank(user2);
        token.burnFrom(user1, burnAmount);

        assertEq(token.balanceOf(user1), 0);
    }

    // ============ Transfer Tests ============

    function test_Transfer_BasicTransfer() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(user1, transferAmount);

        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - transferAmount);
    }

    function test_Transfer_EmitsTransferEvent() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, transferAmount);

        vm.prank(owner);
        token.transfer(user1, transferAmount);
    }

    // ============ ERC20Votes Tests ============

    function test_Delegate_DelegatesToSelf() public {
        vm.prank(owner);
        token.transfer(user1, 1000 * 10 ** 18);

        vm.prank(user1);
        token.delegate(user1);

        assertEq(token.getVotes(user1), 1000 * 10 ** 18);
        assertEq(token.delegates(user1), user1);
    }

    function test_Delegate_DelegatesToOther() public {
        vm.prank(owner);
        token.transfer(user1, 1000 * 10 ** 18);

        vm.prank(user1);
        token.delegate(user2);

        assertEq(token.getVotes(user1), 0);
        assertEq(token.getVotes(user2), 1000 * 10 ** 18);
        assertEq(token.delegates(user1), user2);
    }

    function test_Delegate_EmitsEvent() public {
        vm.expectEmit(true, true, true, false);
        emit DelegateChanged(user1, address(0), user1);

        vm.prank(user1);
        token.delegate(user1);
    }

    function test_GetPastVotes_ReturnsHistoricalVotes() public {
        vm.prank(owner);
        token.transfer(user1, 1000 * 10 ** 18);

        vm.prank(user1);
        token.delegate(user1);

        // Roll forward first, then query previous block
        vm.roll(block.number + 1);

        // Query the block before current (where checkpoint was created)
        assertEq(token.getPastVotes(user1, block.number - 1), 1000 * 10 ** 18);
    }

    function test_GetPastTotalSupply_ReturnsHistoricalSupply() public {
        // Roll forward first
        vm.roll(block.number + 1);

        // Query total supply at the previous block
        assertEq(token.getPastTotalSupply(block.number - 1), INITIAL_SUPPLY);
    }

    function test_Transfer_UpdatesVotingPower() public {
        vm.startPrank(owner);
        token.delegate(owner);
        uint256 votesBefore = token.getVotes(owner);
        token.transfer(user1, 1000 * 10 ** 18);
        vm.stopPrank();

        assertEq(token.getVotes(owner), votesBefore - 1000 * 10 ** 18);
    }

    // ============ Clock Tests ============

    function test_Clock_ReturnsBlockNumber() public view {
        assertEq(token.clock(), uint48(block.number));
    }

    function test_ClockMode_ReturnsCorrectMode() public view {
        assertEq(token.CLOCK_MODE(), "mode=blocknumber&from=default");
    }

    // ============ Approve and TransferFrom Tests ============

    function test_Approve_SetsAllowance() public {
        uint256 allowanceAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.approve(user1, allowanceAmount);

        assertEq(token.allowance(owner, user1), allowanceAmount);
    }

    function test_TransferFrom_WithApproval() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.approve(user1, transferAmount);

        vm.prank(user1);
        token.transferFrom(owner, user2, transferAmount);

        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.allowance(owner, user1), 0);
    }

    // ============ Permit Tests ============

    function test_Permit_AllowsGaslessApproval() public {
        uint256 privateKey = 0x1234567890abcdef;
        address signer = vm.addr(privateKey);

        vm.prank(owner);
        token.transfer(signer, 1000 * 10 ** 18);

        uint256 nonce = token.nonces(signer);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = 500 * 10 ** 18;

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                user1,
                amount,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        token.permit(signer, user1, amount, deadline, v, r, s);

        assertEq(token.allowance(signer, user1), amount);
    }

    // ============ Ownership Tests ============

    function test_TransferOwnership() public {
        vm.prank(owner);
        token.transferOwnership(user1);

        assertEq(token.owner(), user1);
    }

    function test_RenounceOwnership() public {
        vm.prank(owner);
        token.renounceOwnership();

        assertEq(token.owner(), address(0));
    }

    // ============ Edge Cases ============

    function test_Transfer_ZeroAmount() public {
        vm.prank(owner);
        token.transfer(user1, 0);

        assertEq(token.balanceOf(user1), 0);
    }

    function test_SelfTransfer() public {
        uint256 initialBalance = token.balanceOf(owner);

        vm.prank(owner);
        token.transfer(owner, 1000 * 10 ** 18);

        assertEq(token.balanceOf(owner), initialBalance);
    }

    function testFuzz_Transfer_VariousAmounts(uint256 amount) public {
        vm.assume(amount <= INITIAL_SUPPLY);

        vm.prank(owner);
        token.transfer(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }
}
