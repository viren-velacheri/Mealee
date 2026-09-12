import UIKit
import XCTest
@testable import Mealee

final class MockJourneyTests: XCTestCase {
    func testOfflineJourneyUpdatesFighterDiscoveriesAndProducesReplayableFight() async throws {
        let api = MockAPI()

        let joined = try await api.join(
            leagueCode: "DEMO",
            name: "Test Fighter",
            emoji: "🍗",
            auth0Sub: nil
        )
        XCTAssertEqual(joined.league.code, "DEMO")
        XCTAssertTrue(joined.league.players.contains { $0.playerId == joined.playerId })

        let water = try await api.intake(playerId: joined.playerId, kind: "water")
        XCTAssertEqual(water.fighter.recovery, 1)
        XCTAssertTrue(water.fighter.reasons.contains("Water +250 ml: recovery up"))

        let coffee = try await api.intake(playerId: joined.playerId, kind: "coffee")
        XCTAssertEqual(coffee.fighter.focus, 77)
        XCTAssertTrue(coffee.fighter.firstStrike)

        let meal = try await api.uploadMeal(playerId: joined.playerId, jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertFalse(meal.items.isEmpty)
        XCTAssertGreaterThan(meal.fighter.attack, 0)
        let fighterWhileDraft = try await api.fighterToday(playerId: joined.playerId)
        let discoveriesWhileDraft = try await api.discoveries(playerId: joined.playerId)
        XCTAssertEqual(fighterWhileDraft, coffee.fighter)
        XCTAssertTrue(discoveriesWhileDraft.discovered.isEmpty)

        let confirmed = try await api.confirmMeal(mealId: meal.mealId)
        XCTAssertEqual(confirmed.fighter, meal.fighter)

        let discoveries = try await api.discoveries(playerId: joined.playerId)
        XCTAssertEqual(Set(discoveries.discovered.map(\.label)), Set(confirmed.items.map(\.label)))

        let opponent = try XCTUnwrap(joined.league.players.first { $0.playerId != joined.playerId })
        let fight = try await api.startFight(aPlayerId: joined.playerId, bPlayerId: opponent.playerId)
        XCTAssertFalse(fight.turns.isEmpty)
        XCTAssertTrue([fight.a.playerId, fight.b.playerId].contains(fight.winnerId))

        let replay = BattleSim.simulate(
            seed: fight.seed,
            fighterA: fight.a.simFighter,
            fighterB: fight.b.simFighter
        )
        XCTAssertEqual(replay.turns, fight.turns)
        XCTAssertEqual(replay.winner == "a" ? fight.a.playerId : fight.b.playerId, fight.winnerId)
    }

    func testDiscardMealDoesNotApplyTheDraft() async throws {
        let api = MockAPI()
        let joined = try await api.join(
            leagueCode: "DEMO",
            name: "Retake Tester",
            emoji: "📷",
            auth0Sub: nil
        )
        let fighterBefore = try await api.fighterToday(playerId: joined.playerId)
        let draft = try await api.uploadMeal(
            playerId: joined.playerId,
            jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )

        try await api.discardMeal(mealId: draft.mealId)

        let fighterAfterDiscard = try await api.fighterToday(playerId: joined.playerId)
        let discoveriesAfterDiscard = try await api.discoveries(playerId: joined.playerId)
        XCTAssertEqual(fighterAfterDiscard, fighterBefore)
        XCTAssertTrue(discoveriesAfterDiscard.discovered.isEmpty)
        do {
            _ = try await api.confirmMeal(mealId: draft.mealId)
            XCTFail("Discarded drafts must not be confirmable")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testPhotoEncoderProducesAnUprightBoundedJPEG() throws {
        let sourceURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "plate_fixture", withExtension: "jpg")
        )
        let encoded = try XCTUnwrap(PhotoEncoder.jpeg(from: Data(contentsOf: sourceURL)))
        let image = try XCTUnwrap(UIImage(data: encoded))

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1600)
        XCTAssertEqual(image.imageOrientation, .up)
    }
}
