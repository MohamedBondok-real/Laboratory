# Laboratory sample tracking contract

This Foundry project contains a Solidity contract for client registration, sample processing, report review, and sample audit history.

## Workflow

1. The owner registers clients and assigns operator and reviewer roles.
2. An active client registers a sample, or an operator registers one for an active client.
3. An operator moves the sample through `Registered` -> `Collected` -> `Processing`.
4. The operator submits a report digest while the sample is processing. Submission moves it to `AwaitingReview`.
5. A reviewer approves or rejects the pending report. Rejection requires a reason and emits it in an event.
6. An operator releases an approved sample. A rejected sample may be marked for recollection and processed again.

Status changes are timestamped in sample history. The contract exposes client sample lists and counts, a total sample count, the latest audit record, and approved report versions.

## Roles and visibility

- The owner manages clients, roles, pause state, and ownership transfer.
- Operators manage sample processing and release.
- Reviewers approve or reject pending reports. Reviewer and operator roles cannot overlap.
- Active clients can register samples and read their own sample identifiers.
- Owners and operators can read any client's sample identifiers.

Contract storage and emitted events are public on-chain. The contract stores a client metadata hash and report digest, not client names, contact details, or report contents. Keep private source material off-chain and use opaque, non-identifying references and cryptographic hashes. Hashes and references can still reveal information if they are predictable or linkable.

## Development

Build with `forge build` and run the suite with `forge test`.
