// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TitanToken
 * @author Titan Team
 * @notice ERC-20 token for the Titan DeFi ecosystem with governance support
 * @dev Implements ERC20Votes for snapshot-based governance voting
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title TitanToken
 * @notice The native token of the Titan DeFi super app with governance capabilities
 * @dev ERC-20 token with minting capability (owner only), burn function, and voting power
 */
contract TitanToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, Ownable {
    /// @notice Initial supply of 100 million tokens with 18 decimals
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;

    /// @notice Maximum supply cap of 1 billion tokens
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Emitted when tokens are minted
    event TokensMinted(address indexed to, uint256 amount);

    /// @notice Error when minting would exceed max supply
    error MaxSupplyExceeded(uint256 requested, uint256 available);

    /// @notice Error when minting to zero address
    error MintToZeroAddress();

    /// @notice Error when mint amount is zero
    error MintAmountZero();

    /**
     * @notice Constructs the TitanToken contract
     * @param initialOwner The address that will own the contract and receive initial supply
     */
    constructor(address initialOwner)
        ERC20("Titan Token", "TITAN")
        ERC20Permit("Titan Token")
        Ownable(initialOwner)
    {
        _mint(initialOwner, INITIAL_SUPPLY);
    }

    /**
     * @notice Mints new tokens to a specified address
     * @dev Only callable by the contract owner, respects MAX_SUPPLY cap
     * @param to The address to receive the minted tokens
     * @param amount The amount of tokens to mint (in wei)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert MintToZeroAddress();
        if (amount == 0) revert MintAmountZero();

        uint256 newSupply = totalSupply() + amount;
        if (newSupply > MAX_SUPPLY) {
            revert MaxSupplyExceeded(amount, MAX_SUPPLY - totalSupply());
        }

        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @notice Returns the number of decimals used by the token
     * @return The number of decimals (18)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Clock used for voting checkpoints - uses block number
     * @return Current block number
     */
    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    /**
     * @notice Machine-readable description of the clock
     * @return Clock mode description
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    // Required overrides for multiple inheritance

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
