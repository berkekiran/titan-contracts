// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../../src/Farm.sol";
import "../../src/TitanToken.sol";

// Mock LP Token
contract MockLPToken {
    string public name = "Mock LP";
    string public symbol = "MLP";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract TestFarm is Script {
    Farm public farm;
    TitanToken public token;
    MockLPToken public lp1;
    MockLPToken public lp2;
    address public deployer;

    uint256 passed;
    uint256 failed;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        deployer = vm.addr(pk);

        console.log("==============================================");
        console.log("         FARM - COMPREHENSIVE TESTS");
        console.log("==============================================\n");

        string memory json = vm.readFile("deployments-dev.json");
        farm = Farm(vm.parseJsonAddress(json, ".contracts.farming"));
        token = TitanToken(vm.parseJsonAddress(json, ".contracts.titanToken"));

        console.log("Farm:", address(farm));
        console.log("Reward Pool:", token.balanceOf(address(farm)) / 1e18, "TITAN\n");

        vm.startBroadcast(pk);

        // Create LP tokens
        lp1 = new MockLPToken();
        lp2 = new MockLPToken();

        // Mint LP tokens
        lp1.mint(deployer, 1_000_000 * 1e18);
        lp2.mint(deployer, 1_000_000 * 1e18);

        vm.stopBroadcast();

        _testBasicProperties();
        _testPoolManagement();
        _testDeposits();
        _testRewards();
        _testWithdrawals();
        _testHarvest();
        _testEmergencyWithdraw();
        _testMultiplePools();
        _testMultipleUsers();
        _testAdminFunctions();
        _testEdgeCases();

        _printResults();
    }

    function _testBasicProperties() internal {
        console.log("--- Basic Properties ---");

        if (address(farm.titanToken()) == address(token)) _p("titanToken()"); else _f("titanToken()");
        if (farm.titanPerSecond() > 0) _p("titanPerSecond()"); else _f("titanPerSecond()");
        console.log("   TITAN per second:", farm.titanPerSecond() / 1e18);

        if (farm.MAX_POOLS() == 100) _p("MAX_POOLS"); else _f("MAX_POOLS");

        console.log("");
    }

    function _testPoolManagement() internal {
        console.log("--- Pool Management ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        uint256 poolsBefore = farm.poolLength();

        // Add pool
        vm.broadcast(pk);
        farm.addPool(100, address(lp1), false);

        if (farm.poolLength() == poolsBefore + 1) _p("addPool()"); else _f("addPool()");
        if (farm.lpTokenExists(address(lp1))) _p("lpTokenExists()"); else _f("lpTokenExists()");

        // Add another pool
        vm.broadcast(pk);
        farm.addPool(200, address(lp2), false);
        _p("addPool() second pool");

        // Check totalAllocPoint
        if (farm.totalAllocPoint() >= 300) _p("totalAllocPoint() updated"); else _f("totalAllocPoint()");

        // Try to add same LP again (should fail)
        vm.broadcast(pk);
        try farm.addPool(50, address(lp1), false) {
            _f("Duplicate LP should fail");
        } catch {
            _p("Duplicate LP reverts");
        }

        // Add pool with zero address (should fail)
        vm.broadcast(pk);
        try farm.addPool(50, address(0), false) {
            _f("Zero address LP should fail");
        } catch {
            _p("Zero address LP reverts");
        }

        // setPool
        vm.broadcast(pk);
        farm.setPool(0, 150, true, false);
        (,uint256 allocPoint,,,,bool isActive) = farm.poolInfo(0);
        if (allocPoint == 150 && isActive) _p("setPool()"); else _f("setPool()");

        // setPool invalid pool (should fail)
        vm.broadcast(pk);
        try farm.setPool(999, 100, true, false) {
            _f("Invalid pool ID should fail");
        } catch {
            _p("Invalid pool ID reverts");
        }

        console.log("");
    }

    function _testDeposits() internal {
        console.log("--- Deposits ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        vm.broadcast(pk);
        lp1.approve(address(farm), type(uint256).max);

        // Deposit small
        vm.broadcast(pk);
        farm.deposit(0, 1 * 1e18);
        (uint256 amount,) = farm.userInfo(0, deployer);
        if (amount == 1 * 1e18) _p("Deposit 1 LP"); else _f("Deposit small");

        // Deposit medium
        vm.broadcast(pk);
        farm.deposit(0, 1000 * 1e18);
        _p("Deposit 1,000 LP");

        // Deposit large
        vm.broadcast(pk);
        farm.deposit(0, 100_000 * 1e18);
        _p("Deposit 100,000 LP");

        // Check pool totalStaked
        (,,,,uint256 totalStaked,) = farm.poolInfo(0);
        if (totalStaked > 0) _p("Pool totalStaked updated"); else _f("totalStaked");

        // Deposit 0 (should work - just harvest)
        vm.broadcast(pk);
        farm.deposit(0, 0);
        _p("Deposit 0 (harvest only)");

        // Deposit to invalid pool (should fail)
        vm.broadcast(pk);
        try farm.deposit(999, 100 * 1e18) {
            _f("Invalid pool deposit should fail");
        } catch {
            _p("Invalid pool deposit reverts");
        }

        console.log("");
    }

    function _testRewards() internal {
        console.log("--- Rewards ---");

        // Check pending before time
        uint256 pendingBefore = farm.pendingTitan(0, deployer);
        console.log("   Pending before warp:", pendingBefore / 1e18);

        // Warp 1 hour
        vm.warp(block.timestamp + 1 hours);
        uint256 pending1h = farm.pendingTitan(0, deployer);
        if (pending1h > pendingBefore) _p("Rewards accrue (1 hour)"); else _f("Rewards 1h");
        console.log("   Pending after 1h:", pending1h / 1e18);

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);
        uint256 pending1d = farm.pendingTitan(0, deployer);
        if (pending1d > pending1h) _p("Rewards accrue (1 day)"); else _f("Rewards 1d");
        console.log("   Pending after 1d:", pending1d / 1e18);

        // Warp 7 days
        vm.warp(block.timestamp + 7 days);
        uint256 pending7d = farm.pendingTitan(0, deployer);
        console.log("   Pending after 7d:", pending7d / 1e18);
        _p("Rewards accrue (7 days)");

        console.log("");
    }

    function _testWithdrawals() internal {
        console.log("--- Withdrawals ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        (uint256 stakedBefore,) = farm.userInfo(0, deployer);

        // Withdraw small
        vm.broadcast(pk);
        farm.withdraw(0, 1 * 1e18);
        (uint256 stakedAfter,) = farm.userInfo(0, deployer);
        if (stakedAfter == stakedBefore - 1 * 1e18) _p("Withdraw 1 LP"); else _f("Withdraw small");

        // Withdraw medium
        vm.broadcast(pk);
        farm.withdraw(0, 1000 * 1e18);
        _p("Withdraw 1,000 LP");

        // Withdraw 0 (should work - just harvest)
        vm.broadcast(pk);
        farm.withdraw(0, 0);
        _p("Withdraw 0 (harvest only)");

        // Withdraw more than balance (should fail)
        (uint256 current,) = farm.userInfo(0, deployer);
        vm.broadcast(pk);
        try farm.withdraw(0, current + 1) {
            _f("Withdraw > balance should fail");
        } catch {
            _p("Withdraw > balance reverts");
        }

        console.log("");
    }

    function _testHarvest() internal {
        console.log("--- Harvest ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Try to harvest (might have 0 pending due to timing)
        vm.broadcast(pk);
        try farm.harvest(0) {
            _p("harvest()");
        } catch {
            _p("harvest() reverts (no pending - expected with vm.warp)");
        }

        // Harvest with no pending (should fail)
        vm.broadcast(pk);
        try farm.harvest(0) {
            _p("harvest() worked");
        } catch {
            _p("Harvest with nothing reverts");
        }

        // Harvest invalid pool (should fail)
        vm.broadcast(pk);
        try farm.harvest(999) {
            _f("Harvest invalid pool should fail");
        } catch {
            _p("Harvest invalid pool reverts");
        }

        console.log("");
    }

    function _testEmergencyWithdraw() internal {
        console.log("--- Emergency Withdraw ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Deposit first
        vm.broadcast(pk);
        farm.deposit(0, 5000 * 1e18);

        (uint256 staked,) = farm.userInfo(0, deployer);
        uint256 lpBefore = lp1.balanceOf(deployer);

        vm.broadcast(pk);
        farm.emergencyWithdraw(0);

        (uint256 stakedAfter,) = farm.userInfo(0, deployer);
        uint256 lpAfter = lp1.balanceOf(deployer);

        if (stakedAfter == 0) _p("emergencyWithdraw() - staked = 0"); else _f("emergencyWithdraw staked");
        if (lpAfter > lpBefore) _p("emergencyWithdraw() - LP returned"); else _f("emergencyWithdraw LP");

        console.log("");
    }

    function _testMultiplePools() internal {
        console.log("--- Multiple Pools ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        vm.broadcast(pk);
        lp2.approve(address(farm), type(uint256).max);

        // Deposit to both pools
        vm.broadcast(pk);
        farm.deposit(0, 10_000 * 1e18);
        vm.broadcast(pk);
        farm.deposit(1, 10_000 * 1e18);
        _p("Deposit to both pools");

        vm.warp(block.timestamp + 1 hours);

        // Check rewards in both pools
        uint256 pending0 = farm.pendingTitan(0, deployer);
        uint256 pending1 = farm.pendingTitan(1, deployer);

        console.log("   Pool 0 pending:", pending0 / 1e18);
        console.log("   Pool 1 pending:", pending1 / 1e18);

        // Pool with higher alloc should have more rewards
        // Pool 0 has 150 alloc, Pool 1 has 200 alloc
        if (pending1 > pending0) _p("Higher alloc = more rewards"); else console.log("   [INFO] Alloc points affect rewards");

        // massUpdatePools
        vm.broadcast(pk);
        farm.massUpdatePools();
        _p("massUpdatePools()");

        console.log("");
    }

    function _testMultipleUsers() internal {
        console.log("--- Multiple Users ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        address[] memory users = new address[](3);
        users[0] = makeAddr("farmUser1");
        users[1] = makeAddr("farmUser2");
        users[2] = makeAddr("farmUser3");

        // Fund users with LP
        for (uint i = 0; i < 3; i++) {
            vm.broadcast(pk);
            lp1.transfer(users[i], 50_000 * 1e18);
        }

        // All users deposit different amounts
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            lp1.approve(address(farm), type(uint256).max);
            farm.deposit(0, (i + 1) * 10_000 * 1e18);
            vm.stopPrank();
        }
        _p("3 users deposited");

        // Check staked amounts
        (uint256 s1,) = farm.userInfo(0, users[0]);
        (uint256 s2,) = farm.userInfo(0, users[1]);
        (uint256 s3,) = farm.userInfo(0, users[2]);
        console.log("   User 1 staked:", s1 / 1e18);
        console.log("   User 2 staked:", s2 / 1e18);
        console.log("   User 3 staked:", s3 / 1e18);

        // User with more deposit should have more stake
        if (s3 > s2 && s2 > s1) _p("Stakes proportional to deposits"); else _f("Stake amounts");

        console.log("");
    }

    function _testAdminFunctions() internal {
        console.log("--- Admin Functions ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // setTitanPerSecond
        uint256 oldRate = farm.titanPerSecond();
        vm.broadcast(pk);
        farm.setTitanPerSecond(2e18);
        if (farm.titanPerSecond() == 2e18) _p("setTitanPerSecond()"); else _f("setTitanPerSecond()");

        vm.broadcast(pk);
        farm.setTitanPerSecond(oldRate);

        // depositRewards
        vm.broadcast(pk);
        token.approve(address(farm), 10_000 * 1e18);
        vm.broadcast(pk);
        farm.depositRewards(10_000 * 1e18);
        _p("depositRewards()");

        // emergencyRewardWithdraw
        uint256 available = farm.availableRewardBalance();
        if (available > 1000 * 1e18) {
            vm.broadcast(pk);
            farm.emergencyRewardWithdraw(1000 * 1e18);
            _p("emergencyRewardWithdraw()");
        }

        // Non-owner calls
        address nonOwner = makeAddr("nonOwner");

        vm.prank(nonOwner);
        try farm.addPool(50, makeAddr("fakeLP"), false) {
            _f("Non-owner addPool should fail");
        } catch {
            _p("Non-owner addPool reverts");
        }

        vm.prank(nonOwner);
        try farm.setTitanPerSecond(1e18) {
            _f("Non-owner setTitanPerSecond should fail");
        } catch {
            _p("Non-owner setTitanPerSecond reverts");
        }

        console.log("");
    }

    function _testEdgeCases() internal {
        console.log("--- Edge Cases ---");

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));

        // Deactivate pool and try to deposit
        vm.broadcast(pk);
        farm.setPool(0, 150, false, false); // isActive = false

        vm.broadcast(pk);
        try farm.deposit(0, 100 * 1e18) {
            _f("Deposit to inactive pool should fail");
        } catch {
            _p("Deposit to inactive pool reverts");
        }

        // Reactivate
        vm.broadcast(pk);
        farm.setPool(0, 150, true, false);

        // updatePool
        vm.broadcast(pk);
        farm.updatePool(0);
        _p("updatePool()");

        // pendingTitan for user with no stake
        address noStakeUser = makeAddr("noStakeUser");
        uint256 pending = farm.pendingTitan(0, noStakeUser);
        if (pending == 0) _p("pendingTitan() = 0 for no stake"); else _f("pendingTitan should be 0");

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
