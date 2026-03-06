// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TitanToken.sol";
import "../src/Governor.sol";

// Mock target contract for governance
contract MockTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function alwaysReverts() external pure {
        revert("Always reverts");
    }
}

contract GovernorTest is Test {
    TitanToken public token;
    Governor public governor;
    MockTarget public target;

    address public owner;
    address public proposer;
    address public voter1;
    address public voter2;
    address public voter3;

    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 public constant PROPOSAL_THRESHOLD = 1_000_000 * 10 ** 18;
    uint256 public constant VOTING_DELAY = 1; // 1 block
    uint256 public constant VOTING_PERIOD = 100; // 100 blocks
    uint256 public constant TIMELOCK_DELAY = 1 days;
    uint256 public constant QUORUM_PERCENTAGE = 400; // 4%

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
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint8 support, uint256 votes, string reason);
    event ProposalCanceled(uint256 indexed proposalId);
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);

    function setUp() public {
        owner = makeAddr("owner");
        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");

        vm.startPrank(owner);

        token = new TitanToken(owner);
        governor = new Governor(
            address(token),
            PROPOSAL_THRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            TIMELOCK_DELAY,
            QUORUM_PERCENTAGE
        );
        target = new MockTarget();

        // Distribute tokens
        token.transfer(proposer, PROPOSAL_THRESHOLD * 2);
        token.transfer(voter1, 5_000_000 * 10 ** 18); // 5%
        token.transfer(voter2, 3_000_000 * 10 ** 18); // 3%
        token.transfer(voter3, 500_000 * 10 ** 18); // 0.5% - below proposal threshold

        vm.stopPrank();

        // Delegate voting power
        vm.prank(proposer);
        token.delegate(proposer);

        vm.prank(voter1);
        token.delegate(voter1);

        vm.prank(voter2);
        token.delegate(voter2);

        vm.prank(voter3);
        token.delegate(voter3);

        // Roll forward to allow checkpoint
        vm.roll(block.number + 1);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsCorrectToken() public view {
        assertEq(address(governor.titanToken()), address(token));
    }

    function test_Constructor_SetsCorrectThreshold() public view {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function test_Constructor_SetsCorrectVotingDelay() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
    }

    function test_Constructor_SetsCorrectVotingPeriod() public view {
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_Constructor_SetsCorrectTimelockDelay() public view {
        assertEq(governor.timelockDelay(), TIMELOCK_DELAY);
    }

    function test_Constructor_SetsCorrectQuorum() public view {
        assertEq(governor.quorumPercentage(), QUORUM_PERCENTAGE);
    }

    function test_Constructor_RevertsIfZeroTokenAddress() public {
        vm.expectRevert(Governor.InvalidToken.selector);
        new Governor(
            address(0),
            PROPOSAL_THRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            TIMELOCK_DELAY,
            QUORUM_PERCENTAGE
        );
    }

    function test_Constructor_RevertsIfZeroVotingPeriod() public {
        vm.expectRevert(Governor.InvalidVotingPeriod.selector);
        new Governor(address(token), PROPOSAL_THRESHOLD, VOTING_DELAY, 0, TIMELOCK_DELAY, QUORUM_PERCENTAGE);
    }

    function test_Constructor_RevertsIfInvalidQuorum() public {
        vm.expectRevert(Governor.InvalidQuorum.selector);
        new Governor(address(token), PROPOSAL_THRESHOLD, VOTING_DELAY, VOTING_PERIOD, TIMELOCK_DELAY, 0);

        vm.expectRevert(Governor.InvalidQuorum.selector);
        new Governor(address(token), PROPOSAL_THRESHOLD, VOTING_DELAY, VOTING_PERIOD, TIMELOCK_DELAY, 10001);
    }

    // ============ Propose Tests ============

    function test_Propose_CreatesProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Set value to 42");

        assertEq(proposalId, 1);
        assertEq(governor.proposalCount(), 1);
    }

    function test_Propose_RevertsIfBelowThreshold() public {
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(voter3); // voter3 has only 500K tokens
        vm.expectRevert(abi.encodeWithSelector(Governor.BelowProposalThreshold.selector, 500_000 * 10 ** 18, PROPOSAL_THRESHOLD));
        governor.propose(targets, values, calldatas, "Set value to 42");
    }

    function test_Propose_RevertsIfEmptyProposal() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.prank(proposer);
        vm.expectRevert(Governor.EmptyProposal.selector);
        governor.propose(targets, values, calldatas, "Empty proposal");
    }

    function test_Propose_RevertsIfMismatchedArrays() public {
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(proposer);
        vm.expectRevert(Governor.InvalidProposalLength.selector);
        governor.propose(targets, values, calldatas, "Mismatched arrays");
    }

    // ============ Vote Tests ============

    function test_CastVote_RecordsVote() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // Vote for

        (bool hasVoted, uint8 support, uint256 votes) = governor.getReceipt(proposalId, voter1);
        assertTrue(hasVoted);
        assertEq(support, 1);
        assertEq(votes, 5_000_000 * 10 ** 18);
    }

    function test_CastVote_UpdatesVoteCounts() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        vm.prank(voter2);
        governor.castVote(proposalId, 0); // Against

        vm.prank(voter3);
        governor.castVote(proposalId, 2); // Abstain

        (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) = governor.getVotes(proposalId);

        assertEq(forVotes, 5_000_000 * 10 ** 18);
        assertEq(againstVotes, 3_000_000 * 10 ** 18);
        assertEq(abstainVotes, 500_000 * 10 ** 18);
    }

    function test_CastVote_RevertsIfAlreadyVoted() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter1);
        vm.expectRevert(Governor.AlreadyVoted.selector);
        governor.castVote(proposalId, 0);
    }

    function test_CastVote_RevertsIfVotingNotActive() public {
        uint256 proposalId = _createProposal();
        // Don't move to voting period

        vm.prank(voter1);
        vm.expectRevert(Governor.VotingNotActive.selector);
        governor.castVote(proposalId, 1);
    }

    function test_CastVote_RevertsIfInvalidVoteType() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        vm.expectRevert(Governor.InvalidVoteType.selector);
        governor.castVote(proposalId, 3);
    }

    function test_CastVoteWithReason() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        governor.castVoteWithReason(proposalId, 1, "I support this proposal");

        (bool hasVoted, , ) = governor.getReceipt(proposalId, voter1);
        assertTrue(hasVoted);
    }

    // ============ State Tests ============

    function test_State_Pending() public {
        uint256 proposalId = _createProposal();
        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Pending));
    }

    function test_State_Active() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Active));
    }

    function test_State_Defeated_QuorumNotMet() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        // Only voter3 votes (0.5% of supply, below 4% quorum)
        vm.prank(voter3);
        governor.castVote(proposalId, 1);

        _moveToVotingEnd();

        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Defeated));
    }

    function test_State_Defeated_MoreAgainstVotes() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        governor.castVote(proposalId, 0); // Against

        vm.prank(voter2);
        governor.castVote(proposalId, 0); // Against

        _moveToVotingEnd();

        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Defeated));
    }

    function test_State_Succeeded() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        vm.prank(voter2);
        governor.castVote(proposalId, 1); // For

        _moveToVotingEnd();

        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Succeeded));
    }

    function test_State_Canceled() public {
        uint256 proposalId = _createProposal();

        vm.prank(proposer);
        governor.cancel(proposalId);

        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Canceled));
    }

    // ============ Queue Tests ============

    function test_Queue_SetsEta() public {
        uint256 proposalId = _createSuccessfulProposal();

        governor.queue(proposalId);

        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Queued));
    }

    function test_Queue_RevertsIfNotSucceeded() public {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.expectRevert(Governor.ProposalNotSucceeded.selector);
        governor.queue(proposalId);
    }

    // ============ Execute Tests ============

    function test_Execute_ExecutesProposal() public {
        uint256 proposalId = _createQueuedProposal();

        vm.warp(block.timestamp + TIMELOCK_DELAY);

        governor.execute(proposalId);

        assertEq(target.value(), 42);
        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Executed));
    }

    function test_Execute_RevertsIfNotQueued() public {
        uint256 proposalId = _createSuccessfulProposal();

        vm.expectRevert(Governor.ProposalNotQueued.selector);
        governor.execute(proposalId);
    }

    function test_Execute_RevertsIfTimelockNotPassed() public {
        uint256 proposalId = _createQueuedProposal();

        vm.expectRevert(Governor.TimelockNotPassed.selector);
        governor.execute(proposalId);
    }

    function test_Execute_RevertsIfExpired() public {
        uint256 proposalId = _createQueuedProposal();

        vm.warp(block.timestamp + TIMELOCK_DELAY + 15 days);

        // When expired, state() returns Expired, so it fails with ProposalNotQueued
        vm.expectRevert(Governor.ProposalNotQueued.selector);
        governor.execute(proposalId);
    }

    function test_Execute_RevertsIfExecutionFails() public {
        // Create a proposal that will fail on execution
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.alwaysReverts.selector);

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Will revert");

        // Vote
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        // Queue
        vm.roll(block.number + VOTING_PERIOD + 1);
        governor.queue(proposalId);

        // Try to execute (should fail)
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.expectRevert(Governor.ExecutionFailed.selector);
        governor.execute(proposalId);
    }

    // ============ Cancel Tests ============

    function test_Cancel_CancelsProposal() public {
        uint256 proposalId = _createProposal();

        vm.prank(proposer);
        governor.cancel(proposalId);

        assertEq(uint256(governor.state(proposalId)), uint256(Governor.ProposalState.Canceled));
    }

    function test_Cancel_RevertsIfNotProposer() public {
        uint256 proposalId = _createProposal();

        vm.prank(voter1);
        vm.expectRevert(Governor.OnlyProposer.selector);
        governor.cancel(proposalId);
    }

    function test_Cancel_RevertsIfExecuted() public {
        uint256 proposalId = _createQueuedProposal();
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        governor.execute(proposalId);

        vm.prank(proposer);
        vm.expectRevert(Governor.ProposalAlreadyExecuted.selector);
        governor.cancel(proposalId);
    }

    // ============ View Functions Tests ============

    function test_GetProposal() public {
        uint256 proposalId = _createProposal();

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = governor.getProposal(proposalId);

        assertEq(targets[0], address(target));
        assertEq(values[0], 0);
        assertEq(calldatas[0], abi.encodeWithSelector(MockTarget.setValue.selector, 42));
        assertEq(description, "Set value to 42");
    }

    function test_ProposalSnapshot() public {
        uint256 blockBefore = block.number;
        uint256 proposalId = _createProposal();

        assertEq(governor.proposalSnapshot(proposalId), blockBefore);
    }

    function test_ProposalDeadline() public {
        uint256 blockBeforeProposal = block.number;
        uint256 proposalId = _createProposal();
        // voteEnd = snapshot + votingDelay + votingPeriod
        // snapshot = block.number at proposal creation = blockBeforeProposal
        uint256 expectedDeadline = blockBeforeProposal + VOTING_DELAY + VOTING_PERIOD;

        assertEq(governor.proposalDeadline(proposalId), expectedDeadline);
    }

    function test_GetVotingPower() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + 1); // Roll forward so snapshot is in the past

        uint256 votingPower = governor.getVotingPower(proposalId, voter1);
        assertEq(votingPower, 5_000_000 * 10 ** 18);
    }

    function test_Quorum() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + 1); // Roll forward so snapshot is in the past

        uint256 quorum = governor.quorum(proposalId);
        // 4% of 100M = 4M
        assertEq(quorum, 4_000_000 * 10 ** 18);
    }

    function test_State_RevertsIfInvalidProposalId() public {
        vm.expectRevert(Governor.InvalidProposalId.selector);
        governor.state(0);

        vm.expectRevert(Governor.InvalidProposalId.selector);
        governor.state(999);
    }

    // ============ Snapshot Security Tests ============

    function test_FlashLoanProtection() public {
        // Create proposal
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        // Even if someone gets tokens AFTER proposal creation, they can't vote
        vm.prank(owner);
        token.transfer(makeAddr("attacker"), 10_000_000 * 10 ** 18);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        token.delegate(attacker);

        // Attacker tries to vote but has no voting power at snapshot
        vm.prank(attacker);
        vm.expectRevert(Governor.NoVotingPower.selector);
        governor.castVote(proposalId, 1);
    }

    // ============ Helper Functions ============

    function _createProposal() internal returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(proposer);
        return governor.propose(targets, values, calldatas, "Set value to 42");
    }

    function _moveToVotingPeriod() internal {
        vm.roll(block.number + VOTING_DELAY + 1);
    }

    function _moveToVotingEnd() internal {
        vm.roll(block.number + VOTING_PERIOD + 1);
    }

    function _createSuccessfulProposal() internal returns (uint256) {
        uint256 proposalId = _createProposal();
        _moveToVotingPeriod();

        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        _moveToVotingEnd();

        return proposalId;
    }

    function _createQueuedProposal() internal returns (uint256) {
        uint256 proposalId = _createSuccessfulProposal();
        governor.queue(proposalId);
        return proposalId;
    }
}
