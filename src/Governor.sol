// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Governor
 * @author Titan Team
 * @notice Governance contract for Titan DAO with snapshot-based voting
 * @dev Uses ERC20Votes checkpoints to prevent flash loan attacks
 */

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Governor
 * @notice Allows TITAN holders to create and vote on proposals
 * @dev Implements snapshot-based voting using ERC20Votes checkpoints
 */
contract Governor is ReentrancyGuard {
    /// @notice The TITAN token used for voting (must implement ERC20Votes)
    ERC20Votes public immutable titanToken;

    /// @notice Minimum tokens required to create a proposal
    uint256 public immutable proposalThreshold;

    /// @notice Delay between proposal creation and voting start (in blocks)
    uint256 public immutable votingDelay;

    /// @notice Duration of voting period in blocks
    uint256 public immutable votingPeriod;

    /// @notice Timelock delay before execution in seconds
    uint256 public immutable timelockDelay;

    /// @notice Quorum required for proposal to pass (percentage * 100, e.g., 400 = 4%)
    uint256 public immutable quorumPercentage;

    /// @notice Proposal counter
    uint256 public proposalCount;

    /// @notice Proposal state enum
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @notice Proposal struct
    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint256 voteStart;      // Block number when voting starts
        uint256 voteEnd;        // Block number when voting ends
        uint256 snapshotBlock;  // Block number for vote power snapshot
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        uint256 eta;            // Execution time after timelock (timestamp)
    }

    /// @notice Vote receipt
    struct Receipt {
        bool hasVoted;
        uint8 support;  // 0 = Against, 1 = For, 2 = Abstain
        uint256 votes;
    }

    /// @notice Mapping of proposal ID to proposal
    mapping(uint256 => Proposal) public proposals;

    /// @notice Mapping of proposal ID to voter address to receipt
    mapping(uint256 => mapping(address => Receipt)) public receipts;

    /// @notice Emitted when a proposal is created
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        string description,
        uint256 voteStart,
        uint256 voteEnd,
        uint256 snapshotBlock
    );

    /// @notice Emitted when a vote is cast
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 votes,
        string reason
    );

    /// @notice Emitted when a proposal is canceled
    event ProposalCanceled(uint256 indexed proposalId);

    /// @notice Emitted when a proposal is queued
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);

    /// @notice Emitted when a proposal is executed
    event ProposalExecuted(uint256 indexed proposalId);

    /// @notice Error definitions
    error InvalidToken();
    error InvalidVotingPeriod();
    error InvalidQuorum();
    error InvalidVotingDelay();
    error BelowProposalThreshold(uint256 votes, uint256 threshold);
    error InvalidProposalLength();
    error EmptyProposal();
    error InvalidProposalId();
    error VotingNotActive();
    error InvalidVoteType();
    error AlreadyVoted();
    error NoVotingPower();
    error ProposalNotSucceeded();
    error ProposalNotQueued();
    error TimelockNotPassed();
    error ProposalExpired();
    error OnlyProposer();
    error ProposalAlreadyExecuted();
    error ExecutionFailed();

    /**
     * @notice Constructs the Governor contract
     * @param _titanToken Address of the TITAN token (must implement ERC20Votes)
     * @param _proposalThreshold Minimum tokens to create proposal
     * @param _votingDelay Delay before voting starts (in blocks)
     * @param _votingPeriod Duration of voting (in blocks)
     * @param _timelockDelay Delay before execution (in seconds)
     * @param _quorumPercentage Quorum percentage * 100
     */
    constructor(
        address _titanToken,
        uint256 _proposalThreshold,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _timelockDelay,
        uint256 _quorumPercentage
    ) {
        if (_titanToken == address(0)) revert InvalidToken();
        if (_votingPeriod == 0) revert InvalidVotingPeriod();
        if (_quorumPercentage == 0 || _quorumPercentage > 10000) revert InvalidQuorum();

        titanToken = ERC20Votes(_titanToken);
        proposalThreshold = _proposalThreshold;
        votingDelay = _votingDelay;
        votingPeriod = _votingPeriod;
        timelockDelay = _timelockDelay;
        quorumPercentage = _quorumPercentage;
    }

    /**
     * @notice Create a new proposal
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param calldatas Array of calldata
     * @param description Proposal description
     * @return proposalId The ID of the created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256 proposalId) {
        // Check proposer has enough voting power at current block
        uint256 proposerVotes = titanToken.getVotes(msg.sender);
        if (proposerVotes < proposalThreshold) {
            revert BelowProposalThreshold(proposerVotes, proposalThreshold);
        }

        if (targets.length != values.length || targets.length != calldatas.length) {
            revert InvalidProposalLength();
        }
        if (targets.length == 0) revert EmptyProposal();

        proposalId = ++proposalCount;

        // Snapshot is taken at current block
        uint256 snapshot = block.number;
        uint256 voteStart = snapshot + votingDelay;
        uint256 voteEnd = voteStart + votingPeriod;

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;
        proposal.description = description;
        proposal.snapshotBlock = snapshot;
        proposal.voteStart = voteStart;
        proposal.voteEnd = voteEnd;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            calldatas,
            description,
            voteStart,
            voteEnd,
            snapshot
        );
    }

    /**
     * @notice Cast a vote on a proposal
     * @param proposalId The ID of the proposal
     * @param support Vote type (0 = Against, 1 = For, 2 = Abstain)
     */
    function castVote(uint256 proposalId, uint8 support) external nonReentrant {
        _castVote(proposalId, msg.sender, support, "");
    }

    /**
     * @notice Cast a vote on a proposal with reason
     * @param proposalId The ID of the proposal
     * @param support Vote type (0 = Against, 1 = For, 2 = Abstain)
     * @param reason Reason for the vote
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external nonReentrant {
        _castVote(proposalId, msg.sender, support, reason);
    }

    /**
     * @notice Internal vote casting logic
     */
    function _castVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        string memory reason
    ) internal {
        if (state(proposalId) != ProposalState.Active) revert VotingNotActive();
        if (support > 2) revert InvalidVoteType();

        Receipt storage receipt = receipts[proposalId][voter];
        if (receipt.hasVoted) revert AlreadyVoted();

        Proposal storage proposal = proposals[proposalId];

        // Get voting power from snapshot block (prevents flash loans)
        uint256 votes = titanToken.getPastVotes(voter, proposal.snapshotBlock);
        if (votes == 0) revert NoVotingPower();

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        if (support == 0) {
            proposal.againstVotes += votes;
        } else if (support == 1) {
            proposal.forVotes += votes;
        } else {
            proposal.abstainVotes += votes;
        }

        emit VoteCast(voter, proposalId, support, votes, reason);
    }

    /**
     * @notice Queue a succeeded proposal for execution
     * @param proposalId The ID of the proposal
     */
    function queue(uint256 proposalId) external {
        if (state(proposalId) != ProposalState.Succeeded) revert ProposalNotSucceeded();

        Proposal storage proposal = proposals[proposalId];
        proposal.eta = block.timestamp + timelockDelay;

        emit ProposalQueued(proposalId, proposal.eta);
    }

    /**
     * @notice Execute a queued proposal
     * @param proposalId The ID of the proposal
     */
    function execute(uint256 proposalId) external payable nonReentrant {
        ProposalState currentState = state(proposalId);
        if (currentState != ProposalState.Queued) revert ProposalNotQueued();

        Proposal storage proposal = proposals[proposalId];
        if (block.timestamp < proposal.eta) revert TimelockNotPassed();

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            if (!success) revert ExecutionFailed();
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal
     * @param proposalId The ID of the proposal
     */
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (msg.sender != proposal.proposer) revert OnlyProposer();
        if (proposal.executed) revert ProposalAlreadyExecuted();

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    /**
     * @notice Get the state of a proposal
     * @param proposalId The ID of the proposal
     * @return The current state of the proposal
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        if (proposalId == 0 || proposalId > proposalCount) revert InvalidProposalId();

        Proposal storage proposal = proposals[proposalId];

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (block.number < proposal.voteStart) {
            return ProposalState.Pending;
        }

        if (block.number <= proposal.voteEnd) {
            return ProposalState.Active;
        }

        // Voting ended - check outcome
        if (!_quorumReached(proposalId) || !_voteSucceeded(proposalId)) {
            return ProposalState.Defeated;
        }

        if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        }

        if (block.timestamp >= proposal.eta + 14 days) {
            return ProposalState.Expired;
        }

        return ProposalState.Queued;
    }

    /**
     * @notice Check if quorum was reached for a proposal
     * @param proposalId The ID of the proposal
     * @return Whether quorum was reached
     */
    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;

        // Get total supply at snapshot block for quorum calculation
        uint256 snapshotSupply = titanToken.getPastTotalSupply(proposal.snapshotBlock);
        uint256 requiredQuorum = (snapshotSupply * quorumPercentage) / 10000;

        return totalVotes >= requiredQuorum;
    }

    /**
     * @notice Check if vote succeeded (more for than against)
     * @param proposalId The ID of the proposal
     * @return Whether the vote succeeded
     */
    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes;
    }

    /**
     * @notice Get the quorum for a proposal
     * @param proposalId The ID of the proposal
     * @return The quorum amount
     */
    function quorum(uint256 proposalId) external view returns (uint256) {
        if (proposalId == 0 || proposalId > proposalCount) revert InvalidProposalId();
        Proposal storage proposal = proposals[proposalId];
        uint256 snapshotSupply = titanToken.getPastTotalSupply(proposal.snapshotBlock);
        return (snapshotSupply * quorumPercentage) / 10000;
    }

    /**
     * @notice Get proposal details
     * @param proposalId The ID of the proposal
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.targets, proposal.values, proposal.calldatas, proposal.description);
    }

    /**
     * @notice Get vote counts for a proposal
     * @param proposalId The ID of the proposal
     */
    function getVotes(uint256 proposalId)
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
    {
        Proposal storage proposal = proposals[proposalId];
        return (proposal.forVotes, proposal.againstVotes, proposal.abstainVotes);
    }

    /**
     * @notice Check if an account has voted on a proposal
     * @param proposalId The ID of the proposal
     * @param account The account to check
     */
    function getReceipt(uint256 proposalId, address account)
        external
        view
        returns (bool hasVoted, uint8 support, uint256 votes)
    {
        Receipt storage receipt = receipts[proposalId][account];
        return (receipt.hasVoted, receipt.support, receipt.votes);
    }

    /**
     * @notice Get the snapshot block for a proposal
     * @param proposalId The ID of the proposal
     * @return The block number used for voting power snapshot
     */
    function proposalSnapshot(uint256 proposalId) external view returns (uint256) {
        return proposals[proposalId].snapshotBlock;
    }

    /**
     * @notice Get the deadline block for a proposal
     * @param proposalId The ID of the proposal
     * @return The block number when voting ends
     */
    function proposalDeadline(uint256 proposalId) external view returns (uint256) {
        return proposals[proposalId].voteEnd;
    }

    /**
     * @notice Get the voting power of an account at a proposal's snapshot
     * @param proposalId The ID of the proposal
     * @param account The account to check
     * @return The voting power
     */
    function getVotingPower(uint256 proposalId, address account) external view returns (uint256) {
        if (proposalId == 0 || proposalId > proposalCount) revert InvalidProposalId();
        return titanToken.getPastVotes(account, proposals[proposalId].snapshotBlock);
    }

    /**
     * @notice Receive ETH for proposal execution
     */
    receive() external payable {}
}
