// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../../src/Faucet.sol";
import "../../src/TitanToken.sol";

contract TestFaucet is Script {
    Faucet public faucet;
    TitanToken public token;
    address public deployer;

    uint256 passed;
    uint256 failed;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        deployer = vm.addr(pk);

        console.log("==============================================");
        console.log("        FAUCET - COMPREHENSIVE TESTS");
        console.log("==============================================\n");

        string memory json = vm.readFile("deployments-dev.json");
        faucet = Faucet(vm.parseJsonAddress(json, ".contracts.faucet"));
        token = TitanToken(vm.parseJsonAddress(json, ".contracts.titanToken"));

        console.log("Faucet:", address(faucet));
        console.log("Faucet Balance:", token.balanceOf(address(faucet)) / 1e18, "TITAN\n");

        _testBasicProperties();
        _testClaiming();
        _testCooldown();
        _testAdminFunctions();
        _testEdgeCases();

        _printResults();
    }

    function _testBasicProperties() internal {
        console.log("--- Basic Properties ---");

        if (address(faucet.titanToken()) == address(token)) _p("titanToken()"); else _f("titanToken()");
        if (faucet.dripAmount() > 0) _p("dripAmount()"); else _f("dripAmount()");
        console.log("   Drip amount:", faucet.dripAmount() / 1e18, "TITAN");

        if (faucet.cooldownPeriod() > 0) _p("cooldownPeriod()"); else _f("cooldownPeriod()");
        console.log("   Cooldown:", faucet.cooldownPeriod() / 3600, "hours");

        if (faucet.balance() > 0) _p("balance()"); else _f("balance()");

        console.log("");
    }

    function _testClaiming() internal {
        console.log("--- Claiming ---");

        // Fresh user claim
        address newUser = makeAddr("freshUser");
        uint256 balBefore = token.balanceOf(newUser);

        if (faucet.canClaim(newUser)) _p("canClaim() for new user"); else _f("canClaim() new user");

        vm.prank(newUser);
        faucet.claim();
        uint256 balAfter = token.balanceOf(newUser);

        if (balAfter == balBefore + faucet.dripAmount()) _p("claim() correct amount"); else _f("claim() amount");
        console.log("   Received:", (balAfter - balBefore) / 1e18, "TITAN");

        // Multiple users claim
        for (uint i = 1; i <= 5; i++) {
            address user = makeAddr(string(abi.encodePacked("claimUser", vm.toString(i))));
            vm.prank(user);
            faucet.claim();
        }
        _p("5 different users claimed");

        console.log("");
    }

    function _testCooldown() internal {
        console.log("--- Cooldown ---");

        address user = makeAddr("cooldownUser");

        // First claim
        vm.prank(user);
        faucet.claim();

        // Check can't claim again
        if (!faucet.canClaim(user)) _p("canClaim() false after claim"); else _f("canClaim() should be false");

        // Try to claim again (should fail)
        vm.prank(user);
        try faucet.claim() {
            _f("Second claim should fail");
        } catch {
            _p("Second claim reverts");
        }

        // Check timeUntilNextClaim
        uint256 timeLeft = faucet.timeUntilNextClaim(user);
        if (timeLeft > 0) _p("timeUntilNextClaim() > 0"); else _f("timeUntilNextClaim()");
        console.log("   Time until next:", timeLeft / 3600, "hours");

        // Check lastClaimTime
        if (faucet.lastClaimTime(user) > 0) _p("lastClaimTime() recorded"); else _f("lastClaimTime()");

        // Warp time and claim again
        vm.warp(block.timestamp + faucet.cooldownPeriod() + 1);

        if (faucet.canClaim(user)) _p("canClaim() true after cooldown"); else _f("canClaim() after cooldown");

        if (faucet.timeUntilNextClaim(user) == 0) _p("timeUntilNextClaim() = 0"); else _f("timeUntilNextClaim() should be 0");

        vm.prank(user);
        faucet.claim();
        _p("Claim after cooldown works");

        console.log("");
    }

    function _testAdminFunctions() internal {
        console.log("--- Admin Functions ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // setDripAmount
        uint256 oldDrip = faucet.dripAmount();
        vm.broadcast(pk);
        faucet.setDripAmount(200 * 1e18);
        if (faucet.dripAmount() == 200 * 1e18) _p("setDripAmount()"); else _f("setDripAmount()");

        // Reset
        vm.broadcast(pk);
        faucet.setDripAmount(oldDrip);

        // setCooldownPeriod
        uint256 oldCooldown = faucet.cooldownPeriod();
        vm.broadcast(pk);
        faucet.setCooldownPeriod(12 hours);
        if (faucet.cooldownPeriod() == 12 hours) _p("setCooldownPeriod()"); else _f("setCooldownPeriod()");

        vm.broadcast(pk);
        faucet.setCooldownPeriod(oldCooldown);

        // setPaused
        vm.broadcast(pk);
        faucet.setPaused(true);
        if (faucet.paused()) _p("setPaused(true)"); else _f("setPaused(true)");

        // Try claim when paused
        address pauseUser = makeAddr("pauseUser");
        vm.prank(pauseUser);
        try faucet.claim() {
            _f("Claim when paused should fail");
        } catch {
            _p("Claim when paused reverts");
        }

        vm.broadcast(pk);
        faucet.setPaused(false);
        _p("setPaused(false)");

        // deposit
        vm.broadcast(pk);
        token.approve(address(faucet), 1000 * 1e18);
        vm.broadcast(pk);
        faucet.deposit(1000 * 1e18);
        _p("deposit()");

        // withdraw
        uint256 balBefore = faucet.balance();
        vm.broadcast(pk);
        faucet.withdraw(100 * 1e18);
        if (faucet.balance() == balBefore - 100 * 1e18) _p("withdraw()"); else _f("withdraw()");

        // Non-owner admin calls (should fail)
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        try faucet.setDripAmount(50 * 1e18) {
            _f("Non-owner setDripAmount should fail");
        } catch {
            _p("Non-owner setDripAmount reverts");
        }

        vm.prank(nonOwner);
        try faucet.setCooldownPeriod(1 hours) {
            _f("Non-owner setCooldownPeriod should fail");
        } catch {
            _p("Non-owner setCooldownPeriod reverts");
        }

        vm.prank(nonOwner);
        try faucet.setPaused(true) {
            _f("Non-owner setPaused should fail");
        } catch {
            _p("Non-owner setPaused reverts");
        }

        vm.prank(nonOwner);
        try faucet.withdraw(1) {
            _f("Non-owner withdraw should fail");
        } catch {
            _p("Non-owner withdraw reverts");
        }

        console.log("");
    }

    function _testEdgeCases() internal {
        console.log("--- Edge Cases ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // setDripAmount to 0 (should fail)
        vm.broadcast(pk);
        try faucet.setDripAmount(0) {
            _f("setDripAmount(0) should fail");
        } catch {
            _p("setDripAmount(0) reverts");
        }

        // setCooldownPeriod to 0 (should fail)
        vm.broadcast(pk);
        try faucet.setCooldownPeriod(0) {
            _f("setCooldownPeriod(0) should fail");
        } catch {
            _p("setCooldownPeriod(0) reverts");
        }

        // deposit 0 (should fail)
        vm.broadcast(pk);
        try faucet.deposit(0) {
            _f("deposit(0) should fail");
        } catch {
            _p("deposit(0) reverts");
        }

        // withdraw 0 (should fail)
        vm.broadcast(pk);
        try faucet.withdraw(0) {
            _f("withdraw(0) should fail");
        } catch {
            _p("withdraw(0) reverts");
        }

        // withdraw more than balance
        uint256 faucetBal = faucet.balance();
        vm.broadcast(pk);
        try faucet.withdraw(faucetBal + 1) {
            _f("withdraw > balance should fail");
        } catch {
            _p("withdraw > balance reverts");
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
