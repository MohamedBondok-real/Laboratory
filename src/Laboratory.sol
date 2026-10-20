// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

contract Laboratory {
    //////// State Variables /////////
    address public owner;
    bool public paused;

    constructor() {
        owner = msg.sender;
    }

    //////// Modifiers /////////
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert Laboratory__Unauthorized();
        }
        _;
    }
    modifier onlyOperator() {
        if (!operators[msg.sender]) {
            revert Laboratory__Unauthorized();
        }
        _;
    }
    modifier onlyClient() {
        if (!clients[msg.sender].exists || clients[msg.sender].status != ClientStatus.Active) {
            revert Laboratory__Unauthorized();
        }
        _;
    }
    modifier onlyReviewer() {
        if (!reviewers[msg.sender]) {
            revert Laboratory__Unauthorized();
        }
        _;
    }
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert Laboratory__ZeroAddress();
        }
        _;
    }
    modifier contractNotPaused() {
        if (paused) {
            revert Laboratory__ContractPaused();
        }
        _;
    }
    modifier sampleExists(string memory _reference) {
        if (!samples[_reference].exists) {
            revert Laboratory__RecordNotFound();
        }
        _;
    }
    modifier sampleNotExists(string memory _reference) {
        if (samples[_reference].exists) {
            revert Laboratory__RecordAlreadyExists();
        }
        _;
    }

    //////// Errors /////////
    error Laboratory__Unauthorized();
    error Laboratory__ZeroAddress();
    error Laboratory__InvalidReference();
    error Laboratory__RecordAlreadyExists();
    error Laboratory__RecordNotFound();
    error Laboratory__InvalidStatusTransition();
    error Laboratory__ResultNotApproved();
    error Laboratory__InvalidReportDigest();
    error Laboratory__InvalidVersion();
    error Laboratory__ContractPaused();
    error Laboratory__InvalidClient();
    error Laboratory__InvalidInput();
    error Laboratory__NoPendingReport();
    error Laboratory__RoleConflict();

    ///////// Enums /////////
    enum SampleStatus {
        None,
        Registered,
        Collected,
        Processing,
        AwaitingReview,
        Approved,
        Released,
        Rejected,
        RecollectionRequired
    }
    enum SampleType {
        None,
        Blood,
        Urine,
        Saliva,
        Tissue,
        Other
    }
    enum SamplePriority {
        None,
        Low,
        Medium,
        High,
        Urgent
    }
    enum SampleResult {
        None,
        Negative,
        Positive,
        Inconclusive
    }
    enum SampleReportFormat {
        None,
        PDF,
        JSON,
        XML
    }
    enum ClientStatus {
        None,
        Active,
        Inactive,
        Suspended
    }
    enum ClientType {
        None,
        Individual,
        Organization,
        Government
    }

    ///////// Structs /////////
    struct AuditRecord {
        bool exists;
        uint256 createdAt;
        uint256 updatedAt;
        SampleStatus status;
    }

    struct Sample {
        bool exists;
        string sampleReference;
        address clientAccount;
        address registeredBy;
        SampleType sampleType;
        SamplePriority priority;
        SampleStatus status;
        SampleResult result;
        bytes32 reportDigest;
        SampleReportFormat reportFormat;
        uint256 createdAt;
        uint256 updatedAt;
        uint256 collectedAt;
        uint256 releasedAt;
        bool reportPending;
    }

    struct Client {
        bool exists;
        bytes32 metadataHash;
        ClientStatus status;
        ClientType clientType;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct SampleHistory {
        SampleStatus status;
        uint256 changedAt;
    }

    struct SampleReport {
        bytes32 reportDigest;
        SampleReportFormat reportFormat;
        SampleResult result;
        address reviewer;
        uint256 submittedAt;
        uint256 reviewedAt;
    }

    ///////// Mappings /////////
    mapping(string => Sample) private samples;
    mapping(address => bool) public operators;
    mapping(address => bool) public reviewers;
    mapping(address => Client) public clients;
    mapping(bytes32 => AuditRecord) public auditRecords;
    mapping(bytes32 => uint32) public approvedVersions;
    mapping(bytes32 => SampleHistory[]) private sampleHistories;
    mapping(bytes32 => mapping(uint32 => SampleReport)) private sampleReports;
    mapping(address => bytes32[]) private clientSamples;
    mapping(address => uint256) public clientSampleCount;
    uint256 public totalSamples;

    //////// Events /////////
    event OperatorUpdated(address indexed account, bool allowed);
    event ReviewerUpdated(address indexed account, bool allowed);
    event SampleRegistered(bytes32 indexed sampleRef, address indexed registeredBy, uint256 timestamp);
    event SampleStatusChanged(
        bytes32 indexed sampleRef, SampleStatus oldStatus, SampleStatus newStatus, address indexed changedBy
    );
    event ResultApproved(bytes32 indexed sampleRef, uint32 version, address indexed reviewer);

    event ClientRegistered(address indexed account, ClientType clientType, bytes32 metadataHash);
    event ClientUpdated(address indexed account, ClientStatus status);
    event ClientMetadataUpdated(address indexed account, bytes32 metadataHash);
    event ReportSubmitted(bytes32 indexed sampleRef, bytes32 reportDigest, SampleReportFormat format);
    event ContractPauseChanged(bool paused);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ResultRejected(bytes32 indexed sampleRef, address indexed reviewer, string reason);

    modifier validReference(string memory reference_) {
        if (bytes(reference_).length == 0) revert Laboratory__InvalidReference();
        _;
    }

    function setOperator(address account, bool allowed) external onlyOwner notZeroAddress(account) {
        if (allowed && reviewers[account]) revert Laboratory__RoleConflict();
        operators[account] = allowed;
        emit OperatorUpdated(account, allowed);
    }

    function transferOwnership(address newOwner) external onlyOwner notZeroAddress(newOwner) {
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function setReviewer(address account, bool allowed) external onlyOwner notZeroAddress(account) {
        if (allowed && operators[account]) revert Laboratory__RoleConflict();
        reviewers[account] = allowed;
        emit ReviewerUpdated(account, allowed);
    }

    function setPaused(bool shouldPause) external onlyOwner {
        paused = shouldPause;
        emit ContractPauseChanged(shouldPause);
    }

    function registerClient(address account, bytes32 metadataHash, ClientType kind)
        external
        onlyOwner
        notZeroAddress(account)
    {
        if (kind == ClientType.None || metadataHash == bytes32(0)) revert Laboratory__InvalidInput();
        Client storage client = clients[account];
        if (client.exists) revert Laboratory__RecordAlreadyExists();
        client.exists = true;
        client.metadataHash = metadataHash;
        client.status = ClientStatus.Active;
        client.clientType = kind;
        if (client.createdAt == 0) client.createdAt = block.timestamp;
        client.updatedAt = block.timestamp;
        emit ClientRegistered(account, kind, metadataHash);
        emit ClientUpdated(account, client.status);
    }

    function updateClientMetadata(bytes32 metadataHash) external onlyClient {
        if (metadataHash == bytes32(0)) revert Laboratory__InvalidInput();
        clients[msg.sender].metadataHash = metadataHash;
        clients[msg.sender].updatedAt = block.timestamp;
        emit ClientMetadataUpdated(msg.sender, metadataHash);
    }

    function setClientStatus(address account, ClientStatus status) external onlyOwner notZeroAddress(account) {
        if (!clients[account].exists || status == ClientStatus.None) revert Laboratory__RecordNotFound();
        clients[account].status = status;
        clients[account].updatedAt = block.timestamp;
        emit ClientUpdated(account, status);
    }

    function registerSample(string calldata reference_, SampleType sampleType, SamplePriority priority)
        external
        contractNotPaused
        onlyClient
        validReference(reference_)
        sampleNotExists(reference_)
    {
        _registerSample(msg.sender, reference_, sampleType, priority);
    }

    function registerSampleForClient(
        address clientAccount,
        string calldata reference_,
        SampleType sampleType,
        SamplePriority priority
    )
        external
        contractNotPaused
        onlyOperator
        notZeroAddress(clientAccount)
        validReference(reference_)
        sampleNotExists(reference_)
    {
        _requireActiveClient(clientAccount);
        _registerSample(clientAccount, reference_, sampleType, priority);
    }

    function _registerSample(
        address clientAccount,
        string calldata reference_,
        SampleType sampleType,
        SamplePriority priority
    ) private {
        if (sampleType == SampleType.None || priority == SamplePriority.None) {
            revert Laboratory__InvalidInput();
        }
        Sample storage sample = samples[reference_];
        sample.exists = true;
        sample.sampleReference = reference_;
        sample.clientAccount = clientAccount;
        sample.registeredBy = msg.sender;
        sample.sampleType = sampleType;
        sample.priority = priority;
        sample.status = SampleStatus.Registered;
        sample.createdAt = block.timestamp;
        sample.updatedAt = block.timestamp;
        bytes32 key = _sampleKey(reference_);
        _appendHistory(key, SampleStatus.Registered);
        clientSamples[clientAccount].push(key);
        ++clientSampleCount[clientAccount];
        ++totalSamples;
        emit SampleRegistered(key, msg.sender, block.timestamp);
    }

    function updateSampleStatus(string calldata reference_, SampleStatus nextStatus)
        external
        contractNotPaused
        onlyOperator
        sampleExists(reference_)
    {
        if (!_validTransition(samples[reference_].status, nextStatus)) {
            revert Laboratory__InvalidStatusTransition();
        }
        _setStatus(reference_, nextStatus);
    }

    function submitReport(
        string calldata reference_,
        bytes32 reportDigest,
        SampleReportFormat format,
        SampleResult result
    ) external contractNotPaused onlyOperator sampleExists(reference_) {
        Sample storage sample = samples[reference_];
        if (sample.status != SampleStatus.Processing) revert Laboratory__InvalidStatusTransition();
        if (reportDigest == bytes32(0)) revert Laboratory__InvalidReportDigest();
        if (format == SampleReportFormat.None || result == SampleResult.None) revert Laboratory__InvalidInput();
        sample.reportDigest = reportDigest;
        sample.reportFormat = format;
        sample.result = result;
        sample.reportPending = true;
        sample.updatedAt = block.timestamp;
        _setStatus(reference_, SampleStatus.AwaitingReview);
        emit ReportSubmitted(_sampleKey(reference_), reportDigest, format);
    }

    function rejectResult(string calldata reference_, string calldata reason)
        external
        contractNotPaused
        onlyReviewer
        sampleExists(reference_)
    {
        Sample storage sample = samples[reference_];
        if (sample.status != SampleStatus.AwaitingReview || !sample.reportPending) {
            revert Laboratory__NoPendingReport();
        }
        if (bytes(reason).length == 0) revert Laboratory__InvalidInput();
        sample.reportPending = false;
        _setStatus(reference_, SampleStatus.Rejected);
        emit ResultRejected(_sampleKey(reference_), msg.sender, reason);
    }

    function approveResult(string calldata reference_)
        external
        contractNotPaused
        onlyReviewer
        sampleExists(reference_)
    {
        Sample storage sample = samples[reference_];
        if (
            sample.status != SampleStatus.AwaitingReview || sample.reportDigest == bytes32(0)
                || sample.result == SampleResult.None || !sample.reportPending
        ) {
            revert Laboratory__ResultNotApproved();
        }
        sample.reportPending = false;
        bytes32 key = _sampleKey(reference_);
        if (approvedVersions[key] == type(uint32).max) revert Laboratory__InvalidVersion();
        uint256 submittedAt = sample.updatedAt;
        _setStatus(reference_, SampleStatus.Approved);
        uint32 version = ++approvedVersions[key];
        sampleReports[key][version] = SampleReport(
            sample.reportDigest, sample.reportFormat, sample.result, msg.sender, submittedAt, block.timestamp
        );
        emit ResultApproved(key, version, msg.sender);
    }

    function releaseSample(string calldata reference_)
        external
        contractNotPaused
        onlyOperator
        sampleExists(reference_)
    {
        if (samples[reference_].status != SampleStatus.Approved) {
            revert Laboratory__ResultNotApproved();
        }
        _setStatus(reference_, SampleStatus.Released);
        samples[reference_].releasedAt = block.timestamp;
    }

    function getClientSamples(address clientAccount) external view returns (bytes32[] memory) {
        if (!operators[msg.sender] && msg.sender != clientAccount && msg.sender != owner) {
            revert Laboratory__Unauthorized();
        }
        return clientSamples[clientAccount];
    }

    function getSample(string calldata reference_)
        external
        view
        sampleExists(reference_)
        returns (Sample memory)
    {
        return samples[reference_];
    }

    function getSampleHistory(string calldata reference_)
        external
        view
        sampleExists(reference_)
        returns (SampleHistory[] memory)
    {
        return sampleHistories[_sampleKey(reference_)];
    }

    function getReport(string calldata reference_, uint32 version)
        external
        view
        sampleExists(reference_)
        returns (SampleReport memory)
    {
        bytes32 key = _sampleKey(reference_);
        if (version == 0 || version > approvedVersions[key]) revert Laboratory__InvalidVersion();
        return sampleReports[key][version];
    }

    function _sampleKey(string memory reference_) private pure returns (bytes32) {
        return keccak256(bytes(reference_));
    }

    function _appendHistory(bytes32 key, SampleStatus status) private {
        sampleHistories[key].push(SampleHistory(status, block.timestamp));
        AuditRecord storage record = auditRecords[key];
        if (!record.exists) {
            record.exists = true;
            record.createdAt = block.timestamp;
        }
        record.updatedAt = block.timestamp;
        record.status = status;
    }

    function _setStatus(string memory reference_, SampleStatus status) private {
        Sample storage sample = samples[reference_];
        SampleStatus oldStatus = sample.status;
        sample.status = status;
        sample.updatedAt = block.timestamp;
        if (status == SampleStatus.Collected) sample.collectedAt = block.timestamp;
        bytes32 key = _sampleKey(reference_);
        _appendHistory(key, status);
        emit SampleStatusChanged(key, oldStatus, status, msg.sender);
    }

    function _validTransition(SampleStatus _from, SampleStatus _to) private pure returns (bool) {
        if (_to == SampleStatus.None || _from == _to) return false;
        if (_from == SampleStatus.Registered) return _to == SampleStatus.Collected;
        if (_from == SampleStatus.Collected) return _to == SampleStatus.Processing;
        if (_from == SampleStatus.Processing) return _to == SampleStatus.RecollectionRequired;
        if (_from == SampleStatus.Rejected) return _to == SampleStatus.RecollectionRequired;
        if (_from == SampleStatus.RecollectionRequired) return _to == SampleStatus.Collected;
        return false;
    }

    function _requireActiveClient(address _account) private view {
        if (!clients[_account].exists || clients[_account].status != ClientStatus.Active) {
            revert Laboratory__InvalidClient();
        }
    }
}
