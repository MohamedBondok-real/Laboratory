# Laboratory Smart Contract

A role-based Solidity smart contract for managing laboratory samples, clients, reports, approvals, and sample lifecycle history on-chain.

The project implements a controlled laboratory workflow where **owners, operators, reviewers, and clients** have different permissions. Samples move through predefined lifecycle states, while reports are submitted, reviewed, approved or rejected, and released.

## Features

- Role-based access control
  - Owner
  - Operator
  - Reviewer
  - Client
- Client registration and management
- Client metadata stored as a `bytes32` hash
- Laboratory sample registration
- Sample types and priorities
- Controlled sample status transitions
- Report submission using a report digest
- Reviewer approval and rejection
- Versioned approved reports
- Sample history and audit records
- Contract pause functionality
- Ownership transfer
- Custom Solidity errors
- Events for important state changes
- Access-controlled client sample queries
- Foundry unit and fuzz testing

## Sample Lifecycle

Samples follow a controlled workflow:

```text
Registered
    ↓
Collected
    ↓
Processing
    ↓
AwaitingReview
    ├── Approved → Released
    │
    └── Rejected
          ↓
    RecollectionRequired
          ↓
       Collected
          ↓
      Processing
```

The contract rejects unsupported status transitions.

## Roles

### Owner

The owner is responsible for administrative operations:

- Registering clients
- Updating client status
- Assigning and revoking operators
- Assigning and revoking reviewers
- Pausing and unpausing the contract
- Transferring ownership

### Operator

Operators manage the laboratory workflow:

- Register samples for clients
- Update sample status
- Submit laboratory reports
- Release approved samples

### Reviewer

Reviewers are responsible for reviewing submitted reports:

- Approve reports
- Reject reports with a required reason

### Client

Active clients can:

- Register their own samples
- Update their metadata
- Access their own sample identifiers

Inactive or suspended clients cannot perform client-level operations.

## Contract Structure

### `Laboratory.sol`

The main smart contract contains:

- State variables
- Roles and permissions
- Custom errors
- Enums
- Structs
- Mappings
- Events
- Client management
- Sample management
- Report management
- Audit history
- Status transition validation

### `Laboratory.t.sol`

The Foundry test suite covers:

- Constructor and ownership
- Role management
- Ownership transfer
- Zero-address validation
- Role conflicts
- Client registration
- Client metadata updates
- Client status management
- Sample registration
- Sample indexing
- Access control
- Contract pausing
- Sample status transitions
- Report submission
- Report approval
- Report rejection
- Report versioning
- Sample release
- Audit history
- Recollection workflows
- Invalid inputs and invalid states
- Fuzz testing for valid sample types, priorities, report formats, and results

## Data Model

### Sample Types

```solidity
enum SampleType {
    None,
    Blood,
    Urine,
    Saliva,
    Tissue,
    Other
}
```

### Sample Priorities

```solidity
enum SamplePriority {
    None,
    Low,
    Medium,
    High,
    Urgent
}
```

### Sample Results

```solidity
enum SampleResult {
    None,
    Negative,
    Positive,
    Inconclusive
}
```

### Report Formats

```solidity
enum SampleReportFormat {
    None,
    PDF,
    JSON,
    XML
}
```

### Client Types

```solidity
enum ClientType {
    None,
    Individual,
    Organization,
    Government
}
```

## Security & Validation

The contract uses custom errors for validation and access control, including:

- `Laboratory__Unauthorized`
- `Laboratory__ZeroAddress`
- `Laboratory__InvalidReference`
- `Laboratory__RecordAlreadyExists`
- `Laboratory__RecordNotFound`
- `Laboratory__InvalidStatusTransition`
- `Laboratory__ResultNotApproved`
- `Laboratory__InvalidReportDigest`
- `Laboratory__InvalidVersion`
- `Laboratory__ContractPaused`
- `Laboratory__InvalidClient`
- `Laboratory__InvalidInput`
- `Laboratory__NoPendingReport`
- `Laboratory__RoleConflict`

The contract also prevents an address from simultaneously being an operator and reviewer.

## Report Approval

Reports are not immediately considered approved after submission.

The workflow is:

```text
Operator
   ↓
Submit Report
   ↓
AwaitingReview
   ↓
Reviewer
   ├── Approve → Approved
   │
   └── Reject → Rejected
```

Approved reports receive a version number and are stored in the contract history.

## Audit & History

Each sample maintains a history of status changes.

The contract records:

- Status
- Timestamp
- Current audit status
- Creation time
- Last update time

Sample references are converted into `bytes32` identifiers using:

```solidity
keccak256(bytes(reference))
```

This identifier is used for audit records, sample history, report versions, and client sample indexes.

## Testing

The project uses **Foundry** and `forge-std/Test.sol`.

The test suite includes both standard unit tests and fuzz tests.

Examples of tested scenarios:

```text
Authorization
Role conflicts
Client validation
Sample registration
Invalid sample references
Duplicate samples
Status transitions
Report validation
Report approval
Report rejection
Report versioning
Sample release
Pause functionality
Audit history
Fuzz testing
```

## Fuzz Testing

The test suite includes fuzz tests for:

- Non-empty sample references
- All valid sample types
- All valid sample priorities
- All valid report formats
- All valid report results

This helps verify that the contract behaves correctly across a wider range of valid inputs.

## Tech Stack

- Solidity `^0.8.31`
- Foundry
- Forge
- `forge-std`
- Ethereum Virtual Machine (EVM)

## Project Structure

```text
.
├── src/
│   └── Laboratory.sol
│
├── test/
│   └── Laboratory.t.sol
│
└── README.md
```

## Getting Started

Clone the repository and install the Foundry dependencies.

Then compile the contracts:

```bash
forge build
```

Run the test suite:

```bash
forge test
```

Run tests with detailed output:

```bash
forge test -vv
```

Run fuzz tests with increased runs:

```bash
forge test --fuzz-runs 1000
```

## Important Note

This project stores sample references, metadata hashes, report digests, statuses, timestamps, and other workflow information on-chain.

The contract does **not** store the actual laboratory report files directly. Instead, reports are represented by a `bytes32` digest and a declared format such as PDF, JSON, or XML.

For production use, additional security auditing, privacy considerations, access-control review, and off-chain storage integration would be required.

## License

This project is licensed under the MIT License.
