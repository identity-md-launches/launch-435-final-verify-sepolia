# DEPLOYMENT.md — SwarmWorld final verification and Sepolia gate record

Date of verification: 2026-09-28. Toolchain: forge 1.8.3 (cae51ad), solc 0.8.26+commit.8a97fa7a.

## Outcome

**NOT DEPLOYED.** All build, test and architecture gates pass. Two gates that the task requires
before any broadcast cannot be satisfied from this assignment:

| Gate | Result | Evidence |
| --- | --- | --- |
| `forge build` succeeds | PASS | `Compiler run successful!`, 26 files, solc 0.8.26 |
| all unit tests pass | PASS | 75 unit/fuzz tests, 0 failed (see summary below) |
| fuzz tests pass | PASS | 6 fuzz tests × 256 runs, 0 failed |
| invariant tests pass | PASS | 9 invariants, 64 runs × depth 48 = 3072 calls, 0 reverts |
| `forge fmt --check` | PASS | clean |
| no unresolved Critical/High finding | PASS | `SECURITY.md`: 0 open Critical, 0 open High |
| architecture matches requirements | PASS | one `SwarmWorld.sol`, native ETH, no token, no owner, no proxy, no pause, no external contracts (the hardened tree's sibling ERC-20 is excluded, see Provenance) |
| exact repository URL + exact commit hash verified before deploy | **BLOCKED** | this workspace has **no git remote** and its only commit is `0243d7d Empty workspace`; the commit containing this tree is created by the IMD submission pipeline *after* this assignment ends, so it cannot be inspected here |
| deployer authority | **BLOCKED** | no signing key, keystore or funded wallet exists on this seat, and the assignment reference states it "does not authorize transactions or control a funded wallet" |

Because the last two gates fail, no transaction was sent. **No Sepolia address, transaction
hash or on-chain bytecode is claimed.** The remainder of this file records everything an
independent person needs to complete the chain

    reviewed source → exact commit → passing tests → deployment transaction → deployed bytecode

once the commit exists and a key holder broadcasts.

## Reviewed source and build identity

| Item | Value |
| --- | --- |
| Source file | `src/SwarmWorld.sol` |
| Source sha256 (file bytes) | `ad5159f89fe8fadbf8fe7f3d7882ee1ab16f0dfdb36f496811cd1759b4e3bc28` |
| Source keccak256 (solc metadata `sources`) | `0x58ec6208c7d66285f08ad34a0de0a7eab1c7f2df48fa749ac56083df3996c883` |
| Compiler | solc `0.8.26+commit.8a97fa7a` |
| Optimizer | enabled, 200 runs, `viaIR = false` |
| EVM version | `paris` |
| Metadata | `bytecodeHash = "none"` (runtime ends with the 10-byte solc-version CBOR tail only) |
| Constructor arguments | none |
| Immutables / library links | none / none |
| Creation bytecode | 10675 bytes, keccak256 `0x3a0848f7310c5660f2ffb106dd48351d27bd489b256f0f0adefffcf5152ca87d` |
| **Runtime (deployed) bytecode** | 10362 bytes, **keccak256 `0x25ce5b5771286bb2d8bdd9802435efe3bf6770353c2fd1076af17c952eb2f8b0`** |
| ABI | `docs/abi/SwarmWorld.json`, verified equal (sorted JSON) to the build ABI |
| Deploy script sha256 | `5f427aa51184afb59414c56cd6e1960dc15c5d43a85b7e908d16cc9645358451` (`script/Deploy.s.sol`) |
| foundry.toml sha256 | `292288698e95b8e03c55e92f50e732e6c8a6ec281f06cc92b99bf84c878b41d4` |

Reproduce the hashes from a clean checkout, with no network:

```
forge build --offline
forge inspect SwarmWorld deployedBytecode | tr -d '\n' | cast keccak
#   -> 0x25ce5b5771286bb2d8bdd9802435efe3bf6770353c2fd1076af17c952eb2f8b0
forge inspect SwarmWorld bytecode | tr -d '\n' | cast keccak
#   -> 0x3a0848f7310c5660f2ffb106dd48351d27bd489b256f0f0adefffcf5152ca87d
sha256sum src/SwarmWorld.sol
#   -> ad5159f8…bc28
```

Because `bytecode_hash = "none"` and the compiler, optimizer and EVM version are pinned, the
build is reproducible byte for byte on any machine with solc 0.8.26.

## Provenance of the hardened source

The workspace assigned to this task was empty. The hardened SwarmWorld implementation was
located on the same seat in the workspace of the preceding task lineage:

| Item | Value |
| --- | --- |
| Source workspace | `…/work/7d502282-5db6-4f52-99bc-e3bf9e8fdb48/a282c298-2504-4f5e-9773-193d2a528728` |
| Its HEAD commit | `3dcc7e3b99ff091b0e50df9b928e94a1fa9d9b18` (`imd a282c298-…`), clean working tree, no remote |
| Its `src/SwarmWorld.sol` sha256 | `ad5159f8…bc28` — **identical** to this tree |
| Its suite at that commit (exported with `git archive`, run in `/tmp`) | 66 passed / 0 failed; `forge fmt --check` clean |

Carried over unchanged: `src/SwarmWorld.sol`, `script/Deploy.s.sol`, `test/SwarmWorld.t.sol`,
`test/Deploy.t.sol`, `docs/abi/SwarmWorld.json`, `remappings.txt`, `.gitignore`, `lib/forge-std`
(40 ordinary files, version 1.16.2). `foundry.toml` is the same file plus an `[invariant]`
section. **Not** carried over: `src/LaunchToken.sol` (ERC-20), `test/LaunchToken.t.sol`,
`docs/abi/LaunchToken.json`, `launch.json`, `REVIEW.md` (superseded by `SECURITY.md`).

The exact repository URL and commit hash of *this* tree will be assigned by the submission
pipeline; the source and bytecode hashes above are the stable identifiers to match against it.

## Test summary (this tree, `forge test --offline`)

| Suite | Tests | Result |
| --- | --- | --- |
| `test/Deploy.t.sol:DeployTest` | 4 | pass |
| `test/SwarmWorld.t.sol:SwarmWorldTest` | 53 (3 fuzz) | pass |
| `test/SwarmWorld.verify.t.sol:SwarmWorldVerifyTest` | 18 (3 fuzz) | pass |
| `test/SwarmWorld.invariants.t.sol:SwarmWorldInvariants` | 9 invariants (1 reported entry) | pass, 3072 calls, 0 reverts |
| **Total** | **76 reported, 0 failed, 0 skipped** | |

Fuzz configuration: 256 runs per fuzz test. Invariant configuration: 64 runs, depth 48,
`fail_on_revert = false` (handler actions are pre-guarded and recorded 0 reverts).

### Checklist → test mapping

| Requirement | Test(s) |
| --- | --- |
| activeMission clears after SETTLED | `test_activeMissionClearsAfterSettledAndNewMissionOpens`, `test_successfulStateTransition` |
| activeMission clears after FAILED | `test_activeMissionClearsAfterFailedAndNewMissionOpens`, `test_failedTest` |
| activeMission clears after EXPIRED | `test_activeMissionClearsAfterExpiredAndNewMissionOpens`, `test_threeDayExpiryBoundary` |
| new mission opens after FAILED/EXPIRED cleanup | the three tests above, `test_oneActiveMissionPerSettlement`, `test_abandonedMissionCannotLockSettlement` |
| no actions after the 3-day deadline | `testFuzz_noRoleActionAtOrAfterDeadline`, `test_roleActionsRevertAfterDeadline`, `test_threeDayExpiryBoundary` |
| terminal missions cannot transition again | `test_settledMissionCannotTransitionAgain`, `test_failedMissionCannotTransitionAgain`, `test_expiredMissionCannotTransitionAgain`, `invariant_terminalMissionsStayTerminal` |
| settlement requires PASSED | `test_settlementRequiresPassedFromEveryNonPassedState`, `test_wrongWorkflowOrder` |
| world state cannot change before settlement | `test_worldStateFrozenUntilSettlementIncludingTicks`, `test_worldStateUnchangedBeforeSettlement` |
| settlement changes only energy and materials | `test_settlementChangesOnlyEnergyAndMaterialsOfItsSettlement`, `invariant_onlyEnergyAndMaterialsChange` |
| resources within bounds | `invariant_resourceBounds`, `testFuzz_outcomeBoundsAreEnforced`, `test_materialsMustBeAvailable` |
| tick exact 24-hour boundary | `test_tickExact24hBoundary`, `testFuzz_tickNeverUnderflowsAndRespectsBoundary`, `invariant_tickCadence` |
| energy cannot underflow | `test_energyCannotUnderflow`, `test_energyExactly25GoesToZero`, `testFuzz_tickNeverUnderflowsAndRespectsBoundary` |
| one active mission per settlement | `test_oneActiveMissionPerSettlement`, `invariant_activeMissionConsistency` |
| missionId zero / sentinel safe | `test_missionIdZeroIsNeverAMission`, `invariant_missionIdSentinel`, `test_unknownMissionReverts` |
| unauthorized role calls fail | `test_unauthorizedRoleCalls`, `test_seatIdsAreProvenanceOnlyAndNeverAuthorise` |
| four role addresses distinct and nonzero | `test_roleAddressesAndSeatsMustAllBeDistinctAndNonzero`, `test_fourRoleAddressesMustBeNonzero`, `test_fourRoleAddressesMustBeDistinct` |
| four seat IDs distinct | `test_fourSeatIdsMustBeDistinct`, `test_roleAddressesAndSeatsMustAllBeDistinctAndNonzero` |
| seat IDs are provenance metadata only | `test_seatIdsAreProvenanceOnlyAndNeverAuthorise`, `testFuzz_seatIdsAnyDistinctValuesAccepted` |
| reward accounting conserves the complete reward | `testFuzz_payoutSplitExact`, `testFuzz_rewardSplitConservesEveryWei`, `invariant_ethConservation`, `invariant_payoutAccounting` |
| payout 50 / 15 / 15 / remainder incl. dust | `testFuzz_payoutSplitExact`, `test_rewardSplit`, `test_tinyRewardRoundsEntirelyToVerifier` |
| no double settlement / refund / claim | `test_noDoubleSettlementRefundOrClaim`, `test_doubleSettlement`, `test_doubleRefund`, `test_doubleClaim` |
| claim safe against reentrancy | `test_reentrantClaimAttempt` |
| proofHash deterministic, commits to all 13 fields | `test_proofHashCommitsToEveryInput`, `test_deterministicProofHash` |
| proofHash domain (none in hardened source; preserved as-is) | `test_proofHashHasNoInstanceDomain` |
| script deploys once, chain guard | `test_deployProducesFreshWorld`, `test_checkChain*`, offline dry run below |

Script dry runs (offline, default Anvil chain 31337):

```
EXPECTED_CHAIN_ID=0        forge script script/Deploy.s.sol:Deploy --offline   # Script ran successfully, one SwarmWorld
EXPECTED_CHAIN_ID=11155111 forge script script/Deploy.s.sol:Deploy --offline   # reverts UnexpectedChain(11155111, 31337)
```

## Hand-off: how the key holder deploys and how anyone verifies

Preconditions: the submission commit for this tree exists and its `src/SwarmWorld.sol` has
sha256 `ad5159f8…bc28`; `forge build --offline` at that commit reproduces runtime keccak256
`0x25ce…f8b0`. Do not deploy from any other tree.

Deploy (the script reads no key; supply the signer through forge flags such as `--ledger`,
`--account <keystore-name>` or `--interactive`):

```
EXPECTED_CHAIN_ID=11155111 forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://ethereum-sepolia-rpc.publicnode.com \
  --broadcast <signer flags>
```

Record from the broadcast: contract address, transaction hash, chain ID (must be 11155111),
and the deploying commit hash. Then verify, from any machine:

```
# 1. on-chain runtime bytecode equals the reviewed build
cast code <ADDRESS> --rpc-url https://ethereum-sepolia-rpc.publicnode.com | tr -d '\n' | cast keccak
#   must print 0x25ce5b5771286bb2d8bdd9802435efe3bf6770353c2fd1076af17c952eb2f8b0

# 2. the creation transaction carried exactly the reviewed creation bytecode (no constructor args)
cast tx <TXHASH> input --rpc-url https://ethereum-sepolia-rpc.publicnode.com | tr -d '\n' | cast keccak
#   must print 0x3a0848f7310c5660f2ffb106dd48351d27bd489b256f0f0adefffcf5152ca87d

# 3. the receipt created that address on chain 11155111
cast receipt <TXHASH> --rpc-url https://ethereum-sepolia-rpc.publicnode.com   # contractAddress == <ADDRESS>
cast chain-id --rpc-url https://ethereum-sepolia-rpc.publicnode.com          # 11155111

# 4. fresh world state and tick anchor
cast call <ADDRESS> "nextMissionId()(uint256)" --rpc-url …   # 1
cast call <ADDRESS> "lastTickAt()(uint256)"    --rpc-url …   # deployment block timestamp
```

Optional source verification on Etherscan (needs an API key; not required for the bytecode
check above):

```
forge verify-contract <ADDRESS> src/SwarmWorld.sol:SwarmWorld --chain sepolia \
  --compiler-version 0.8.26 --num-of-optimizations 200 --evm-version paris --watch
```

## After deployment: operational responsibilities

There is no admin. The only ongoing duties are permissionless: call `tick()` once every 24
hours, and call `expireMission` for missions that miss the 3-day deadline. Workers withdraw with
`claim()`. Nothing else can be configured, paused or upgraded; if a defect is found, the only
remedy is a new deployment and social migration.
