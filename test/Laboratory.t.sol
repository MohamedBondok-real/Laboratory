// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {Laboratory} from "../src/Laboratory.sol";

contract LaboratoryTest is Test {
    Laboratory private lab;

    address private operator = makeAddr("operator");
    address private reviewer = makeAddr("reviewer");
    address private client = makeAddr("client");
    address private otherClient = makeAddr("other-client");
    address private outsider = makeAddr("outsider");

    bytes32 private constant CLIENT_HASH = keccak256("client metadata");
    bytes32 private constant UPDATED_HASH = keccak256("updated metadata");
    bytes32 private constant REPORT_HASH = keccak256("report v1");
    bytes32 private constant REPORT_HASH_2 = keccak256("report v2");
    string private constant REF = "sample-001";

    function setUp() public {
        lab = new Laboratory();
        lab.registerClient(client, CLIENT_HASH, Laboratory.ClientType.Individual);
        lab.registerClient(otherClient, UPDATED_HASH, Laboratory.ClientType.Organization);
        lab.setOperator(operator, true);
        lab.setReviewer(reviewer, true);
    }

    function _register(string memory reference_) private {
        vm.prank(client);
        lab.registerSample(reference_, Laboratory.SampleType.Blood, Laboratory.SamplePriority.High);
    }

    function _toProcessing(string memory reference_) private {
        vm.startPrank(operator);
        lab.updateSampleStatus(reference_, Laboratory.SampleStatus.Collected);
        lab.updateSampleStatus(reference_, Laboratory.SampleStatus.Processing);
        vm.stopPrank();
    }

    function _submit(string memory reference_, bytes32 digest) private {
        vm.prank(operator);
        lab.submitReport(reference_, digest, Laboratory.SampleReportFormat.PDF, Laboratory.SampleResult.Negative);
    }

    function _approvedReleased(string memory reference_) private {
        _register(reference_);
        _toProcessing(reference_);
        _submit(reference_, REPORT_HASH);
        vm.prank(reviewer);
        lab.approveResult(reference_);
        vm.prank(operator);
        lab.releaseSample(reference_);
    }

    function testConstructorSetsDeployerAsOwner() public view {
        assertEq(lab.owner(), address(this));
        assertFalse(lab.paused());
        assertEq(lab.totalSamples(), 0);
    }

    function testOwnerCanConfigureRolesAndTransferOwnership() public {
        address newOwner = makeAddr("new-owner");
        vm.expectEmit(true, false, false, true);
        emit Laboratory.OwnershipTransferred(address(this), newOwner);
        lab.transferOwnership(newOwner);
        assertEq(lab.owner(), newOwner);

        vm.prank(newOwner);
        lab.setPaused(true);
        assertTrue(lab.paused());
    }

    function testOnlyOwnerCanManageRolesClientsPauseAndOwnership() public {
        vm.startPrank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.setOperator(outsider, true);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.setReviewer(outsider, true);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.registerClient(outsider, CLIENT_HASH, Laboratory.ClientType.Individual);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.setClientStatus(client, Laboratory.ClientStatus.Inactive);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.setPaused(true);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.transferOwnership(outsider);
        vm.stopPrank();
    }

    function testRejectsZeroAddressesForOwnerConfiguration() public {
        vm.expectRevert(Laboratory.Laboratory__ZeroAddress.selector);
        lab.setOperator(address(0), true);
        vm.expectRevert(Laboratory.Laboratory__ZeroAddress.selector);
        lab.setReviewer(address(0), true);
        vm.expectRevert(Laboratory.Laboratory__ZeroAddress.selector);
        lab.transferOwnership(address(0));
        vm.expectRevert(Laboratory.Laboratory__ZeroAddress.selector);
        lab.registerClient(address(0), CLIENT_HASH, Laboratory.ClientType.Individual);
        vm.expectRevert(Laboratory.Laboratory__ZeroAddress.selector);
        lab.setClientStatus(address(0), Laboratory.ClientStatus.Active);
    }

    function testRoleConflictIsRejectedInBothDirectionsAndCanBeRevoked() public {
        vm.expectRevert(Laboratory.Laboratory__RoleConflict.selector);
        lab.setReviewer(operator, true);
        vm.expectRevert(Laboratory.Laboratory__RoleConflict.selector);
        lab.setOperator(reviewer, true);

        lab.setOperator(operator, false);
        lab.setReviewer(operator, true);
        lab.setReviewer(operator, false);
        lab.setOperator(operator, true);
    }

    function testRevokedOperatorAndReviewerLoseTheirPermissions() public {
        _register(REF);
        _toProcessing(REF);
        _submit(REF, REPORT_HASH);
        lab.setReviewer(reviewer, false);
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.approveResult(REF);

        lab.setOperator(operator, false);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.registerSampleForClient(client, "sample-after-revoke", Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);
    }

    function testClientRegistrationValidatesInputsAndUniqueness() public {
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.registerClient(outsider, bytes32(0), Laboratory.ClientType.Individual);
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.registerClient(outsider, CLIENT_HASH, Laboratory.ClientType.None);
        vm.expectRevert(Laboratory.Laboratory__RecordAlreadyExists.selector);
        lab.registerClient(client, UPDATED_HASH, Laboratory.ClientType.Individual);
    }

    function testClientCanUpdateMetadataAndRejectsZeroHash() public {
        vm.prank(client);
        lab.updateClientMetadata(UPDATED_HASH);
        (, bytes32 metadataHash,,,,) = lab.clients(client);
        assertEq(metadataHash, UPDATED_HASH);

        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.updateClientMetadata(bytes32(0));
    }

    function testOnlyActiveExistingClientCanUpdateMetadataOrRegister() public {
        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.updateClientMetadata(UPDATED_HASH);

        lab.setClientStatus(client, Laboratory.ClientStatus.Suspended);
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.updateClientMetadata(UPDATED_HASH);
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.registerSample(REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);

        lab.setClientStatus(client, Laboratory.ClientStatus.Inactive);
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.registerSample(REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);
        lab.setClientStatus(client, Laboratory.ClientStatus.Active);
    }

    function testClientStatusValidationAndChanges() public {
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.setClientStatus(outsider, Laboratory.ClientStatus.Active);
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.setClientStatus(client, Laboratory.ClientStatus.None);
        lab.setClientStatus(client, Laboratory.ClientStatus.Suspended);
        (, , Laboratory.ClientStatus status,,,) = lab.clients(client);
        assertEq(uint256(status), uint256(Laboratory.ClientStatus.Suspended));
    }

    function testClientCanRegisterSampleAndIndexesAreUpdated() public {
        vm.expectEmit(true, true, false, true);
        emit Laboratory.SampleRegistered(keccak256(bytes(REF)), client, block.timestamp);
        _register(REF);

        assertEq(lab.totalSamples(), 1);
        assertEq(lab.clientSampleCount(client), 1);
        bytes32[] memory ids = lab.getClientSamples(client);
        assertEq(ids.length, 1);
        assertEq(ids[0], keccak256(bytes(REF)));
        Laboratory.SampleHistory[] memory history = lab.getSampleHistory(REF);
        assertEq(history.length, 1);
        assertEq(uint256(history[0].status), uint256(Laboratory.SampleStatus.Registered));
        (bool exists,, uint256 updatedAt, Laboratory.SampleStatus auditStatus) = lab.auditRecords(ids[0]);
        assertTrue(exists);
        assertEq(updatedAt, block.timestamp);
        assertEq(uint256(auditStatus), uint256(Laboratory.SampleStatus.Registered));
    }

    function testGetSampleReturnsStoredSampleAndRejectsUnknownReference() public {
        _register(REF);

        Laboratory.Sample memory sample = lab.getSample(REF);
        assertTrue(sample.exists);
        assertEq(sample.sampleReference, REF);
        assertEq(sample.clientAccount, client);
        assertEq(uint256(sample.sampleType), uint256(Laboratory.SampleType.Blood));
        assertEq(uint256(sample.priority), uint256(Laboratory.SamplePriority.High));
        assertEq(uint256(sample.status), uint256(Laboratory.SampleStatus.Registered));

        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.getSample("unknown-sample");
    }

    function testSampleRegistrationRejectsEmptyDuplicateAndInvalidEnums() public {
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__InvalidReference.selector);
        lab.registerSample("", Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.registerSample(REF, Laboratory.SampleType.None, Laboratory.SamplePriority.Low);
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.registerSample(REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.None);

        _register(REF);
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__RecordAlreadyExists.selector);
        lab.registerSample(REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);
    }

    function testOperatorCanRegisterForActiveClientAndValidatesClientAndInputs() public {
        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.registerSampleForClient(client, REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Medium);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__ZeroAddress.selector);
        lab.registerSampleForClient(address(0), REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Medium);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidReference.selector);
        lab.registerSampleForClient(client, "", Laboratory.SampleType.Blood, Laboratory.SamplePriority.Medium);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidClient.selector);
        lab.registerSampleForClient(outsider, REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Medium);
        lab.setClientStatus(client, Laboratory.ClientStatus.Inactive);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidClient.selector);
        lab.registerSampleForClient(client, REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Medium);

        lab.setClientStatus(client, Laboratory.ClientStatus.Active);
        vm.prank(operator);
        lab.registerSampleForClient(client, REF, Laboratory.SampleType.Urine, Laboratory.SamplePriority.Urgent);
        assertEq(lab.clientSampleCount(client), 1);
        assertEq(lab.totalSamples(), 1);
    }

    function testOperatorCannotRegisterDuplicateSample() public {
        _register(REF);

        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__RecordAlreadyExists.selector);
        lab.registerSampleForClient(client, REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);
    }

    function testOwnerCanReadAnyClientSamplesClientCanReadOwnAndOutsiderCannot() public {
        _register(REF);
        vm.prank(client);
        assertEq(lab.getClientSamples(client).length, 1);
        vm.prank(otherClient);
        assertEq(lab.getClientSamples(otherClient).length, 0);
        assertEq(lab.getClientSamples(client).length, 1); // owner

        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.getClientSamples(client);
    }

    function testOperatorCanReadEveryClientsSampleIdentifiers() public {
        _register(REF);
        vm.prank(otherClient);
        lab.registerSample("sample-002", Laboratory.SampleType.Saliva, Laboratory.SamplePriority.Low);

        vm.prank(operator);
        bytes32[] memory clientIds = lab.getClientSamples(client);
        assertEq(clientIds.length, 1);
        assertEq(clientIds[0], keccak256(bytes(REF)));
        vm.prank(operator);
        bytes32[] memory otherIds = lab.getClientSamples(otherClient);
        assertEq(otherIds.length, 1);
        assertEq(otherIds[0], keccak256(bytes("sample-002")));
    }

    function testPausingBlocksSampleAndReportWorkflowButOwnerCanUnpause() public {
        lab.setPaused(true);
        vm.prank(client);
        vm.expectRevert(Laboratory.Laboratory__ContractPaused.selector);
        lab.registerSample(REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__ContractPaused.selector);
        lab.registerSampleForClient(client, REF, Laboratory.SampleType.Blood, Laboratory.SamplePriority.Low);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__ContractPaused.selector);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__ContractPaused.selector);
        lab.submitReport(REF, REPORT_HASH, Laboratory.SampleReportFormat.PDF, Laboratory.SampleResult.Negative);
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__ContractPaused.selector);
        lab.approveResult(REF);
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__ContractPaused.selector);
        lab.rejectResult(REF, "reason");
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__ContractPaused.selector);
        lab.releaseSample(REF);

        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.setPaused(false);
        lab.setPaused(false);
        _register(REF);
    }

    function testStatusTransitionsAndTimestamps() public {
        _register(REF);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
        // `block.timestamp` is fixed for the test transaction context, so a
        // second relative warp would target the same timestamp.
        vm.warp(block.timestamp + 2 hours);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Processing);

        Laboratory.SampleHistory[] memory history = lab.getSampleHistory(REF);
        assertEq(history.length, 3);
        assertEq(uint256(history[1].status), uint256(Laboratory.SampleStatus.Collected));
        assertEq(uint256(history[2].status), uint256(Laboratory.SampleStatus.Processing));
        assertGt(history[1].changedAt, history[0].changedAt);
        assertGt(history[2].changedAt, history[1].changedAt);
    }

    function testStatusTransitionRejectsUnauthorizedMissingAndInvalidMoves() public {
        _register(REF);
        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.updateSampleStatus("missing", Laboratory.SampleStatus.Collected);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidStatusTransition.selector);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Processing);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidStatusTransition.selector);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidStatusTransition.selector);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.None);
    }

    function testEveryUnsupportedStatusTransitionReverts() public {
        _register("matrix-registered");
        _assertUnsupportedTransitions("matrix-registered", Laboratory.SampleStatus.Collected);

        _register("matrix-collected");
        vm.prank(operator);
        lab.updateSampleStatus("matrix-collected", Laboratory.SampleStatus.Collected);
        _assertUnsupportedTransitions("matrix-collected", Laboratory.SampleStatus.Processing);

        _register("matrix-processing");
        _toProcessing("matrix-processing");
        _assertUnsupportedTransitions("matrix-processing", Laboratory.SampleStatus.RecollectionRequired);

        _register("matrix-rejected");
        _toProcessing("matrix-rejected");
        _submit("matrix-rejected", REPORT_HASH);
        vm.prank(reviewer);
        lab.rejectResult("matrix-rejected", "retest");
        _assertUnsupportedTransitions("matrix-rejected", Laboratory.SampleStatus.RecollectionRequired);

        _register("matrix-recollection");
        _toProcessing("matrix-recollection");
        vm.prank(operator);
        lab.updateSampleStatus("matrix-recollection", Laboratory.SampleStatus.RecollectionRequired);
        _assertUnsupportedTransitions("matrix-recollection", Laboratory.SampleStatus.Collected);
    }

    function testReleasedSampleCannotTransitionFurther() public {
        _approvedReleased(REF);

        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidStatusTransition.selector);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
    }

    function _assertUnsupportedTransitions(string memory reference_, Laboratory.SampleStatus allowed)
        private
    {
        for (uint256 i; i <= uint256(Laboratory.SampleStatus.RecollectionRequired); ++i) {
            Laboratory.SampleStatus candidate = Laboratory.SampleStatus(i);
            if (candidate == allowed) continue;
            vm.prank(operator);
            vm.expectRevert(Laboratory.Laboratory__InvalidStatusTransition.selector);
            lab.updateSampleStatus(reference_, candidate);
        }
    }

    function testReportSubmissionValidatesStateDigestFormatAndResult() public {
        _register(REF);
        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.submitReport(REF, REPORT_HASH, Laboratory.SampleReportFormat.PDF, Laboratory.SampleResult.Negative);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidStatusTransition.selector);
        lab.submitReport(REF, REPORT_HASH, Laboratory.SampleReportFormat.PDF, Laboratory.SampleResult.Negative);
        _toProcessing(REF);

        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidReportDigest.selector);
        lab.submitReport(REF, bytes32(0), Laboratory.SampleReportFormat.PDF, Laboratory.SampleResult.Negative);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.submitReport(REF, REPORT_HASH, Laboratory.SampleReportFormat.None, Laboratory.SampleResult.Negative);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.submitReport(REF, REPORT_HASH, Laboratory.SampleReportFormat.PDF, Laboratory.SampleResult.None);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.submitReport("missing", REPORT_HASH, Laboratory.SampleReportFormat.PDF, Laboratory.SampleResult.Negative);
    }

    function testReviewerCanApproveReportAndOperatorCanReleaseIt() public {
        _register(REF);
        _toProcessing(REF);
        vm.warp(block.timestamp + 12 minutes);
        _submit(REF, REPORT_HASH);
        vm.warp(block.timestamp + 5 minutes);
        vm.expectEmit(true, false, true, true);
        emit Laboratory.ResultApproved(keccak256(bytes(REF)), 1, reviewer);
        vm.prank(reviewer);
        lab.approveResult(REF);

        assertEq(lab.approvedVersions(keccak256(bytes(REF))), 1);
        Laboratory.SampleReport memory report = lab.getReport(REF, 1);
        assertEq(report.reportDigest, REPORT_HASH);
        assertEq(uint256(report.reportFormat), uint256(Laboratory.SampleReportFormat.PDF));
        assertEq(uint256(report.result), uint256(Laboratory.SampleResult.Negative));
        assertEq(report.reviewer, reviewer);
        assertEq(report.reviewedAt, block.timestamp);
        assertEq(report.submittedAt, block.timestamp - 5 minutes);

        vm.warp(block.timestamp + 3 minutes);
        vm.prank(operator);
        lab.releaseSample(REF);
        Laboratory.Sample memory releasedSample = lab.getSample(REF);
        assertEq(releasedSample.releasedAt, block.timestamp);
        Laboratory.SampleHistory[] memory history = lab.getSampleHistory(REF);
        assertEq(uint256(history[history.length - 1].status), uint256(Laboratory.SampleStatus.Released));
    }

    function testApprovalRejectsVersionOverflow() public {
        _register(REF);
        _toProcessing(REF);
        _submit(REF, REPORT_HASH);

        // approvedVersions is the seventh storage slot in Laboratory.
        bytes32 versionSlot = keccak256(abi.encode(keccak256(bytes(REF)), uint256(6)));
        vm.store(address(lab), versionSlot, bytes32(uint256(type(uint32).max)));

        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__InvalidVersion.selector);
        lab.approveResult(REF);
    }

    function testApprovalRejectsUnauthorizedMissingAndNoPendingReport() public {
        _register(REF);
        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.approveResult(REF);
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.approveResult("missing");
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__ResultNotApproved.selector);
        lab.approveResult(REF);

        _toProcessing(REF);
        _submit(REF, REPORT_HASH);
        vm.prank(reviewer);
        lab.approveResult(REF);
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__ResultNotApproved.selector);
        lab.approveResult(REF);
    }

    function testReviewerCanRejectPendingReportAndRequiresReason() public {
        _register(REF);
        _toProcessing(REF);
        _submit(REF, REPORT_HASH);
        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.rejectResult(REF, "incorrect");
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__InvalidInput.selector);
        lab.rejectResult(REF, "");

        vm.expectEmit(true, true, false, true);
        emit Laboratory.ResultRejected(keccak256(bytes(REF)), reviewer, "incorrect result");
        vm.prank(reviewer);
        lab.rejectResult(REF, "incorrect result");
        Laboratory.SampleHistory[] memory history = lab.getSampleHistory(REF);
        assertEq(uint256(history[history.length - 1].status), uint256(Laboratory.SampleStatus.Rejected));
        vm.prank(reviewer);
        vm.expectRevert(Laboratory.Laboratory__NoPendingReport.selector);
        lab.rejectResult(REF, "again");
    }

    function testRejectedSampleCanBeRecollectedAndResubmittedAsNewReportVersion() public {
        _register(REF);
        _toProcessing(REF);
        _submit(REF, REPORT_HASH);
        vm.prank(reviewer);
        lab.rejectResult(REF, "retest");
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.RecollectionRequired);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Processing);
        _submit(REF, REPORT_HASH_2);
        vm.prank(reviewer);
        lab.approveResult(REF);

        assertEq(lab.approvedVersions(keccak256(bytes(REF))), 1);
        assertEq(lab.getReport(REF, 1).reportDigest, REPORT_HASH_2);
    }

    function testProcessingCanRequestRecollectionAndRestart() public {
        _register(REF);
        _toProcessing(REF);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.RecollectionRequired);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Collected);
        vm.prank(operator);
        lab.updateSampleStatus(REF, Laboratory.SampleStatus.Processing);
        Laboratory.SampleHistory[] memory history = lab.getSampleHistory(REF);
        assertEq(history.length, 6);
        assertEq(uint256(history[3].status), uint256(Laboratory.SampleStatus.RecollectionRequired));
        assertEq(uint256(history[5].status), uint256(Laboratory.SampleStatus.Processing));
    }

    function testReleaseRequiresApprovedResultAndOperator() public {
        _register(REF);
        vm.prank(outsider);
        vm.expectRevert(Laboratory.Laboratory__Unauthorized.selector);
        lab.releaseSample(REF);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__ResultNotApproved.selector);
        lab.releaseSample(REF);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.releaseSample("missing");

        _toProcessing(REF);
        _submit(REF, REPORT_HASH);
        vm.prank(reviewer);
        lab.approveResult(REF);
        vm.prank(operator);
        lab.releaseSample(REF);
        vm.prank(operator);
        vm.expectRevert(Laboratory.Laboratory__ResultNotApproved.selector);
        lab.releaseSample(REF);
    }

    function testReportGetterRejectsMissingSampleAndInvalidVersion() public {
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.getReport("missing", 1);
        _register(REF);
        vm.expectRevert(Laboratory.Laboratory__InvalidVersion.selector);
        lab.getReport(REF, 0);
        vm.expectRevert(Laboratory.Laboratory__InvalidVersion.selector);
        lab.getReport(REF, 1);
    }

    function testHistoryGetterRejectsUnknownSample() public {
        vm.expectRevert(Laboratory.Laboratory__RecordNotFound.selector);
        lab.getSampleHistory("missing");
    }

    function testMultipleSamplesMaintainIndependentCountsAndHistory() public {
        _register("sample-a");
        vm.prank(otherClient);
        lab.registerSample("sample-b", Laboratory.SampleType.Urine, Laboratory.SamplePriority.Low);
        _register("sample-c");

        assertEq(lab.totalSamples(), 3);
        assertEq(lab.clientSampleCount(client), 2);
        assertEq(lab.clientSampleCount(otherClient), 1);
        assertEq(lab.getClientSamples(client).length, 2);
        assertEq(lab.getClientSamples(otherClient).length, 1);
        assertEq(lab.getSampleHistory("sample-b").length, 1);
    }

    function testFuzzAnyValidNonemptyReferenceCanBeRegistered(bytes32 seed) public {
        vm.assume(seed != bytes32(0));
        string memory reference_ = vm.toString(seed);
        _register(reference_);
        assertEq(lab.totalSamples(), 1);
        assertEq(lab.getSampleHistory(reference_).length, 1);
    }

    function testFuzzEveryValidSampleTypeAndPriority(uint8 sampleType, uint8 priority) public {
        vm.assume(sampleType >= uint8(Laboratory.SampleType.Blood));
        vm.assume(sampleType <= uint8(Laboratory.SampleType.Other));
        vm.assume(priority >= uint8(Laboratory.SamplePriority.Low));
        vm.assume(priority <= uint8(Laboratory.SamplePriority.Urgent));

        vm.prank(client);
        lab.registerSample(
            REF, Laboratory.SampleType(sampleType), Laboratory.SamplePriority(priority)
        );
        assertEq(lab.totalSamples(), 1);
        assertEq(lab.clientSampleCount(client), 1);
    }

    function testFuzzEveryValidReportFormatAndResult(uint8 reportFormat, uint8 result) public {
        vm.assume(reportFormat >= uint8(Laboratory.SampleReportFormat.PDF));
        vm.assume(reportFormat <= uint8(Laboratory.SampleReportFormat.XML));
        vm.assume(result >= uint8(Laboratory.SampleResult.Negative));
        vm.assume(result <= uint8(Laboratory.SampleResult.Inconclusive));

        _register(REF);
        _toProcessing(REF);
        bytes32 digest = keccak256(abi.encode(reportFormat, result));
        vm.prank(operator);
        lab.submitReport(
            REF,
            digest,
            Laboratory.SampleReportFormat(reportFormat),
            Laboratory.SampleResult(result)
        );
        vm.prank(reviewer);
        lab.approveResult(REF);
        Laboratory.SampleReport memory report = lab.getReport(REF, 1);
        assertEq(report.reportDigest, digest);
        assertEq(uint256(report.reportFormat), reportFormat);
        assertEq(uint256(report.result), result);
    }
}
