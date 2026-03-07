// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

interface ILiquidityRouter {
    function getPosition(address, address, address, uint24, int24, int24, int24) external view returns (uint128);
}

interface IStateView {
    function getSlot0(bytes32) external view returns (uint160, int24, uint24, uint24);
    function getLiquidity(bytes32) external view returns (uint128);
}

contract CheckPool is Script {
    function run() external view {
        bytes32 poolId = 0x4ae462d3c91da0f107761d41803f02a4e03123028630ca17fe6937b8742746b9;

        (uint160 sqrtPrice, int24 tick,,) = IStateView(0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C).getSlot0(poolId);
        uint128 poolLiq = IStateView(0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C).getLiquidity(poolId);

        console.log("=== Pool State ===");
        console.log("sqrtPriceX96:", sqrtPrice);
        console.log("tick:", tick);
        console.log("Pool liquidity:", poolLiq);

        uint128 userLiq = ILiquidityRouter(0x266E2E67dCe607fcE9aF30b2fb23Fcb070c45299).getPosition(
            0x4Fd7Ef2D7E7d795b042C88Cf779dd86eB568AD81,
            0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            0xbA6720e72f929318E66AcED4389889640Aee0F6e,
            3000, 60, -887220, 887220
        );
        console.log("");
        console.log("=== User Position ===");
        console.log("User liquidity:", userLiq);

        if (poolLiq > 0) {
            uint256 share = uint256(userLiq) * 10000 / uint256(poolLiq);
            console.log("User share (basis points):", share);
        }
    }
}
