# SECURITY.md — SwarmWorld Core

Scope: `src/SwarmWorld.sol` (sha256 `ad5159f89fe8fadbf8fe7f3d7882ee1ab16f0dfdb36f496811cd1759b4e3bc28`),
`script/Deploy.s.sol`, the four test files and `foundry.toml`.

This document summarises every finding raised against the hardened implementation (the
self-review and one external report that preceded this assignment) plus the findings of this
final verification. It is a findings register, not an independent audit. The network's own
adversarial review before release is still required; tests passing are not an audit.

## Severity summary

| Severity | Open | Fixed | Accepted / informational |
| --- | --- | --- | --- |
| Critical | 0 | 0 | 0 |
| High | 0 | 1 (F13) | 0 |
| Medium | 0 | 0 | 2 (F2, F4) |
| Low | 0 | 0 | 3 (F7, F9, F10) |
| Informational | 0 | 2 (V1, V2) | 5 (F1, F3, F6, F8, F12) + 2 (V3, V4) |

**No unresolved Critical or High finding remains.**

## Findings carried from the hardened review

### F13 — High — Sponsor-only expiry could lock a settlement forever — FIXED
Reported externally after the first acceptance. `expireMission` previously required
`msg.sender == sponsor`; after the deadline `_live` blocks every role action, so an absent
sponsor (1 wei griefing mission, lost key, contract wallet) held the settlement's only mission
slot indefinitely, and `tick()` skipped that settlement. Fix in the hardened source:
`expireMission` is permissionless at or after the deadline; the refund is still credited only to
the recorded sponsor, and the caller receives nothing. Pinned by
`test_expireIsPermissionlessButRefundsOnlySponsor`, `test_abandonedMissionCannotLockSettlement`,
`test_activeMissionClearsAfterExpiredAndNewMissionOpens` and the
`invariant_activeMissionConsistency` invariant.

### F1 — Informational — Reentrancy through `claim()` — no issue
Balance and `totalClaimable` are zeroed before the ETH send; a re-entrant `claim()` sees zero and
reverts. No other function makes an external call. `test_reentrantClaimAttempt`.

### F2 — Medium (accepted) — Failed ETH send blocks only the recipient
If the receiver reverts, `claim()` reverts with `EthTransferFailed` and the balance stays
claimable. Only that account is affected. A contract-wallet worker that cannot receive ETH
strands its own share. `test_claimToRejectingReceiverRevertsAndKeepsBalance`.

### F3 — Informational — ETH conservation holds
No `receive`/`fallback`. Every terminal transition moves the reward from `totalEscrowed` to
`totalClaimable` exactly once. `invariant_ethConservation`, `invariant_escrowMatchesLiveMissions`,
`invariant_payoutAccounting`, `testFuzz_rewardSplitConservesEveryWei`, `testFuzz_payoutSplitExact`.

### F4 — Medium (accepted design) — PASSED missions never expire
A PASSED mission can be settled by anyone at any later time and cannot be expired. Rationale:
all four gates accepted the work and the settlement's energy and materials are frozen while the
mission is active, so the proposal stays valid. The alternative would let a sponsor race the
permissionless settlement to claw back an earned reward.
`test_passedMissionCannotExpireAndSettlesAfterDeadline`.

### F5 — Informational — Role actions after the deadline revert
`_live` rejects every role action once `block.timestamp >= deadline`, the same instant
`expireMission` becomes available; there is no window where both can act.
`test_threeDayExpiryBoundary`, `testFuzz_noRoleActionAtOrAfterDeadline`.

### F6 — Informational — Bounds re-checked at settlement
`_validateOutcome` runs at submit and again at settle. Kept as a defensive invariant.

### F7 — Low (noted) — `EnergyWouldExceedMax` is unreachable today
A mission opens only when energy < 300 and the maximum gain is 300, so resulting energy is at
most 599. The bound is enforced anyway. `test_resultingEnergyCannotExceed1000`.

### F8 — Informational — Seat IDs are provenance only
Stored, required distinct, hashed into `proofHash`, emitted; never authenticated. Seat 0 is
accepted. `test_seatIdsAreProvenanceOnlyAndNeverAuthorise`, `testFuzz_seatIdsAnyDistinctValuesAccepted`.

### F9 — Low (accepted) — Timestamp dependence
`tick()` and deadlines compare `block.timestamp`. Validators can shift it by seconds; the
boundaries are one day and three days.

### F10 — Low (accepted) — Sponsor self-dealing
A sponsor may name four addresses they control and pass their own mission. Only the sponsor's own
ETH is involved; the world-state change is bounded by the outcome limits.

### F12 — Informational — Compiler lints only
`block-timestamp` lints and one `unsafe-typecast` on `uint64(block.timestamp + 3 days)`, which
cannot truncate before year 5.8e11. No compiler errors or warnings. The lint about reading
`block.timestamp` across a `vm.warp` mutation is in test code only.

## Findings of this final verification

### V1 — Informational — Invariant tests were missing from the hardened tree — FIXED
The hardened artifacts contained unit and fuzz tests but no stateful invariant suite, so the
gate "invariant tests pass" could not be evaluated. Added `test/SwarmWorld.invariants.t.sol`:
a guarded handler drives open / submit / test / review / verify / settle / expire / tick / warp /
claim across all three settlements and six actors, and nine invariants check ETH conservation,
escrow accounting, exact payout split per account, resource bounds, frozen fields, active-mission
pointer consistency in both directions, terminal-state finality, mission-ID density from 1, and
tick cadence. 64 runs × depth 48 = 3072 calls, 0 reverts, all invariants hold.

### V2 — Informational — SECURITY.md was missing from the hardened tree — FIXED
The hardened tree carried `REVIEW.md`. This file is the required `SECURITY.md`; it supersedes
that review in this tree.

### V3 — Informational — Hardened tree shipped an ERC-20 beside SwarmWorld — EXCLUDED
The hardened repository contained `src/LaunchToken.sol`, a fixed-supply ERC-20 demanded by the
IMD launch factory for a different pipeline, plus `launch.json`. SwarmWorld never referenced it
(verified: no import, no address, no token call in `src/SwarmWorld.sol`; ABI has no token
function). Because this assignment's architecture rule is "no ERC-20, no token", the token, its
tests, its ABI and the launch manifest are **not** carried into this tree. `SwarmWorld.sol` itself
was already compliant and is byte-identical to the hardened source.

### V4 — Informational — proofHash has no chain / instance domain — ACCEPTED, DOCUMENTED
`proofHash` commits to missionId, settlementId, world-state-before, energyGain, materialsCost,
the four evidence hashes and the four seat IDs (all thirteen fields verified independently
significant by `test_proofHashCommitsToEveryInput`). It does not include `chainId`,
`address(this)` or a version tag, so the same evidence on two instances yields the same
commitment (`test_proofHashHasNoInstanceDomain`). The task instructs to preserve domain
separation only if the hardened version added it; it did not, and the protocol is not
redesigned here. Consumers that need instance binding must pair the hash with the
`MissionSettled` event's emitting address and chain. The hash is a commitment to recorded
evidence, not a proof that the evidence is true.

## Bytecode-level checks

- Runtime bytecode contains no `DELEGATECALL`, `CALLCODE`, `SELFDESTRUCT` or `CREATE` opcodes.
- No immutables, no library links: on-chain code must equal compiled `deployedBytecode`.
- ABI exposes no owner, admin, pause, upgrade, sweep or token entry points; no `receive`/`fallback`.

## Out of scope / not tested here

- Real Sepolia deployment (not performed; see `DEPLOYMENT.md`).
- Correctness of any off-chain artifact behind `builderArtifactHash`, `testHash`, `reviewHash`
  or `verificationHash`.
- Economic incentives of the four-role design beyond the fund-safety properties above.
