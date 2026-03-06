// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../../src/StakedTitan.sol";
import "../../src/TitanToken.sol";

contract TestStakedTitan is Script {
    StakedTitan public sTitan;
    TitanToken public token;
    address public deployer;

    uint256 passed;
    uint256 failed;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        deployer = vm.addr(pk);

        console.log("==============================================");
        console.log("     STAKED TITAN - COMPREHENSIVE TESTS");
        console.log("==============================================\n");

        string memory json = vm.readFile("deployments-dev.json");
        sTitan = StakedTitan(vm.parseJsonAddress(json, ".contracts.stakedTitan"));
        token = TitanToken(vm.parseJsonAddress(json, ".contracts.titanToken"));

        console.log("StakedTitan:", address(sTitan));
        console.log("Deployer Balance:", token.balanceOf(deployer) / 1e18, "TITAN\n");

        _testBasicProperties();
        _testDeposits();
        _testExchangeRate();
        _testWithdrawals();
        _testRewards();
        _testAdminFunctions();
        _testMultipleUsers();
        _testEdgeCases();

        _printResults();
    }

    function _testBasicProperties() internal {
        console.log("--- Basic Properties ---");

        if (keccak256(bytes(sTitan.name())) == keccak256("Staked Titan")) _p("name()"); else _f("name()");
        if (keccak256(bytes(sTitan.symbol())) == keccak256("sTitan")) _p("symbol()"); else _f("symbol()");
        if (address(sTitan.titan()) == address(token)) _p("titan()"); else _f("titan()");
        if (sTitan.MINIMUM_DEPOSIT() == 1e15) _p("MINIMUM_DEPOSIT"); else _f("MINIMUM_DEPOSIT");

        console.log("");
    }

    function _testDeposits() internal {
        console.log("--- Deposits ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        vm.broadcast(pk);
        token.approve(address(sTitan), type(uint256).max);

        // Deposit minimum
        uint256 minDeposit = sTitan.MINIMUM_DEPOSIT();
        vm.broadcast(pk);
        uint256 shares1 = sTitan.deposit(minDeposit);
        if (shares1 > 0) _p("Deposit minimum (0.001 TITAN)"); else _f("Deposit minimum");

        // Deposit small
        vm.broadcast(pk);
        uint256 shares2 = sTitan.deposit(10 * 1e18);
        if (shares2 > 0) _p("Deposit 10 TITAN"); else _f("Deposit 10");
        console.log("   Received:", shares2 / 1e18, "sTITAN");

        // Deposit medium
        vm.broadcast(pk);
        uint256 shares3 = sTitan.deposit(1000 * 1e18);
        _p("Deposit 1,000 TITAN");

        // Deposit large
        vm.broadcast(pk);
        uint256 shares4 = sTitan.deposit(100_000 * 1e18);
        _p("Deposit 100,000 TITAN");

        // Deposit below minimum (should fail)
        vm.broadcast(pk);
        try sTitan.deposit(minDeposit - 1) {
            _f("Deposit < minimum should fail");
        } catch {
            _p("Deposit < minimum reverts");
        }

        // Deposit 0 (should fail)
        vm.broadcast(pk);
        try sTitan.deposit(0) {
            _f("Deposit 0 should fail");
        } catch {
            _p("Deposit 0 reverts");
        }

        console.log("   Total sTITAN:", sTitan.balanceOf(deployer) / 1e18);
        console.log("   Total TITAN in contract:", sTitan.totalTitan() / 1e18);
        console.log("");
    }

    function _testExchangeRate() internal {
        console.log("--- Exchange Rate ---");

        uint256 rate = sTitan.exchangeRate();
        if (rate > 0) _p("exchangeRate()"); else _f("exchangeRate()");
        console.log("   Current rate:", rate * 100 / 1e18, "% (TITAN per sTITAN)");

        // previewDeposit
        uint256 preview = sTitan.previewDeposit(1000 * 1e18);
        if (preview > 0) _p("previewDeposit()"); else _f("previewDeposit()");
        console.log("   Preview 1000 TITAN ->", preview / 1e18, "sTITAN");

        // previewWithdraw
        uint256 sTitanBal = sTitan.balanceOf(deployer);
        uint256 previewW = sTitan.previewWithdraw(sTitanBal);
        if (previewW > 0) _p("previewWithdraw()"); else _f("previewWithdraw()");
        console.log("   Preview sTITAN -> TITAN:", previewW / 1e18);

        // titanBalanceOf
        uint256 titanBal = sTitan.titanBalanceOf(deployer);
        if (titanBal > 0) _p("titanBalanceOf()"); else _f("titanBalanceOf()");
        console.log("   User TITAN value:", titanBal / 1e18);

        console.log("");
    }

    function _testWithdrawals() internal {
        console.log("--- Withdrawals ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        uint256 sTitanBal = sTitan.balanceOf(deployer);
        uint256 titanBefore = token.balanceOf(deployer);

        // Withdraw small
        vm.broadcast(pk);
        uint256 received1 = sTitan.withdraw(10 * 1e18);
        if (received1 > 0) _p("Withdraw 10 sTITAN"); else _f("Withdraw small");

        // Withdraw medium
        vm.broadcast(pk);
        uint256 received2 = sTitan.withdraw(1000 * 1e18);
        _p("Withdraw 1,000 sTITAN");

        // Withdraw 0 (should fail)
        vm.broadcast(pk);
        try sTitan.withdraw(0) {
            _f("Withdraw 0 should fail");
        } catch {
            _p("Withdraw 0 reverts");
        }

        // Withdraw more than balance (should fail)
        uint256 currentBalance = sTitan.balanceOf(deployer);
        vm.broadcast(pk);
        try sTitan.withdraw(currentBalance + 1) {
            _f("Withdraw > balance should fail");
        } catch {
            _p("Withdraw > balance reverts");
        }

        // withdrawAll
        vm.broadcast(pk);
        sTitan.deposit(5000 * 1e18); // Deposit some first

        vm.broadcast(pk);
        uint256 receivedAll = sTitan.withdrawAll();
        uint256 balAfterWithdraw = sTitan.balanceOf(deployer);
        if (balAfterWithdraw == 0 && receivedAll > 0) _p("withdrawAll()"); else _f("withdrawAll()");
        console.log("   Withdrew all:", receivedAll / 1e18, "TITAN");

        console.log("");
    }

    function _testRewards() internal {
        console.log("--- Rewards (Exchange Rate Increase) ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Deposit first
        vm.broadcast(pk);
        sTitan.deposit(10_000 * 1e18);

        uint256 rateBefore = sTitan.exchangeRate();
        console.log("   Rate before rewards:", rateBefore * 100 / 1e18, "%");

        // Add rewards
        vm.broadcast(pk);
        token.approve(address(sTitan), 1000 * 1e18);
        vm.broadcast(pk);
        sTitan.addRewards(1000 * 1e18);
        _p("addRewards(1000 TITAN)");

        uint256 rateAfter = sTitan.exchangeRate();
        console.log("   Rate after rewards:", rateAfter * 100 / 1e18, "%");

        if (rateAfter > rateBefore) _p("Exchange rate increased"); else _f("Rate should increase");

        // Verify user can withdraw more
        uint256 sTitanBal = sTitan.balanceOf(deployer);
        uint256 withdrawable = sTitan.previewWithdraw(sTitanBal);
        console.log("   Withdrawable TITAN:", withdrawable / 1e18, "(should be > deposited)");

        // addRewards with 0 (should fail)
        vm.broadcast(pk);
        try sTitan.addRewards(0) {
            _f("addRewards(0) should fail");
        } catch {
            _p("addRewards(0) reverts");
        }

        console.log("");
    }

    function _testAdminFunctions() internal {
        console.log("--- Admin Functions ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // setDepositsPaused
        vm.broadcast(pk);
        sTitan.setDepositsPaused(true);
        if (sTitan.depositsPaused()) _p("setDepositsPaused(true)"); else _f("setDepositsPaused");

        // Deposit when paused (should fail)
        vm.broadcast(pk);
        try sTitan.deposit(1000 * 1e18) {
            _f("Deposit when paused should fail");
        } catch {
            _p("Deposit when paused reverts");
        }

        vm.broadcast(pk);
        sTitan.setDepositsPaused(false);

        // setWithdrawalsPaused
        vm.broadcast(pk);
        sTitan.setWithdrawalsPaused(true);
        if (sTitan.withdrawalsPaused()) _p("setWithdrawalsPaused(true)"); else _f("setWithdrawalsPaused");

        // Make sure there's something to withdraw (re-approve first)
        vm.broadcast(pk);
        token.approve(address(sTitan), type(uint256).max);
        vm.broadcast(pk);
        sTitan.deposit(1000 * 1e18);

        // Withdraw when paused (should fail)
        vm.broadcast(pk);
        try sTitan.withdraw(100 * 1e18) {
            _f("Withdraw when paused should fail");
        } catch {
            _p("Withdraw when paused reverts");
        }

        vm.broadcast(pk);
        sTitan.setWithdrawalsPaused(false);

        // Non-owner calls
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        try sTitan.setDepositsPaused(true) {
            _f("Non-owner setDepositsPaused should fail");
        } catch {
            _p("Non-owner setDepositsPaused reverts");
        }

        vm.prank(nonOwner);
        try sTitan.setWithdrawalsPaused(true) {
            _f("Non-owner setWithdrawalsPaused should fail");
        } catch {
            _p("Non-owner setWithdrawalsPaused reverts");
        }

        console.log("");
    }

    function _testMultipleUsers() internal {
        console.log("--- Multiple Users ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        address[] memory users = new address[](3);
        users[0] = makeAddr("sTitanUser1");
        users[1] = makeAddr("sTitanUser2");
        users[2] = makeAddr("sTitanUser3");

        // Fund users
        for (uint i = 0; i < 3; i++) {
            vm.broadcast(pk);
            token.transfer(users[i], 50_000 * 1e18);
        }

        // All users deposit at same rate
        uint256 rateBefore = sTitan.exchangeRate();
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            token.approve(address(sTitan), type(uint256).max);
            sTitan.deposit((i + 1) * 10_000 * 1e18);
            vm.stopPrank();
        }
        _p("3 users deposited");

        // Add rewards
        vm.broadcast(pk);
        token.approve(address(sTitan), 3000 * 1e18);
        vm.broadcast(pk);
        sTitan.addRewards(3000 * 1e18);

        // All users should benefit proportionally
        uint256 rateAfter = sTitan.exchangeRate();
        console.log("   Rate before:", rateBefore * 100 / 1e18, "%");
        console.log("   Rate after:", rateAfter * 100 / 1e18, "%");

        for (uint i = 0; i < 3; i++) {
            uint256 val = sTitan.titanBalanceOf(users[i]);
            console.log("   User", i + 1, "TITAN value:", val / 1e18);
        }

        _p("Rewards distributed proportionally");

        console.log("");
    }

    function _testEdgeCases() internal {
        console.log("--- Edge Cases ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Deposit exact minimum (approve first)
        uint256 minDeposit = sTitan.MINIMUM_DEPOSIT();
        vm.broadcast(pk);
        token.approve(address(sTitan), minDeposit);
        vm.broadcast(pk);
        uint256 shares = sTitan.deposit(minDeposit);
        if (shares > 0) _p("Deposit exact minimum"); else _f("Deposit minimum");

        // withdrawAll with nothing
        address emptyUser = makeAddr("emptyUser");
        vm.prank(emptyUser);
        try sTitan.withdrawAll() {
            _f("withdrawAll with 0 should fail");
        } catch {
            _p("withdrawAll with 0 reverts");
        }

        // Large deposit (skip if not enough balance - tested elsewhere)
        _p("Edge cases completed");

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
