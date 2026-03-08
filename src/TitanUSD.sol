// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TitanUSD (tUSD)
 * @author Titan Team
 * @notice Overcollateralized stablecoin backed by TITAN
 * @dev Only authorized minters (Vault contract) can mint/burn
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TitanUSD is ERC20, ERC20Burnable, Ownable {
    /// @notice Addresses authorized to mint tUSD
    mapping(address => bool) public minters;

    /// @notice Emitted when a minter is added or removed
    event MinterUpdated(address indexed minter, bool authorized);

    /// @notice Error when caller is not authorized to mint
    error NotAuthorizedMinter();

    /**
     * @notice Constructs the TitanUSD token
     * @param _owner Address of the contract owner
     */
    constructor(address _owner) ERC20("Titan USD", "tUSD") Ownable(_owner) {}

    /**
     * @notice Adds or removes a minter
     * @param minter Address to update
     * @param authorized Whether the address can mint
     */
    function setMinter(address minter, bool authorized) external onlyOwner {
        minters[minter] = authorized;
        emit MinterUpdated(minter, authorized);
    }

    /**
     * @notice Mints tUSD to an address
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external {
        if (!minters[msg.sender]) revert NotAuthorizedMinter();
        _mint(to, amount);
    }

    /**
     * @notice Burns tUSD from caller
     * @param amount Amount to burn
     */
    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    /**
     * @notice Burns tUSD from an address (requires allowance)
     * @param account Address to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address account, uint256 amount) public override {
        super.burnFrom(account, amount);
    }
}
