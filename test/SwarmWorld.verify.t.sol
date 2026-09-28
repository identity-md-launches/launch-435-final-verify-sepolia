// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SwarmWorld} from "../src/SwarmWorld.sol";

/// @title Final-verification suite
/// @notice One test per item of the pre-deployment checklist that the base suite covers only
///         implicitly. Nothing here changes the protocol; it pins behaviour of the reviewed source.
contract SwarmWorldVerifyTest is Test {
    SwarmWorld internal world;

    address internal sponsor = makeAddr("sponsor");
    address internal builder = makeAddr("builder");
    address internal tester = makeAddr("tester");
    address internal reviewer = makeAddr("reviewer");
    address internal verifier = makeAddr("verifier");
    address internal stranger = makeAddr("stranger");

    uint8 internal constant NOVA_PORT = 2;
    uint256 internal constant REWARD = 1 ether;
    uint256 internal deployedAt;

    function setUp() public {
        vm.warp(1_700_000_000);
        deployedAt = block.timestamp;
        world = new SwarmWorld();
        vm.deal(sponsor, 100 ether);
        vm.deal(stranger, 100 ether);
    }

    // ------------------------------------------------------------------ helpers

    function _roles() internal view returns (SwarmWorld.Roles memory r) {
        r = SwarmWorld.Roles({
            builder: builder,
            tester: tester,
            reviewer: reviewer,
            verifier: verifier,
            builderSeat: 11,
            testerSeat: 22,
            reviewerSeat: 33,
            verifierSeat: 44
        });
    }

    function _open() internal returns (uint256 id) {
        vm.prank(sponsor);
        id = world.openEnergyMission{value: REWARD}(NOVA_PORT, _roles());
    }

    function _runToPassed(uint256 id) internal {
        vm.prank(builder);
        world.submitOutcome(id, 250, 60, keccak256("artifact"));
        vm.prank(tester);
        world.submitTest(id, keccak256("test"), true);
        vm.prank(reviewer);
        world.submitReview(id, keccak256("review"), true);
        vm.prank(verifier);
        world.verifyOutcome(id, keccak256("verify"), true);
    }

    function _settled() internal returns (uint256 id) {
        id = _open();
        _runToPassed(id);
        world.settleMission(id);
    }

    function _failed() internal returns (uint256 id) {
        id = _open();
        vm.prank(builder);
        world.submitOutcome(id, 250, 60, keccak256("artifact"));
        vm.prank(tester);
        world.submitTest(id, keccak256("test"), false);
    }

    function _expired() internal returns (uint256 id) {
        id = _open();
        vm.warp(block.timestamp + 3 days);
        vm.prank(stranger);
        world.expireMission(id);
    }

    /// @dev Bring Nova Port back under the crisis threshold after a settlement raised its energy.
    function _driveIntoCrisis() internal {
        while (world.getSettlement(NOVA_PORT).energy >= 300) {
            vm.warp(world.nextTickAt());
            world.tick();
        }
    }

    function _state(uint256 id) internal view returns (SwarmWorld.MissionState) {
        return world.getMission(id).state;
    }

    function _wrong(uint256 id, SwarmWorld.MissionState actual, SwarmWorld.MissionState expected)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(SwarmWorld.WrongState.selector, id, actual, expected);
    }

    // ------------------------------------------------------------------ active-mission cleanup

    function test_activeMissionClearsAfterSettledAndNewMissionOpens() public {
        uint256 id = _settled();
        assertEq(uint8(_state(id)), uint8(SwarmWorld.MissionState.SETTLED));
        assertEq(world.getSettlement(NOVA_PORT).activeMission, 0, "slot freed on SETTLED");
        _driveIntoCrisis();
        uint256 next = _open();
        assertEq(next, id + 1);
        assertEq(world.getSettlement(NOVA_PORT).activeMission, next);
    }

    function test_activeMissionClearsAfterFailedAndNewMissionOpens() public {
        uint256 id = _failed();
        assertEq(uint8(_state(id)), uint8(SwarmWorld.MissionState.FAILED));
        assertEq(world.getSettlement(NOVA_PORT).activeMission, 0, "slot freed on FAILED");
        uint256 next = _open();
        assertEq(next, id + 1);
        assertEq(world.getSettlement(NOVA_PORT).activeMission, next);
    }

    function test_activeMissionClearsAfterExpiredAndNewMissionOpens() public {
        uint256 id = _expired();
        assertEq(uint8(_state(id)), uint8(SwarmWorld.MissionState.EXPIRED));
        assertEq(world.getSettlement(NOVA_PORT).activeMission, 0, "slot freed on EXPIRED");
        uint256 next = _open();
        assertEq(next, id + 1);
        assertEq(world.getSettlement(NOVA_PORT).activeMission, next);
    }

    // ------------------------------------------------------------------ terminal states are final

    function _assertNoTransitionFrom(uint256 id, SwarmWorld.MissionState terminal) internal {
        uint256 sponsorBefore = world.claimable(sponsor);
        uint256 builderBefore = world.claimable(builder);
        uint256 escrowBefore = world.totalEscrowed();
        bytes32 worldBefore = world.worldStateHash();

        vm.prank(builder);
        vm.expectRevert(_wrong(id, terminal, SwarmWorld.MissionState.OPEN));
        world.submitOutcome(id, 250, 60, keccak256("x"));
        vm.prank(tester);
        vm.expectRevert(_wrong(id, terminal, SwarmWorld.MissionState.WORKING));
        world.submitTest(id, keccak256("x"), true);
        vm.prank(reviewer);
        vm.expectRevert(_wrong(id, terminal, SwarmWorld.MissionState.WORKING));
        world.submitReview(id, keccak256("x"), true);
        vm.prank(verifier);
        vm.expectRevert(_wrong(id, terminal, SwarmWorld.MissionState.VERIFYING));
        world.verifyOutcome(id, keccak256("x"), true);
        vm.expectRevert(_wrong(id, terminal, SwarmWorld.MissionState.PASSED));
        world.settleMission(id);
        vm.warp(block.timestamp + 30 days);
        vm.prank(sponsor);
        vm.expectRevert(_wrong(id, terminal, SwarmWorld.MissionState.OPEN));
        world.expireMission(id);

        assertEq(uint8(_state(id)), uint8(terminal), "state unchanged");
        assertEq(world.claimable(sponsor), sponsorBefore, "no extra sponsor credit");
        assertEq(world.claimable(builder), builderBefore, "no extra builder credit");
        assertEq(world.totalEscrowed(), escrowBefore, "escrow unchanged");
        assertEq(world.worldStateHash(), worldBefore, "world unchanged");
    }

    function test_settledMissionCannotTransitionAgain() public {
        _assertNoTransitionFrom(_settled(), SwarmWorld.MissionState.SETTLED);
    }

    function test_failedMissionCannotTransitionAgain() public {
        _assertNoTransitionFrom(_failed(), SwarmWorld.MissionState.FAILED);
    }

    function test_expiredMissionCannotTransitionAgain() public {
        _assertNoTransitionFrom(_expired(), SwarmWorld.MissionState.EXPIRED);
    }

    // ------------------------------------------------------------------ settlement gating

    function test_settlementRequiresPassedFromEveryNonPassedState() public {
        uint256 id = _open();
        vm.expectRevert(_wrong(id, SwarmWorld.MissionState.OPEN, SwarmWorld.MissionState.PASSED));
        world.settleMission(id);

        vm.prank(builder);
        world.submitOutcome(id, 250, 60, keccak256("artifact"));
        vm.expectRevert(_wrong(id, SwarmWorld.MissionState.WORKING, SwarmWorld.MissionState.PASSED));
        world.settleMission(id);

        vm.prank(tester);
        world.submitTest(id, keccak256("test"), true);
        vm.expectRevert(_wrong(id, SwarmWorld.MissionState.WORKING, SwarmWorld.MissionState.PASSED));
        world.settleMission(id);

        vm.prank(reviewer);
        world.submitReview(id, keccak256("review"), true);
        vm.expectRevert(_wrong(id, SwarmWorld.MissionState.VERIFYING, SwarmWorld.MissionState.PASSED));
        world.settleMission(id);

        vm.prank(verifier);
        world.verifyOutcome(id, keccak256("verify"), true);
        world.settleMission(id);
        assertEq(uint8(_state(id)), uint8(SwarmWorld.MissionState.SETTLED));
    }

    function test_worldStateFrozenUntilSettlementIncludingTicks() public {
        uint256 id = _open();
        bytes32 h0 = world.worldStateHash();
        SwarmWorld.Settlement memory before = world.getSettlement(NOVA_PORT);
        _runToPassed(id);
        // Two ticks while the mission is PASSED but not settled: other settlements decay, Nova Port
        // is frozen, and the mission's stored outcome has not been applied.
        vm.warp(world.nextTickAt());
        world.tick();
        vm.warp(world.nextTickAt());
        world.tick();
        SwarmWorld.Settlement memory mid = world.getSettlement(NOVA_PORT);
        assertEq(mid.energy, before.energy, "energy frozen while active");
        assertEq(mid.materials, before.materials, "materials frozen while active");
        assertEq(world.getSettlement(0).energy, 450, "idle settlements still decay");
        assertTrue(world.worldStateHash() != h0, "other settlements moved");
        assertEq(world.getMission(id).worldStateBefore, bytes32(0), "not settled yet");

        bytes32 hBefore = world.worldStateHash();
        world.settleMission(id);
        assertEq(world.getMission(id).worldStateBefore, hBefore, "settlement snapshots the world it changed");
    }

    function test_settlementChangesOnlyEnergyAndMaterialsOfItsSettlement() public {
        SwarmWorld.Settlement memory s0 = world.getSettlement(0);
        SwarmWorld.Settlement memory s1 = world.getSettlement(1);
        SwarmWorld.Settlement memory s2 = world.getSettlement(2);
        _settled();
        SwarmWorld.Settlement memory a0 = world.getSettlement(0);
        SwarmWorld.Settlement memory a1 = world.getSettlement(1);
        SwarmWorld.Settlement memory a2 = world.getSettlement(2);
        assertEq(keccak256(abi.encode(s0)), keccak256(abi.encode(a0)), "settlement 0 untouched");
        assertEq(keccak256(abi.encode(s1)), keccak256(abi.encode(a1)), "settlement 1 untouched");
        assertEq(a2.energy, s2.energy + 250);
        assertEq(a2.materials, s2.materials - 60);
        assertEq(a2.food, s2.food);
        assertEq(a2.knowledge, s2.knowledge);
        assertEq(a2.population, s2.population);
        assertEq(a2.stability, s2.stability);
        assertEq(a2.activeMission, 0);
    }

    // ------------------------------------------------------------------ mission id sentinel

    function test_missionIdZeroIsNeverAMission() public {
        assertEq(world.nextMissionId(), 1);
        assertEq(world.getSettlement(0).activeMission, 0);
        bytes memory unknown0 = abi.encodeWithSelector(SwarmWorld.UnknownMission.selector, 0);
        vm.expectRevert(unknown0);
        world.getMission(0);
        vm.expectRevert(unknown0);
        world.settleMission(0);
        vm.expectRevert(unknown0);
        world.expireMission(0);
        vm.prank(builder);
        vm.expectRevert(unknown0);
        world.submitOutcome(0, 250, 60, keccak256("a"));
        vm.prank(tester);
        vm.expectRevert(unknown0);
        world.submitTest(0, keccak256("t"), true);
        vm.prank(reviewer);
        vm.expectRevert(unknown0);
        world.submitReview(0, keccak256("r"), true);
        vm.prank(verifier);
        vm.expectRevert(unknown0);
        world.verifyOutcome(0, keccak256("v"), true);

        // The first real mission is 1, and IDs beyond the counter are unknown too.
        uint256 id = _open();
        assertEq(id, 1);
        vm.expectRevert(abi.encodeWithSelector(SwarmWorld.UnknownMission.selector, 2));
        world.getMission(2);
        vm.expectRevert(abi.encodeWithSelector(SwarmWorld.UnknownMission.selector, type(uint256).max));
        world.settleMission(type(uint256).max);
    }

    // ------------------------------------------------------------------ proof hash

    function test_proofHashCommitsToEveryInput() public {
        uint256 id = _open();
        _runToPassed(id);
        bytes32 before = world.worldStateHash();
        world.settleMission(id);
        bytes32 stored = world.getMission(id).proofHash;

        uint32[4] memory seats = [uint32(11), 22, 33, 44];
        bytes32 base = world.computeProofHash(
            id,
            NOVA_PORT,
            before,
            250,
            60,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        assertEq(base, stored, "recomputation matches stored value");

        // Flip each of the thirteen committed fields in turn: every one must change the hash.
        bytes32[13] memory variants;
        variants[0] = world.computeProofHash(
            id + 1,
            NOVA_PORT,
            before,
            250,
            60,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        variants[1] = world.computeProofHash(
            id,
            1,
            before,
            250,
            60,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        variants[2] = world.computeProofHash(
            id,
            NOVA_PORT,
            bytes32(uint256(before) ^ 1),
            250,
            60,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        variants[3] = world.computeProofHash(
            id,
            NOVA_PORT,
            before,
            251,
            60,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        variants[4] = world.computeProofHash(
            id,
            NOVA_PORT,
            before,
            250,
            61,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        variants[5] = world.computeProofHash(
            id,
            NOVA_PORT,
            before,
            250,
            60,
            keccak256("artifact2"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        variants[6] = world.computeProofHash(
            id,
            NOVA_PORT,
            before,
            250,
            60,
            keccak256("artifact"),
            keccak256("test2"),
            keccak256("review"),
            keccak256("verify"),
            seats
        );
        variants[7] = world.computeProofHash(
            id,
            NOVA_PORT,
            before,
            250,
            60,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review2"),
            keccak256("verify"),
            seats
        );
        variants[8] = world.computeProofHash(
            id,
            NOVA_PORT,
            before,
            250,
            60,
            keccak256("artifact"),
            keccak256("test"),
            keccak256("review"),
            keccak256("verify2"),
            seats
        );
        for (uint256 k = 0; k < 4; ++k) {
            uint32[4] memory alt = seats;
            alt[k] += 1;
            variants[9 + k] = world.computeProofHash(
                id,
                NOVA_PORT,
                before,
                250,
                60,
                keccak256("artifact"),
                keccak256("test"),
                keccak256("review"),
                keccak256("verify"),
                alt
            );
        }
        for (uint256 i = 0; i < 13; ++i) {
            assertTrue(variants[i] != base, "field not committed");
            for (uint256 j = i + 1; j < 13; ++j) {
                assertTrue(variants[i] != variants[j], "variants collide");
            }
        }
    }

    /// @dev The reviewed source has no chainId / address(this) / version domain in the proof hash:
    ///      the same evidence on two different world instances yields the same commitment. This is
    ///      documented behaviour, not a change request; the hash is a commitment to recorded
    ///      evidence, not a claim that the evidence is true.
    function test_proofHashHasNoInstanceDomain() public {
        uint256 id = _settled();
        bytes32 first = world.getMission(id).proofHash;

        SwarmWorld other = new SwarmWorld();
        vm.prank(sponsor);
        uint256 oid = other.openEnergyMission{value: REWARD}(NOVA_PORT, _roles());
        vm.prank(builder);
        other.submitOutcome(oid, 250, 60, keccak256("artifact"));
        vm.prank(tester);
        other.submitTest(oid, keccak256("test"), true);
        vm.prank(reviewer);
        other.submitReview(oid, keccak256("review"), true);
        vm.prank(verifier);
        other.verifyOutcome(oid, keccak256("verify"), true);
        other.settleMission(oid);

        assertEq(oid, id);
        assertEq(other.getMission(oid).proofHash, first, "no chainId/address domain separation");
        assertEq(
            world.computeProofHash(
                id,
                NOVA_PORT,
                world.getMission(id).worldStateBefore,
                250,
                60,
                keccak256("artifact"),
                keccak256("test"),
                keccak256("review"),
                keccak256("verify"),
                [uint32(11), 22, 33, 44]
            ),
            first
        );
    }

    // ------------------------------------------------------------------ roles and seats

    function test_seatIdsAreProvenanceOnlyAndNeverAuthorise() public {
        // Same addresses, different seat IDs: the addresses authorise, the seats are only stored.
        SwarmWorld.Roles memory r = _roles();
        r.builderSeat = 7;
        r.testerSeat = 8;
        r.reviewerSeat = 9;
        r.verifierSeat = 10;
        vm.prank(sponsor);
        uint256 id = world.openEnergyMission{value: REWARD}(NOVA_PORT, r);
        // Nothing in the contract accepts a seat ID as authentication: only the recorded address
        // can act, regardless of seat.
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(SwarmWorld.NotRole.selector, id, builder, stranger));
        world.submitOutcome(id, 250, 60, keccak256("a"));
        _runToPassed(id);
        world.settleMission(id);
        SwarmWorld.Mission memory m = world.getMission(id);
        assertEq(m.roles.builderSeat, 7);
        assertEq(m.roles.verifierSeat, 10);
        // Payout follows the addresses, not the seats.
        assertEq(world.claimable(builder), REWARD / 2);
        assertEq(world.claimable(verifier), REWARD - REWARD / 2 - 2 * (REWARD * 15 / 100));
    }

    function test_roleAddressesAndSeatsMustAllBeDistinctAndNonzero() public {
        // Every address zero.
        for (uint256 k = 0; k < 4; ++k) {
            SwarmWorld.Roles memory r = _roles();
            if (k == 0) r.builder = address(0);
            if (k == 1) r.tester = address(0);
            if (k == 2) r.reviewer = address(0);
            if (k == 3) r.verifier = address(0);
            vm.prank(sponsor);
            vm.expectRevert(SwarmWorld.ZeroRoleAddress.selector);
            world.openEnergyMission{value: REWARD}(NOVA_PORT, r);
        }
        // All four addresses equal, all four seats equal.
        SwarmWorld.Roles memory same = _roles();
        same.tester = builder;
        same.reviewer = builder;
        same.verifier = builder;
        vm.prank(sponsor);
        vm.expectRevert(SwarmWorld.RolesNotDistinct.selector);
        world.openEnergyMission{value: REWARD}(NOVA_PORT, same);
        SwarmWorld.Roles memory seats = _roles();
        seats.testerSeat = 11;
        seats.reviewerSeat = 11;
        seats.verifierSeat = 11;
        vm.prank(sponsor);
        vm.expectRevert(SwarmWorld.SeatsNotDistinct.selector);
        world.openEnergyMission{value: REWARD}(NOVA_PORT, seats);
        // Address check runs before the seat check, so zero address wins over duplicate seats.
        SwarmWorld.Roles memory both = seats;
        both.builder = address(0);
        vm.prank(sponsor);
        vm.expectRevert(SwarmWorld.ZeroRoleAddress.selector);
        world.openEnergyMission{value: REWARD}(NOVA_PORT, both);
    }

    // ------------------------------------------------------------------ deadline

    function testFuzz_noRoleActionAtOrAfterDeadline(uint64 offset) public {
        uint256 id = _open();
        vm.prank(builder);
        world.submitOutcome(id, 250, 60, keccak256("artifact"));
        vm.prank(tester);
        world.submitTest(id, keccak256("test"), true);
        uint64 deadline = uint64(deployedAt + 3 days);
        offset = uint64(bound(offset, 0, 365 days));
        vm.warp(deadline + offset);
        bytes memory err = abi.encodeWithSelector(SwarmWorld.MissionDeadlinePassed.selector, id, deadline);
        vm.prank(reviewer);
        vm.expectRevert(err);
        world.submitReview(id, keccak256("review"), true);
        // The deadline guard runs before the "already tested" guard, so the tester also sees it.
        vm.prank(tester);
        vm.expectRevert(err);
        world.submitTest(id, keccak256("test"), true);
        vm.prank(builder);
        vm.expectRevert(_wrong(id, SwarmWorld.MissionState.WORKING, SwarmWorld.MissionState.OPEN));
        world.submitOutcome(id, 250, 60, keccak256("again"));
        // Expiry is available at exactly the same instant.
        vm.prank(stranger);
        world.expireMission(id);
        assertEq(world.claimable(sponsor), REWARD);
    }

    // ------------------------------------------------------------------ energy / tick

    function testFuzz_tickNeverUnderflowsAndRespectsBoundary(uint8 ticks) public {
        ticks = uint8(bound(ticks, 1, 60));
        for (uint256 i = 0; i < ticks; ++i) {
            uint256 due = world.nextTickAt();
            vm.warp(due - 1);
            vm.expectRevert(abi.encodeWithSelector(SwarmWorld.TickTooEarly.selector, due));
            world.tick();
            vm.warp(due);
            world.tick();
        }
        assertEq(world.tickCount(), ticks);
        for (uint8 s = 0; s < 3; ++s) {
            uint16 start = s == 0 ? 500 : (s == 1 ? 420 : 120);
            uint256 expected = uint256(ticks) * 25 >= start ? 0 : start - uint256(ticks) * 25;
            assertEq(world.getSettlement(s).energy, expected, "saturating decay");
        }
    }

    // ------------------------------------------------------------------ rewards

    function testFuzz_payoutSplitExact(uint128 rewardRaw) public {
        uint256 reward = uint256(rewardRaw) + 1;
        vm.deal(sponsor, reward);
        vm.prank(sponsor);
        uint256 id = world.openEnergyMission{value: reward}(NOVA_PORT, _roles());
        _runToPassed(id);
        world.settleMission(id);
        uint256 b = reward * 50 / 100;
        uint256 t = reward * 15 / 100;
        uint256 r = reward * 15 / 100;
        uint256 v = reward - b - t - r;
        assertEq(world.claimable(builder), b, "builder 50%");
        assertEq(world.claimable(tester), t, "tester 15%");
        assertEq(world.claimable(reviewer), r, "reviewer 15%");
        assertEq(world.claimable(verifier), v, "verifier remainder incl. dust");
        assertGe(v, reward * 20 / 100, "verifier never below 20%");
        assertLe(v - reward * 20 / 100, 3, "dust is at most 3 wei");
        assertEq(b + t + r + v, reward, "complete reward conserved");
        assertEq(world.totalClaimable(), reward);
        assertEq(world.totalEscrowed(), 0);
        assertEq(address(world).balance, reward);
    }

    function test_noDoubleSettlementRefundOrClaim() public {
        // Settle once; second settle reverts and credits nothing more.
        uint256 a = _settled();
        uint256 builderCredit = world.claimable(builder);
        vm.expectRevert(_wrong(a, SwarmWorld.MissionState.SETTLED, SwarmWorld.MissionState.PASSED));
        world.settleMission(a);
        assertEq(world.claimable(builder), builderCredit);

        // Fail once; the refund cannot be triggered again through any path.
        _driveIntoCrisis();
        uint256 b = _failed();
        assertEq(world.claimable(sponsor), REWARD);
        vm.prank(tester);
        vm.expectRevert(_wrong(b, SwarmWorld.MissionState.FAILED, SwarmWorld.MissionState.WORKING));
        world.submitTest(b, keccak256("t"), false);
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert(_wrong(b, SwarmWorld.MissionState.FAILED, SwarmWorld.MissionState.OPEN));
        world.expireMission(b);
        assertEq(world.claimable(sponsor), REWARD);

        // Claim once; second claim reverts; balance is conserved throughout.
        uint256 before = sponsor.balance;
        vm.prank(sponsor);
        world.claim();
        assertEq(sponsor.balance, before + REWARD);
        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(SwarmWorld.NothingToClaim.selector, sponsor));
        world.claim();
        assertEq(address(world).balance, world.totalEscrowed() + world.totalClaimable());
    }
}
