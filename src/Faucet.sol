// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Faucet
 * @author Titan Team
 * @notice Testnet faucet for TITAN tokens
 * @dev DISCLAIMER: This contract is for educational and testing purposes only.
 * Do not use in production without proper security audits.
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Faucet
 * @notice Drips TITAN tokens for testing with rate limiting
 * @dev One claim per address every 24 hours
 */
contract Faucet is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The TITAN token
    IERC20 public immutable titanToken;

    /// @notice Amount of tokens to drip per claim
    uint256 public dripAmount;

    /// @notice Cooldown period between claims in seconds
    uint256 public cooldownPeriod;

    /// @notice Mapping of address to last claim timestamp
    mapping(address => uint256) public lastClaimTime;

    /// @notice Whether the faucet is paused
    bool public paused;

    /// @notice Emitted when tokens are claimed
    event TokensClaimed(address indexed claimer, uint256 amount);

    /// @notice Emitted when drip amount is updated
    event DripAmountUpdated(uint256 oldAmount, uint256 newAmount);

    /// @notice Emitted when cooldown period is updated
    event CooldownPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    /// @notice Emitted when faucet is paused/unpaused
    event PausedStateChanged(bool paused);

    /// @notice Emitted when tokens are deposited
    event TokensDeposited(address indexed depositor, uint256 amount);

    /// @notice Emitted when tokens are withdrawn
    event TokensWithdrawn(address indexed to, uint256 amount);

    /**
     * @notice Constructs the Faucet contract
     * @param _titanToken Address of the TITAN token
     * @param _dripAmount Amount of tokens per claim
     * @param _cooldownPeriod Cooldown period in seconds
     * @param _owner Address of the contract owner
     */
    constructor(
        address _titanToken,
        uint256 _dripAmount,
        uint256 _cooldownPeriod,
        address _owner
    ) Ownable(_owner) {
        require(_titanToken != address(0), "Faucet: invalid token");
        require(_dripAmount > 0, "Faucet: invalid drip amount");
        require(_cooldownPeriod > 0, "Faucet: invalid cooldown");

        titanToken = IERC20(_titanToken);
        dripAmount = _dripAmount;
        cooldownPeriod = _cooldownPeriod;
    }

    /**
     * @notice Claim tokens from the faucet
     */
    function claim() external nonReentrant {
        require(!paused, "Faucet: paused");
        require(canClaim(msg.sender), "Faucet: cooldown not passed");
        require(titanToken.balanceOf(address(this)) >= dripAmount, "Faucet: insufficient balance");

        lastClaimTime[msg.sender] = block.timestamp;
        titanToken.safeTransfer(msg.sender, dripAmount);

        emit TokensClaimed(msg.sender, dripAmount);
    }

    /**
     * @notice Check if an address can claim
     * @param account Address to check
     * @return Whether the address can claim
     */
    function canClaim(address account) public view returns (bool) {
        // If never claimed, allow claim
        if (lastClaimTime[account] == 0) {
            return true;
        }
        return block.timestamp >= lastClaimTime[account] + cooldownPeriod;
    }

    /**
     * @notice Get time until next claim is available
     * @param account Address to check
     * @return Seconds until next claim (0 if can claim now)
     */
    function timeUntilNextClaim(address account) external view returns (uint256) {
        // If never claimed, can claim now
        if (lastClaimTime[account] == 0) {
            return 0;
        }
        uint256 nextClaimTime = lastClaimTime[account] + cooldownPeriod;
        if (block.timestamp >= nextClaimTime) {
            return 0;
        }
        return nextClaimTime - block.timestamp;
    }

    /**
     * @notice Update the drip amount
     * @param newDripAmount New drip amount
     */
    function setDripAmount(uint256 newDripAmount) external onlyOwner {
        require(newDripAmount > 0, "Faucet: invalid drip amount");
        uint256 oldAmount = dripAmount;
        dripAmount = newDripAmount;
        emit DripAmountUpdated(oldAmount, newDripAmount);
    }

    /**
     * @notice Update the cooldown period
     * @param newCooldownPeriod New cooldown period in seconds
     */
    function setCooldownPeriod(uint256 newCooldownPeriod) external onlyOwner {
        require(newCooldownPeriod > 0, "Faucet: invalid cooldown");
        uint256 oldPeriod = cooldownPeriod;
        cooldownPeriod = newCooldownPeriod;
        emit CooldownPeriodUpdated(oldPeriod, newCooldownPeriod);
    }

    /**
     * @notice Pause or unpause the faucet
     * @param isPaused Whether to pause
     */
    function setPaused(bool isPaused) external onlyOwner {
        paused = isPaused;
        emit PausedStateChanged(isPaused);
    }

    /**
     * @notice Deposit tokens into the faucet
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Faucet: invalid amount");
        titanToken.safeTransferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw tokens from the faucet
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external onlyOwner {
        require(amount > 0, "Faucet: invalid amount");
        require(titanToken.balanceOf(address(this)) >= amount, "Faucet: insufficient balance");
        titanToken.safeTransfer(owner(), amount);
        emit TokensWithdrawn(owner(), amount);
    }

    /**
     * @notice Get the current faucet balance
     * @return Current token balance
     */
    function balance() external view returns (uint256) {
        return titanToken.balanceOf(address(this));
    }
}
