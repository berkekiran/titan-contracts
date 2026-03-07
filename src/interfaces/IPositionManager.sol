// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IPoolManager.sol";

/// @title IPositionManager
/// @notice Interface for Uniswap V4 PositionManager
interface IPositionManager {
    /// @notice Batches many liquidity modification calls to pool manager
    /// @param unlockData is an encoding of actions, and parameters for those actions
    /// @param deadline is the deadline for the batched actions to be executed
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;

    /// @notice Batches many liquidity modification calls to pool manager without closing deltas
    /// @param actions the actions to perform
    /// @param params the parameters to provide for the actions
    function modifyLiquiditiesWithoutUnlock(bytes calldata actions, bytes[] calldata params) external payable;

    /// @notice Used to get the ID that will be used for the next minted liquidity position
    /// @return uint256 The next token ID
    function nextTokenId() external view returns (uint256);

    /// @notice Returns the position info for a given token ID
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

    /// @notice ERC721 transfer
    function transferFrom(address from, address to, uint256 tokenId) external;

    /// @notice ERC721 ownerOf
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Actions for PositionManager
library Actions {
    // Pool actions (no-op on PositionManager)
    uint256 constant SETTLE = 0x09;
    uint256 constant TAKE = 0x0d;
    uint256 constant CLOSE_CURRENCY = 0x11;
    uint256 constant SWEEP = 0x14;

    // Position actions
    uint256 constant MINT_POSITION = 0x00;
    uint256 constant INCREASE_LIQUIDITY = 0x02;
    uint256 constant DECREASE_LIQUIDITY = 0x03;
    uint256 constant BURN_POSITION = 0x04;

    // Settling actions
    uint256 constant SETTLE_PAIR = 0x10;
    uint256 constant TAKE_PAIR = 0x12;
}
