import XCTest
@testable import Mealee

// Pins the Swift simulation to the Python one. If this fails, the phone and the server
// disagree about who won a fight. Regenerate the fixture with:
//     python3 spikes/spike_battle.py
final class BattleSimTests: XCTestCase {

    private struct Fixture: Decodable {
        let fightId: String
        let seed: UInt32
        let a: SimFighter
        let b: SimFighter
        let expected: BattleResult
    }

    private func loadFixtures() throws -> [Fixture] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "battle_fixtures", withExtension: "json"),
            "battle_fixtures.json is not in the test bundle. Add ios/Mealee/Fixtures to the target."
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Fixture].self, from: Data(contentsOf: url))
    }

    func testMulberry32MatchesCanonicalImplementation() {
        let reference: [UInt32: [UInt32]] = [
            1: [2693262067, 11749833, 2265367787, 4213581821, 4159151403],
            0: [1144304738, 1416247, 958946056, 627933444, 2007157716],
            2967037554: [634114255, 3430785177, 1044617980, 2133622804, 2768123999],
            744262745: [723998645, 651310318, 82830691, 74561485, 305162176],
        ]
        for (seed, expected) in reference {
            var rng = Mulberry32(seed: seed)
            let produced = (0..<expected.count).map { _ in rng.nextU32() }
            XCTAssertEqual(produced, expected, "mulberry32 drifted for seed \(seed)")
        }
    }

    func testSeedDerivationMatchesServer() throws {
        for fixture in try loadFixtures() {
            XCTAssertEqual(seedFromFightID(fixture.fightId), fixture.seed,
                           "seed derivation disagrees for \(fixture.fightId)")
        }
    }

    func testTurnLogsMatchPythonExactly() throws {
        for fixture in try loadFixtures() {
            let produced = BattleSim.simulate(seed: fixture.seed, fighterA: fixture.a, fighterB: fixture.b)

            XCTAssertEqual(produced.winner, fixture.expected.winner, "winner differs in \(fixture.fightId)")
            XCTAssertEqual(produced.turns.count, fixture.expected.turns.count,
                           "turn count differs in \(fixture.fightId)")

            for (index, expectedTurn) in fixture.expected.turns.enumerated() {
                guard index < produced.turns.count else { break }
                XCTAssertEqual(produced.turns[index], expectedTurn,
                               "entry \(index) differs in \(fixture.fightId)")
            }
        }
    }

    func testEveryFightEndsWithinTwentyTurns() throws {
        for fixture in try loadFixtures() {
            let produced = BattleSim.simulate(seed: fixture.seed, fighterA: fixture.a, fighterB: fixture.b)
            let lastTurn = try XCTUnwrap(produced.turns.last).turn
            XCTAssertLessThanOrEqual(lastTurn, BattleSim.maxTurns, "\(fixture.fightId) overran")
        }
    }
}
