# SwarmWorld Core — final verification tree

A persistent on-chain world where independent workers submit, test, review and verify missions
before world state changes. One standalone Foundry project, Solidity 0.8.26, one contract.

This tree is the **final-verify + Sepolia-deploy** assignment for SwarmWorld. It carries the
hardened `SwarmWorld.sol` forward unchanged, adds the artifacts the deployment gate requires
(invariant tests, a final-verification suite, `SECURITY.md`, `DEPLOYMENT.md`) and records the
gate outcome. **No Sepolia deployment was performed** — see `DEPLOYMENT.md` for the failing gates
and the exact hand-off for the key holder. No address or transaction hash is claimed anywhere.

## Architecture (as required, and as verified)

| Requirement | Status |
| --- | --- |
| one `SwarmWorld.sol` | `src/SwarmWorld.sol` is the only contract in `src/` |
| native ETH only | rewards enter through payable `openEnergyMission`, leave through `claim()` |
| no ERC-20 / no token | no token code, import or address anywhere in `src/` |
| no owner / admin | no privileged address; every mutating function is either role-gated by the mission's four payout addresses or permissionless |
| no upgradeability | no proxy, no `DELEGATECALL`, no initializer, no immutables |
| no pausing | no pause state or guard |
| no external contracts | the only external call is the ETH send in `claim()` to `msg.sender` |

The hardened tree this was taken from also contained `src/LaunchToken.sol`, an ERC-20 that the
IMD project-launch factory demanded for a *different* pipeline. SwarmWorld never referenced it.
It is **not** carried into this tree because the architecture rule for this assignment is
"no ERC-20, no token". See `DEPLOYMENT.md` § Provenance.

## Layout

| Path | Contents |
| --- | --- |
| `src/SwarmWorld.sol` | World, missions, rewards (byte-identical to the hardened source) |
| `script/Deploy.s.sol` | Deploys exactly one SwarmWorld; reads no keys; chain guard |
| `test/SwarmWorld.t.sol` | Hardened unit + fuzz suite (53 tests, 3 fuzz) |
| `test/SwarmWorld.verify.t.sol` | Final-verification suite: one test per checklist item (18 tests, 3 fuzz) |
| `test/SwarmWorld.invariants.t.sol` | Stateful invariant suite with a guarded handler (9 invariants) |
| `test/Deploy.t.sol` | Calls the deploy function and chain guard directly (4 tests) |
| `docs/abi/SwarmWorld.json` | Exported ABI, verified equal to the build ABI |
| `lib/forge-std` | Vendored forge-std 1.16.2 as ordinary files (no submodule) |
| `SECURITY.md` | Findings summary and disposition |
| `DEPLOYMENT.md` | Verification record, bytecode hashes, gate outcome, deployer hand-off |

## World rules

Three settlements with fixed IDs. Resources `energy`, `food`, `materials`, `knowledge` are
bounded 0..1000; `stability` is bounded 0..100.

| ID | Name | energy | food | materials | knowledge | population | stability |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | Genesis City | 500 | 500 | 500 | 500 | 100 | 80 |
| 1 | Iron Valley | 420 | 550 | 700 | 350 | 100 | 75 |
| 2 | Nova Port | 120 | 420 | 300 | 180 | 100 | 75 |

### Time

`tick()` is permissionless and executes at most once per 24 hours measured from the last
accepted tick (`lastTickAt`, initialised to deployment time). It succeeds at exactly
`lastTickAt + 1 days` and reverts with `TickTooEarly` one second earlier. Each tick reduces
energy by 25, saturating at zero, for every settlement without an active mission, and emits
`EnergyCrisis` for each settlement whose energy is strictly below 300 afterwards. Missed days
are not caught up.

### Missions

One mission type, `ENERGY_REPAIR`. `openEnergyMission(settlementId, roles)` is payable; anyone
may call it for a settlement with energy < 300 and no active mission, with `msg.value > 0` as
the escrowed reward, four nonzero pairwise-distinct payout addresses and four pairwise-distinct
`uint32` seat IDs. Seat IDs are provenance metadata only: the contract never authenticates
them; the payout addresses are the authorisation.

Mission IDs start at 1; 0 is the "no mission" sentinel and is rejected everywhere. Lifetime is
3 days from creation. Exactly one active mission per settlement; the slot is freed on SETTLED,
FAILED or EXPIRED.

States: `OPEN, WORKING, VERIFYING, PASSED, FAILED, SETTLED, EXPIRED`.

| Step | Caller | From | To |
| --- | --- | --- | --- |
| `submitOutcome(id, energyGain, materialsCost, artifactHash)` | builder | OPEN | WORKING |
| `submitTest(id, testHash, pass)` | tester | WORKING | WORKING (pass) or FAILED |
| `submitReview(id, reviewHash, pass)` | reviewer | WORKING after test pass | VERIFYING or FAILED |
| `verifyOutcome(id, verificationHash, pass)` | verifier | VERIFYING | PASSED or FAILED |
| `settleMission(id)` | anyone | PASSED | SETTLED |
| `expireMission(id)` | anyone | OPEN, WORKING, VERIFYING at/after deadline | EXPIRED |

Outcome bounds: 200 <= energyGain <= 300, materialsCost <= 100, resulting energy <= 1000,
materials >= cost. They are checked at submission and again at settlement.

Role actions revert with `MissionDeadlinePassed` once `block.timestamp >= deadline`, the same
instant at which `expireMission` becomes available. A PASSED mission cannot expire and can be
settled at any later time.

### Settlement and proof hash

`settleMission` adds `energyGain` to energy, subtracts `materialsCost` from materials, clears the
active-mission pointer, marks the mission SETTLED, stores `worldStateBefore = worldStateHash()`
taken immediately before the write, stores `proofHash`, and credits the four workers.
Food, knowledge, population and stability are never modified by anything.

```
proofHash = keccak256(abi.encode(
    missionId, settlementId, worldStateBefore, energyGain, materialsCost,
    builderArtifactHash, testHash, reviewHash, verificationHash,
    builderSeat, testerSeat, reviewerSeat, verifierSeat))
```

`computeProofHash(...)` is a public pure function so the value can be recomputed off-chain.
The hash is a **deterministic commitment to the recorded evidence**. It does not prove that the
off-chain artifacts behind those hashes are correct or that the seats did the work. The
hardened source does not include `chainId`, `address(this)` or a version domain; the same
evidence replayed on another instance yields the same commitment. This is pinned by
`test_proofHashHasNoInstanceDomain` and left unchanged because this assignment does not
redesign the protocol.

### Rewards

Pull payments only. Terminal transitions credit `claimable[account]`; `claim()` zeroes the
balance before sending and reverts if the send fails, so a rejecting receiver blocks only
itself.

| Outcome | Credit |
| --- | --- |
| SETTLED | builder 50%, tester 15%, reviewer 15%, verifier the remainder (20% plus rounding dust) |
| FAILED / EXPIRED | sponsor receives the full reward |

The contract has no `receive` or `fallback`, so `address(this).balance == totalEscrowed +
totalClaimable` at all times. This is an invariant in the stateful suite.

## Building and testing offline

```
forge build --offline
forge test --offline
forge fmt --check
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
```

`foundry.toml` pins `solc = "0.8.26"`, optimizer on with 200 runs, `evm_version = "paris"`,
`bytecode_hash = "none"`, `ffi = false`, `fs_permissions = []`, fuzz 256 runs, invariants
64 runs × depth 48. Tests read no environment variables and pass in any order.

## Deployment parameters

- Contract: `SwarmWorld`, nonpayable constructor, **no constructor arguments**, no
  post-deployment configuration, no owner to transfer.
- Target chain: Sepolia, chain ID 11155111.
- Script: `script/Deploy.s.sol:Deploy`. `run()` reads exactly one environment variable,
  `EXPECTED_CHAIN_ID`, and when it is nonzero requires it to equal `block.chainid` and to be
  31337 or 11155111. It never reads a private key; the signer is supplied by forge flags.
- Expected runtime bytecode keccak256 of the reviewed build:
  `0x25ce5b5771286bb2d8bdd9802435efe3bf6770353c2fd1076af17c952eb2f8b0`. The contract has no
  immutables, so the on-chain code must equal the compiled `deployedBytecode` byte for byte.

Full hand-off and verification commands are in `DEPLOYMENT.md`.

## Operational responsibilities and assumptions

- Someone must call `tick()` daily. Nothing is automatic; a missed day is lost.
- Someone must call `expireMission` on missions that pass their deadline without reaching
  PASSED. Anyone may. Until then the settlement stays busy and its ticks are skipped.
- The sponsor chooses the four workers and seat IDs. The contract enforces distinctness, not
  competence or independence. A sponsor can name four addresses they control; the reward is
  then paid to themselves, which harms no one else, but the resulting world-state change is only
  as trustworthy as the sponsor.
- The builder alone chooses `energyGain` and `materialsCost` within bounds; tester, reviewer
  and verifier gate whether the proposal is applied.
- Timestamps come from `block.timestamp`; second-level drift is irrelevant at day-scale.
- There is no way to recover ETH except `claim()` by its rightful owner. No admin sweep.
- Mission storage grows without bound (one struct per mission, never deleted). No loop over
  missions exists, so this affects only storage cost, not liveness.
- This assignment did not deploy anything and never held a key.
