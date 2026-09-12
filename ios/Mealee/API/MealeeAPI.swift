import Foundation

protocol MealeeAPI: AnyObject {
    var isMock: Bool { get }

    func createLeague(name: String) async throws -> String
    func join(leagueCode: String, name: String, emoji: String, auth0Sub: String?) async throws -> JoinResponse
    func league(code: String) async throws -> LeagueResponse
    func uploadMeal(playerId: String, jpeg: Data) async throws -> MealResponse
    func relabel(mealId: String, itemId: String, label: String) async throws -> MealResponse
    func searchFoods(query: String) async throws -> [FoodSearchResult]
    func updateMealItem(mealId: String, itemId: String, fdcId: Int, grams: Double) async throws -> MealResponse
    func addMealItem(mealId: String, fdcId: Int, grams: Double) async throws -> MealResponse
    func deleteMealItem(mealId: String, itemId: String) async throws -> MealResponse
    func confirmMeal(mealId: String) async throws -> MealResponse
    func discardMeal(mealId: String) async throws
    func intake(playerId: String, kind: String) async throws -> IntakeResponse
    func fighterToday(playerId: String) async throws -> FighterStats
    func startFight(aPlayerId: String, bPlayerId: String) async throws -> FightResponse
    func fight(id: String) async throws -> FightResponse
    func discoveries(playerId: String) async throws -> DiscoveriesResponse
    func timeline(playerId: String) async throws -> [TimelineEntry]
    func imageURL(path: String) -> URL?
    func leagueEvents(code: String) -> AsyncStream<LeagueEvent>
}

enum APIConfig {
    static var baseURLString: String {
        (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String) ?? "mock"
    }

    static var auth0Enabled: Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "AUTH0_ENABLED") as? String) ?? "NO"
        return raw.uppercased() == "YES"
    }

    static func make() -> MealeeAPI {
        if baseURLString == "mock" || baseURLString.isEmpty { return MockAPI() }
        guard let url = URL(string: baseURLString) else { return MockAPI() }
        return LiveAPI(baseURL: url)
    }
}
