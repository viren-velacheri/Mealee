import Foundation

// Runs the whole app with no server. Fixtures are real server responses captured from the
// seeded DEMO league. Fights are simulated on the phone with BattleSim, so the turn log is
// a real fight, not canned.
final class MockAPI: MealeeAPI {
    let isMock = true
    private var league: LeagueResponse
    private let mealFixture: MealResponse
    private var fighters: [String: FighterStats] = [:]
    private var fights: [String: FightResponse] = [:]
    private var totals: [String: DayTotals] = [:]
    private var discovered: [String: [Discovery]] = [:]
    private var draftMeals: [String: (playerId: String, meal: MealResponse)] = [:]
    private let eventContinuations = LockedBox<[UUID: AsyncStream<LeagueEvent>.Continuation]>([:])

    init() {
        league = MockAPI.load("league")
        mealFixture = MockAPI.load("meal")
        for player in league.players {
            fighters[player.playerId] = player.fighter ?? .empty
        }
    }

    private static func load<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            fatalError("Fixtures/\(name).json missing from the app bundle")
        }
        do {
            return try JSONDecoder.mealee.decode(T.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Fixtures/\(name).json does not decode: \(error)")
        }
    }

    private func delay() async {
        try? await Task.sleep(for: .milliseconds(350))
    }

    func createLeague(name: String) async throws -> String {
        await delay()
        return league.code
    }

    func join(leagueCode: String, name: String, emoji: String, auth0Sub: String?) async throws -> JoinResponse {
        await delay()
        let playerId = "mock-" + UUID().uuidString.prefix(8)
        let newPlayer = LeaguePlayer(playerId: playerId, name: name, emoji: emoji, discovered: 0, fighter: .empty)
        fighters[playerId] = .empty
        league = LeagueResponse(code: league.code, name: league.name, weekStart: league.weekStart,
                                players: league.players + [newPlayer],
                                standings: league.standings + [Standing(playerId: playerId, name: name, emoji: emoji,
                                                                        wins: 0, damage: 0, rank: league.standings.count + 1)],
                                tonight: league.tonight)
        return JoinResponse(playerId: playerId, league: league)
    }

    func league(code: String) async throws -> LeagueResponse {
        await delay()
        return league
    }

    func uploadMeal(playerId: String, jpeg: Data) async throws -> MealResponse {
        try? await Task.sleep(for: .milliseconds(1200))
        let mealId = "mock-" + UUID().uuidString.lowercased()
        let already = Set((discovered[playerId] ?? []).map(\.label))
        let fresh = mealFixture.items.filter { !already.contains($0.label) }
        let items = mealFixture.items.enumerated().map { index, item in
            MealItem(itemId: "\(mealId)-\(index)", label: item.label, fdcId: item.fdcId, grams: item.grams,
                                         gramsLow: item.gramsLow, gramsHigh: item.gramsHigh, confidence: item.confidence,
                                         polygon: item.polygon, isNew: fresh.contains { $0.label == item.label })
        }
        let draft = MealResponse(mealId: mealId, imageW: mealFixture.imageW, imageH: mealFixture.imageH,
                                 imageUrl: mealFixture.imageUrl, items: items, scale: mealFixture.scale,
                                 dayTotals: mealFixture.dayTotals, fighter: mealFixture.fighter)
        draftMeals[mealId] = (playerId, draft)
        return draft
    }

    func relabel(mealId: String, itemId: String, label: String) async throws -> MealResponse {
        await delay()
        guard let draft = draftMeals[mealId] else {
            throw APIError(error: "unknown meal", hint: "Scan the meal again.")
        }
        let items = draft.meal.items.map { item in
            item.itemId == itemId
                ? MealItem(itemId: item.itemId, label: label, fdcId: item.fdcId, grams: item.grams * 0.9,
                           gramsLow: item.gramsLow * 0.9, gramsHigh: item.gramsHigh * 0.9, confidence: 1.0,
                           polygon: item.polygon, isNew: false)
                : item
        }
        let updated = MealResponse(mealId: mealId, imageW: draft.meal.imageW, imageH: draft.meal.imageH,
                                   imageUrl: draft.meal.imageUrl, items: items, scale: draft.meal.scale,
                                   dayTotals: draft.meal.dayTotals, fighter: draft.meal.fighter)
        draftMeals[mealId] = (draft.playerId, updated)
        return updated
    }

    func searchFoods(query: String) async throws -> [FoodSearchResult] {
        await delay()
        return allSearchFoods.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }

    private var allSearchFoods: [FoodSearchResult] {
        foodClassLabels.enumerated().map { index, label in
            FoodSearchResult(fdcId: 100_000 + index, label: label, source: "Mealee catalog",
                             kcal: 100, proteinG: 5, fiberG: 2, sodiumMg: 50, caffeineMg: 0,
                             isVegetable: ["salad greens", "broccoli", "carrots", "beans"].contains(label))
        } + [
            FoodSearchResult(fdcId: 173032, label: "Goji berries, dried", source: "USDA SR Legacy",
                             kcal: 349, proteinG: 14.3, fiberG: 13, sodiumMg: 298, caffeineMg: 0,
                             isVegetable: false),
        ]
    }

    func updateMealItem(mealId: String, itemId: String, fdcId: Int,
                        grams: Double) async throws -> MealResponse {
        await delay()
        guard let draft = draftMeals[mealId],
              let food = allSearchFoods.first(where: { $0.fdcId == fdcId }) else {
            throw APIError(error: "unknown food", hint: "Search for the food again.")
        }
        let items = draft.meal.items.map { item in
            item.itemId == itemId
                ? MealItem(itemId: item.itemId, label: food.label, fdcId: food.fdcId, grams: grams,
                           gramsLow: grams * 0.7, gramsHigh: grams * 1.3, confidence: 1,
                           polygon: item.polygon, isNew: false)
                : item
        }
        return storeDraft(draft, items: items)
    }

    func addMealItem(mealId: String, fdcId: Int, grams: Double) async throws -> MealResponse {
        await delay()
        guard let draft = draftMeals[mealId],
              let food = allSearchFoods.first(where: { $0.fdcId == fdcId }) else {
            throw APIError(error: "unknown food", hint: "Search for the food again.")
        }
        let item = MealItem(itemId: "\(mealId)-\(UUID().uuidString)", label: food.label,
                            fdcId: food.fdcId, grams: grams, gramsLow: grams * 0.7,
                            gramsHigh: grams * 1.3, confidence: 1, polygon: [], isNew: false)
        return storeDraft(draft, items: draft.meal.items + [item])
    }

    func deleteMealItem(mealId: String, itemId: String) async throws -> MealResponse {
        await delay()
        guard let draft = draftMeals[mealId] else {
            throw APIError(error: "unknown meal", hint: "Scan the meal again.")
        }
        return storeDraft(draft, items: draft.meal.items.filter { $0.itemId != itemId })
    }

    func confirmMeal(mealId: String) async throws -> MealResponse {
        await delay()
        guard let draft = draftMeals.removeValue(forKey: mealId) else {
            throw APIError(error: "unknown meal", hint: "Scan the meal again.")
        }
        let already = Set((discovered[draft.playerId] ?? []).map(\.label))
        let freshLabels = Set(draft.meal.items.map(\.label).filter { !already.contains($0) })
        let items = draft.meal.items.map { item in
            MealItem(itemId: item.itemId, label: item.label, fdcId: item.fdcId, grams: item.grams,
                     gramsLow: item.gramsLow, gramsHigh: item.gramsHigh, confidence: item.confidence,
                     polygon: item.polygon, isNew: freshLabels.contains(item.label))
        }
        let confirmed = MealResponse(mealId: mealId, imageW: draft.meal.imageW, imageH: draft.meal.imageH,
                                     imageUrl: draft.meal.imageUrl, items: items, scale: draft.meal.scale,
                                     dayTotals: draft.meal.dayTotals, fighter: draft.meal.fighter)
        fighters[draft.playerId] = confirmed.fighter
        totals[draft.playerId] = confirmed.dayTotals
        discovered[draft.playerId, default: []] += items
            .filter { freshLabels.contains($0.label) }
            .map { Discovery(label: $0.label, thumbnailUrl: "plate_fixture.jpg") }
        broadcast(.fighterUpdate(playerId: draft.playerId, fighter: confirmed.fighter))
        return confirmed
    }

    func discardMeal(mealId: String) async throws {
        await delay()
        guard draftMeals.removeValue(forKey: mealId) != nil else {
            throw APIError(error: "unknown meal", hint: "It may already be discarded.")
        }
    }

    func intake(playerId: String, kind: String) async throws -> IntakeResponse {
        await delay()
        let current = fighters[playerId] ?? .empty
        let boosted = FighterStats(attack: current.attack, defense: current.defense, stamina: current.stamina,
                                   speed: current.speed, focus: kind == "coffee" ? min(100, current.focus + 7) : current.focus,
                                   recovery: kind == "water" ? min(10, current.recovery + 1) : current.recovery,
                                   crashTurn: current.crashTurn, hpMax: current.hpMax,
                                   firstStrike: current.firstStrike || kind == "coffee",
                                   reasons: current.reasons + [kind == "water" ? "Water +250 ml: recovery up" : "Coffee +95 mg: focus up"])
        fighters[playerId] = boosted
        return IntakeResponse(dayTotals: totals[playerId] ?? mealFixture.dayTotals, fighter: boosted)
    }

    func fighterToday(playerId: String) async throws -> FighterStats {
        await delay()
        return fighters[playerId] ?? .empty
    }

    func startFight(aPlayerId: String, bPlayerId: String) async throws -> FightResponse {
        await delay()
        let fightId = UUID().uuidString.lowercased()
        let seed = seedFromFightID(fightId)
        let refA = playerRef(aPlayerId), refB = playerRef(bPlayerId)
        let a = Combatant.from(playerId: aPlayerId, name: refA.name, emoji: refA.emoji, stats: fighters[aPlayerId] ?? .empty)
        let b = Combatant.from(playerId: bPlayerId, name: refB.name, emoji: refB.emoji, stats: fighters[bPlayerId] ?? .empty)
        let outcome = BattleSim.simulate(seed: seed, fighterA: a.simFighter, fighterB: b.simFighter)
        let fight = FightResponse(fightId: fightId, seed: seed, kind: "quick", leagueCode: league.code,
                                  winnerId: outcome.winner == "a" ? aPlayerId : bPlayerId,
                                  createdAt: ISO8601DateFormatter().string(from: Date()),
                                  a: a, b: b, turns: outcome.turns)
        fights[fightId] = fight
        broadcast(.fightEnded(fight))
        return fight
    }

    func fight(id: String) async throws -> FightResponse {
        guard let fight = fights[id] else { throw APIError(error: "unknown fight", hint: "mock has no fight \(id)") }
        return fight
    }

    func discoveries(playerId: String) async throws -> DiscoveriesResponse {
        await delay()
        return DiscoveriesResponse(weekStart: league.weekStart, total: foodClassLabels.count,
                                   discovered: discovered[playerId] ?? [])
    }

    func imageURL(path: String) -> URL? {
        Bundle.main.url(forResource: "plate_fixture", withExtension: "jpg")
    }

    func leagueEvents(code: String) -> AsyncStream<LeagueEvent> {
        AsyncStream { continuation in
            let key = UUID()
            eventContinuations.mutate { $0[key] = continuation }
            continuation.onTermination = { [eventContinuations] _ in
                eventContinuations.mutate { $0[key] = nil }
            }
        }
    }

    private func broadcast(_ event: LeagueEvent) {
        for continuation in eventContinuations.value.values {
            continuation.yield(event)
        }
    }

    private func storeDraft(_ draft: (playerId: String, meal: MealResponse),
                            items: [MealItem]) -> MealResponse {
        let updated = MealResponse(mealId: draft.meal.mealId, imageW: draft.meal.imageW,
                                   imageH: draft.meal.imageH, imageUrl: draft.meal.imageUrl,
                                   items: items, scale: draft.meal.scale,
                                   dayTotals: draft.meal.dayTotals, fighter: draft.meal.fighter)
        draftMeals[draft.meal.mealId] = (draft.playerId, updated)
        return updated
    }

    private func playerRef(_ playerId: String) -> PlayerRef {
        league.players.first { $0.playerId == playerId }?.ref
            ?? PlayerRef(playerId: playerId, name: "You", emoji: "🍽️")
    }
}

final class LockedBox<Value> {
    private var stored: Value
    private let lock = NSLock()

    init(_ value: Value) { stored = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func mutate(_ change: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        change(&stored)
    }
}
