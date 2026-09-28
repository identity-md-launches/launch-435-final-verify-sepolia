// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {SwarmWorld} from "../src/SwarmWorld.sol";

/// @dev Stateful handler. Every call the fuzzer makes goes through here, so the ghost variables are
///      a complete record of what should have happened. Actions are guarded so that most calls
///      succeed; the unit suite covers the revert paths one by one.
contract SwarmWorldHandler is CommonBase, StdCheats, StdUtils {
    SwarmWorld public immutable world;

    address[6] internal _actors;
    uint32[4] internal _seats = [uint32(101), 202, 303, 404];

    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;
    uint256 public ghostOpened;
    uint256 public ghostSettled;
    uint256 public ghostFailed;
    uint256 public ghostExpired;
    uint256 public ghostTicks;

    mapping(uint256 => bool) public ghostIsTerminal;
    mapping(uint256 => SwarmWorld.MissionState) public ghostTerminalState;
    mapping(address => uint256) public ghostCredited;
    mapping(address => uint256) public ghostWithdrawnBy;

    constructor(SwarmWorld world_) {
        world = world_;
        _actors[0] = makeAddr("sponsorA");
        _actors[1] = makeAddr("sponsorB");
        _actors[2] = makeAddr("builder");
        _actors[3] = makeAddr("tester");
        _actors[4] = makeAddr("reviewer");
        _actors[5] = makeAddr("verifier");
    }

    function actorCount() external pure returns (uint256) {
        return 6;
    }

    function actor(uint256 i) external view returns (address) {
        return _actors[i];
    }

    function _roles() internal view returns (SwarmWorld.Roles memory r) {
        r = SwarmWorld.Roles({
            builder: _actors[2],
            tester: _actors[3],
            reviewer: _actors[4],
            verifier: _actors[5],
            builderSeat: _seats[0],
            testerSeat: _seats[1],
            reviewerSeat: _seats[2],
            verifierSeat: _seats[3]
        });
    }

    function _active(uint8 seed) internal view returns (uint256 id, SwarmWorld.Mission memory m) {
        uint8 sid = uint8(bound(seed, 0, 2));
        id = world.getSettlement(sid).activeMission;
        if (id != 0) m = world.getMission(id);
    }

    function _recordTerminal(uint256 id, SwarmWorld.MissionState st, SwarmWorld.Mission memory m) internal {
        ghostIsTerminal[id] = true;
        ghostTerminalState[id] = st;
        if (st == SwarmWorld.MissionState.SETTLED) {
            uint256 b = m.reward * 5000 / 10_000;
            uint256 t = m.reward * 1500 / 10_000;
            uint256 r = m.reward * 1500 / 10_000;
            ghostCredited[m.roles.builder] += b;
            ghostCredited[m.roles.tester] += t;
            ghostCredited[m.roles.reviewer] += r;
            ghostCredited[m.roles.verifier] += m.reward - b - t - r;
            ghostSettled++;
        } else {
            ghostCredited[m.sponsor] += m.reward;
            if (st == SwarmWorld.MissionState.FAILED) ghostFailed++;
            else ghostExpired++;
        }
    }

    // ------------------------------------------------------------------ actions

    function open(uint8 sSeed, uint96 rewardSeed, uint8 sponsorSeed) external {
        uint8 sid = uint8(bound(sSeed, 0, 2));
        uint256 reward = bound(rewardSeed, 1, 10 ether);
        address sp = _actors[sponsorSeed % 2];
        SwarmWorld.Settlement memory s = world.getSettlement(sid);
        if (s.activeMission != 0 || s.energy >= world.ENERGY_CRISIS_THRESHOLD()) return;
        vm.deal(sp, sp.balance + reward);
        vm.prank(sp);
        world.openEnergyMission{value: reward}(sid, _roles());
        ghostDeposited += reward;
        ghostOpened++;
    }

    function submitOutcome(uint8 sSeed, uint16 gainSeed, uint16 costSeed) external {
        (uint256 id, SwarmWorld.Mission memory m) = _active(sSeed);
        if (id == 0 || m.state != SwarmWorld.MissionState.OPEN || block.timestamp >= m.deadline) return;
        uint16 gain = uint16(bound(gainSeed, 200, 300));
        uint16 cost = uint16(bound(costSeed, 0, 100));
        uint16 have = world.getSettlement(m.settlementId).materials;
        if (cost > have) cost = have;
        vm.prank(m.roles.builder);
        world.submitOutcome(id, gain, cost, keccak256(abi.encode("artifact", id)));
    }

    function submitTest(uint8 sSeed, uint8 passSeed) external {
        (uint256 id, SwarmWorld.Mission memory m) = _active(sSeed);
        if (id == 0 || m.state != SwarmWorld.MissionState.WORKING || m.testPassed || block.timestamp >= m.deadline) {
            return;
        }
        bool pass = passSeed % 5 != 0;
        vm.prank(m.roles.tester);
        world.submitTest(id, keccak256(abi.encode("test", id)), pass);
        if (!pass) _recordTerminal(id, SwarmWorld.MissionState.FAILED, m);
    }

    function submitReview(uint8 sSeed, uint8 passSeed) external {
        (uint256 id, SwarmWorld.Mission memory m) = _active(sSeed);
        if (id == 0 || m.state != SwarmWorld.MissionState.WORKING || !m.testPassed || block.timestamp >= m.deadline) {
            return;
        }
        bool pass = passSeed % 5 != 0;
        vm.prank(m.roles.reviewer);
        world.submitReview(id, keccak256(abi.encode("review", id)), pass);
        if (!pass) _recordTerminal(id, SwarmWorld.MissionState.FAILED, m);
    }

    function verify(uint8 sSeed, uint8 passSeed) external {
        (uint256 id, SwarmWorld.Mission memory m) = _active(sSeed);
        if (id == 0 || m.state != SwarmWorld.MissionState.VERIFYING || block.timestamp >= m.deadline) return;
        bool pass = passSeed % 5 != 0;
        vm.prank(m.roles.verifier);
        world.verifyOutcome(id, keccak256(abi.encode("verify", id)), pass);
        if (!pass) _recordTerminal(id, SwarmWorld.MissionState.FAILED, m);
    }

    function settle(uint8 sSeed, uint8 callerSeed) external {
        (uint256 id, SwarmWorld.Mission memory m) = _active(sSeed);
        if (id == 0 || m.state != SwarmWorld.MissionState.PASSED) return;
        vm.prank(_actors[callerSeed % 6]);
        world.settleMission(id);
        _recordTerminal(id, SwarmWorld.MissionState.SETTLED, m);
    }

    function expire(uint8 sSeed, uint8 callerSeed) external {
        (uint256 id, SwarmWorld.Mission memory m) = _active(sSeed);
        if (id == 0 || m.state == SwarmWorld.MissionState.PASSED || block.timestamp < m.deadline) return;
        vm.prank(_actors[callerSeed % 6]);
        world.expireMission(id);
        _recordTerminal(id, SwarmWorld.MissionState.EXPIRED, m);
    }

    function tick(uint32 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 2 days));
        if (block.timestamp < world.nextTickAt()) return;
        world.tick();
        ghostTicks++;
    }

    function warp(uint32 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 4 days));
    }

    function claim(uint8 whoSeed) external {
        address a = _actors[whoSeed % 6];
        uint256 amount = world.claimable(a);
        if (amount == 0) return;
        vm.prank(a);
        world.claim();
        ghostWithdrawn += amount;
        ghostWithdrawnBy[a] += amount;
    }
}

contract SwarmWorldInvariants is StdInvariant, Test {
    SwarmWorld internal world;
    SwarmWorldHandler internal handler;

    function setUp() public {
        vm.warp(1_700_000_000);
        world = new SwarmWorld();
        handler = new SwarmWorldHandler(world);
        targetContract(address(handler));
    }

    /// @dev The contract can neither lose nor create ETH: balance is exactly escrow plus claimable,
    ///      and equals everything ever deposited minus everything ever withdrawn.
    function invariant_ethConservation() public view {
        assertEq(
            address(world).balance, world.totalEscrowed() + world.totalClaimable(), "balance == escrow + claimable"
        );
        assertEq(address(world).balance, handler.ghostDeposited() - handler.ghostWithdrawn(), "balance == in - out");
    }

    /// @dev Escrow is exactly the sum of rewards of missions that are not terminal.
    function invariant_escrowMatchesLiveMissions() public view {
        uint256 live;
        uint256 next = world.nextMissionId();
        for (uint256 id = 1; id < next; ++id) {
            SwarmWorld.Mission memory m = world.getMission(id);
            if (!_isTerminal(m.state)) live += m.reward;
        }
        assertEq(world.totalEscrowed(), live, "escrow == live rewards");
    }

    /// @dev Every account's lifetime credit equals what the handler computed from the 50/15/15/rest
    ///      split and the full sponsor refunds; nothing is credited twice or lost.
    function invariant_payoutAccounting() public view {
        uint256 sumClaimable;
        for (uint256 i = 0; i < handler.actorCount(); ++i) {
            address a = handler.actor(i);
            assertEq(
                world.claimable(a) + handler.ghostWithdrawnBy(a), handler.ghostCredited(a), "credit == expected split"
            );
            sumClaimable += world.claimable(a);
        }
        assertEq(sumClaimable, world.totalClaimable(), "only actors hold claimable ETH");
    }

    /// @dev Resources stay within their declared bounds.
    function invariant_resourceBounds() public view {
        for (uint8 i = 0; i < 3; ++i) {
            SwarmWorld.Settlement memory s = world.getSettlement(i);
            assertLe(s.energy, 1000, "energy");
            assertLe(s.food, 1000, "food");
            assertLe(s.materials, 1000, "materials");
            assertLe(s.knowledge, 1000, "knowledge");
            assertLe(s.stability, 100, "stability");
        }
    }

    /// @dev Only energy and materials ever move. Food, knowledge, population and stability keep
    ///      their constructor values forever.
    function invariant_onlyEnergyAndMaterialsChange() public view {
        uint16[3] memory food = [uint16(500), 550, 420];
        uint16[3] memory knowledge = [uint16(500), 350, 180];
        uint8[3] memory stability = [uint8(80), 75, 75];
        for (uint8 i = 0; i < 3; ++i) {
            SwarmWorld.Settlement memory s = world.getSettlement(i);
            assertEq(s.food, food[i], "food frozen");
            assertEq(s.knowledge, knowledge[i], "knowledge frozen");
            assertEq(s.population, 100, "population frozen");
            assertEq(s.stability, stability[i], "stability frozen");
        }
    }

    /// @dev The active-mission pointer is consistent in both directions: a settlement's pointer
    ///      names a live mission on that settlement, every live mission is its settlement's pointer,
    ///      and every terminal mission is no settlement's pointer.
    function invariant_activeMissionConsistency() public view {
        uint256 next = world.nextMissionId();
        for (uint8 i = 0; i < 3; ++i) {
            uint256 id = world.getSettlement(i).activeMission;
            if (id == 0) continue;
            assertLt(id, next, "pointer names an opened mission");
            SwarmWorld.Mission memory m = world.getMission(id);
            assertEq(m.settlementId, i, "pointer settlement matches");
            assertFalse(_isTerminal(m.state), "pointer is live");
        }
        for (uint256 id = 1; id < next; ++id) {
            SwarmWorld.Mission memory m = world.getMission(id);
            uint256 ptr = world.getSettlement(m.settlementId).activeMission;
            if (_isTerminal(m.state)) assertTrue(ptr != id, "terminal mission released its slot");
            else assertEq(ptr, id, "live mission holds its slot");
        }
    }

    /// @dev Once terminal, a mission never changes state again (the handler records the first
    ///      terminal state it observed).
    function invariant_terminalMissionsStayTerminal() public view {
        uint256 next = world.nextMissionId();
        uint256 terminal;
        for (uint256 id = 1; id < next; ++id) {
            SwarmWorld.Mission memory m = world.getMission(id);
            if (handler.ghostIsTerminal(id)) {
                terminal++;
                assertEq(uint8(m.state), uint8(handler.ghostTerminalState(id)), "terminal state frozen");
            } else {
                assertFalse(_isTerminal(m.state), "terminal only through a recorded transition");
            }
        }
        assertEq(terminal, handler.ghostSettled() + handler.ghostFailed() + handler.ghostExpired(), "terminal count");
    }

    /// @dev Mission IDs start at 1 and grow by exactly one per opened mission; 0 is never a mission.
    function invariant_missionIdSentinel() public {
        assertEq(world.nextMissionId(), 1 + handler.ghostOpened(), "ids are dense from 1");
        vm.expectRevert(abi.encodeWithSelector(SwarmWorld.UnknownMission.selector, 0));
        world.getMission(0);
    }

    /// @dev Ticks never run more often than once per 24 hours.
    function invariant_tickCadence() public view {
        assertEq(world.tickCount(), handler.ghostTicks(), "tick count");
        assertLe(world.lastTickAt(), block.timestamp, "last tick in the past");
        assertLe(world.tickCount() * 1 days, block.timestamp - 1_700_000_000 + 1 days, "at most one tick per day");
    }

    function _isTerminal(SwarmWorld.MissionState st) internal pure returns (bool) {
        return st == SwarmWorld.MissionState.SETTLED || st == SwarmWorld.MissionState.FAILED
            || st == SwarmWorld.MissionState.EXPIRED;
    }
}
