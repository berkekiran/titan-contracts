// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IStateView
/// @notice Interface for Uniswap V4 StateView contract to read pool state
interface IStateView {
    /// @notice Get slot0 data for a pool
    /// @param poolId The pool ID (keccak256 of PoolKey)
    /// @return sqrtPriceX96 The current sqrt price
    /// @return tick The current tick
    /// @return protocolFee The protocol fee
    /// @return lpFee The LP fee
    function getSlot0(bytes32 poolId) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    );

    /// @notice Get liquidity for a pool
    /// @param poolId The pool ID
    /// @return liquidity The current liquidity
    function getLiquidity(bytes32 poolId) external view returns (uint128 liquidity);
}
