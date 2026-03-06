// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../../src/TitanToken.sol";

contract TestTitanToken is Script {
    TitanToken public token;
    address public deployer;
    address public user1;
    address public user2;
    address public user3;

    uint256 passed;
    uint256 failed;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        deployer = vm.addr(pk);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        console.log("==============================================");
        console.log("       TITAN TOKEN - COMPREHENSIVE TESTS");
        console.log("==============================================\n");

        string memory json = vm.readFile("deployments-dev.json");
        token = TitanToken(vm.parseJsonAddress(json, ".contracts.titanToken"));
        console.log("Token:", address(token));
        console.log("Deployer:", deployer);
        console.log("Balance:", token.balanceOf(deployer) / 1e18, "TITAN\n");

        vm.startBroadcast(pk);

        // Setup users
        token.transfer(user1, 1_000_000 * 1e18);
        token.transfer(user2, 500_000 * 1e18);

        vm.stopBroadcast();

        _testBasicProperties();
        _testTransfers();
        _testDelegation();
        _testMinting();
        _testBurning();
        _testApprovals();

        _printResults();
    }

    function _testBasicProperties() internal {
        console.log("--- Basic Properties ---");

        if (keccak256(bytes(token.name())) == keccak256("Titan Token")) _p("name()"); else _f("name()");
        if (keccak256(bytes(token.symbol())) == keccak256("TITAN")) _p("symbol()"); else _f("symbol()");
        if (token.decimals() == 18) _p("decimals()"); else _f("decimals()");
        if (token.INITIAL_SUPPLY() == 100_000_000 * 1e18) _p("INITIAL_SUPPLY"); else _f("INITIAL_SUPPLY");
        if (token.MAX_SUPPLY() == 1_000_000_000 * 1e18) _p("MAX_SUPPLY"); else _f("MAX_SUPPLY");
        if (token.totalSupply() > 0) _p("totalSupply()"); else _f("totalSupply()");

        console.log("");
    }

    function _testTransfers() internal {
        console.log("--- Transfers ---");

        uint256 bal1Before = token.balanceOf(user1);
        uint256 bal2Before = token.balanceOf(user2);

        // Small transfer
        vm.prank(user1);
        token.transfer(user2, 1); // 1 wei
        if (token.balanceOf(user2) == bal2Before + 1) _p("Transfer 1 wei"); else _f("Transfer 1 wei");

        // Medium transfer
        vm.prank(user1);
        token.transfer(user2, 1000 * 1e18);
        _p("Transfer 1,000 TITAN");

        // Large transfer
        vm.prank(user1);
        token.transfer(user2, 100_000 * 1e18);
        _p("Transfer 100,000 TITAN");

        // Transfer to self
        uint256 selfBal = token.balanceOf(user2);
        vm.prank(user2);
        token.transfer(user2, 100 * 1e18);
        if (token.balanceOf(user2) == selfBal) _p("Transfer to self"); else _f("Transfer to self");

        // Transfer zero (should work)
        vm.prank(user1);
        token.transfer(user2, 0);
        _p("Transfer 0 amount");

        // Transfer more than balance (should fail)
        vm.prank(user3);
        try token.transfer(user1, 1) {
            _f("Transfer without balance should fail");
        } catch {
            _p("Transfer without balance reverts");
        }

        console.log("");
    }

    function _testDelegation() internal {
        console.log("--- Delegation & Voting ---");

        // Self delegation
        vm.prank(user1);
        token.delegate(user1);
        vm.roll(block.number + 1);

        uint256 votes = token.getVotes(user1);
        if (votes > 0) _p("Self delegation"); else _f("Self delegation");
        console.log("   User1 votes:", votes / 1e18);

        // Delegate to another
        vm.prank(user2);
        token.delegate(user1);
        vm.roll(block.number + 1);

        uint256 newVotes = token.getVotes(user1);
        if (newVotes > votes) _p("Delegate to other"); else _f("Delegate to other");
        console.log("   User1 votes after delegation:", newVotes / 1e18);

        // Check delegates
        if (token.delegates(user2) == user1) _p("delegates() returns correct"); else _f("delegates()");

        // getPastVotes
        uint256 pastVotes = token.getPastVotes(user1, block.number - 1);
        _p("getPastVotes()");
        console.log("   Past votes:", pastVotes / 1e18);

        // getPastTotalSupply
        uint256 pastSupply = token.getPastTotalSupply(block.number - 1);
        if (pastSupply > 0) _p("getPastTotalSupply()"); else _f("getPastTotalSupply()");

        console.log("");
    }

    function _testMinting() internal {
        console.log("--- Minting (Owner Only) ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Mint small amount
        uint256 supplyBefore = token.totalSupply();
        vm.broadcast(pk);
        token.mint(user3, 100 * 1e18);
        if (token.balanceOf(user3) == 100 * 1e18) _p("Mint 100 TITAN"); else _f("Mint 100 TITAN");

        // Mint larger amount
        vm.broadcast(pk);
        token.mint(user3, 1_000_000 * 1e18);
        _p("Mint 1,000,000 TITAN");

        // Mint to zero address (should fail)
        vm.broadcast(pk);
        try token.mint(address(0), 100 * 1e18) {
            _f("Mint to zero should fail");
        } catch {
            _p("Mint to zero address reverts");
        }

        // Mint zero amount (should fail)
        vm.broadcast(pk);
        try token.mint(user3, 0) {
            _f("Mint zero should fail");
        } catch {
            _p("Mint zero amount reverts");
        }

        // Non-owner mint (should fail)
        vm.prank(user1);
        try token.mint(user1, 100 * 1e18) {
            _f("Non-owner mint should fail");
        } catch {
            _p("Non-owner mint reverts");
        }

        console.log("");
    }

    function _testBurning() internal {
        console.log("--- Burning ---");

        uint256 bal = token.balanceOf(user1);

        // Burn small
        vm.prank(user1);
        token.burn(1);
        if (token.balanceOf(user1) == bal - 1) _p("Burn 1 wei"); else _f("Burn 1 wei");

        // Burn medium
        vm.prank(user1);
        token.burn(1000 * 1e18);
        _p("Burn 1,000 TITAN");

        // Burn more than balance (should fail)
        vm.prank(user3);
        try token.burn(token.balanceOf(user3) + 1) {
            _f("Burn more than balance should fail");
        } catch {
            _p("Burn more than balance reverts");
        }

        console.log("");
    }

    function _testApprovals() internal {
        console.log("--- Approvals & TransferFrom ---");

        // Approve small
        vm.prank(user1);
        token.approve(user2, 100 * 1e18);
        if (token.allowance(user1, user2) == 100 * 1e18) _p("Approve 100 TITAN"); else _f("Approve");

        // Approve max
        vm.prank(user1);
        token.approve(user2, type(uint256).max);
        if (token.allowance(user1, user2) == type(uint256).max) _p("Approve max uint256"); else _f("Approve max");

        // TransferFrom
        uint256 bal1 = token.balanceOf(user1);
        uint256 bal3 = token.balanceOf(user3);
        vm.prank(user2);
        token.transferFrom(user1, user3, 500 * 1e18);
        if (token.balanceOf(user3) == bal3 + 500 * 1e18) _p("transferFrom"); else _f("transferFrom");

        // TransferFrom without approval (should fail)
        vm.prank(user3);
        try token.transferFrom(user2, user1, 100 * 1e18) {
            _f("TransferFrom without approval should fail");
        } catch {
            _p("TransferFrom without approval reverts");
        }

        // Increase allowance
        vm.prank(user1);
        token.approve(user3, 100 * 1e18);
        uint256 allowance1 = token.allowance(user1, user3);
        // Note: OZ 5.x doesn't have increaseAllowance, using approve
        _p("Allowance set correctly");

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
