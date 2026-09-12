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

    func testDraftMealCanBeCorrectedAndSplitIntoIngredients() async throws {
        let api = MockAPI()
        let joined = try await api.join(
            leagueCode: "DEMO", name: "Bowl Editor", emoji: "🥣", auth0Sub: nil)
        let draft = try await api.uploadMeal(
            playerId: joined.playerId, jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let first = try XCTUnwrap(draft.items.first)
        let last = try XCTUnwrap(draft.items.last)
        let gojiResults = try await api.searchFoods(query: "goji")
        let carrotResults = try await api.searchFoods(query: "carrots")
        let goji = try XCTUnwrap(gojiResults.first)
        let carrots = try XCTUnwrap(carrotResults.first)

        let corrected = try await api.updateMealItem(
            mealId: draft.mealId, itemId: first.itemId, fdcId: goji.fdcId, grams: 25)
        XCTAssertEqual(corrected.items.first?.label, "Goji berries, dried")
        XCTAssertEqual(corrected.items.first?.grams, 25)

        let added = try await api.addMealItem(mealId: draft.mealId, fdcId: carrots.fdcId, grams: 40)
        XCTAssertTrue(added.items.contains { $0.label == "carrots" && $0.grams == 40 })

        let removed = try await api.deleteMealItem(mealId: draft.mealId, itemId: last.itemId)
        XCTAssertFalse(removed.items.contains { $0.itemId == last.itemId })
        try await api.discardMeal(mealId: draft.mealId)
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
