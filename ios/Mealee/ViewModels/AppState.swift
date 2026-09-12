import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    let api: MealeeAPI
    var playerId: String?
    var leagueCode: String?
    var playerName = ""
    var playerEmoji = "🍽️"
    var fighter: FighterStats = .empty
    var league: LeagueResponse?
    var errorMessage: String?
    var lastFight: FightResponse?

    private var eventTask: Task<Void, Never>?

    private struct Persisted: Codable {
        var playerId: String
        var leagueCode: String
        var playerName: String
        var playerEmoji: String
    }

    init(api: MealeeAPI) {
        self.api = api
        restore()
    }

    var isJoined: Bool { playerId != nil && leagueCode != nil }

    var weekWins: Int {
        guard let league, let playerId else { return 0 }
        return league.standings.first { $0.playerId == playerId }?.wins ?? 0
    }

    var opponents: [LeaguePlayer] {
        (league?.players ?? []).filter { $0.playerId != playerId }
    }

    func join(code: String, name: String, emoji: String, auth0Sub: String?) async {
        errorMessage = nil
        do {
            let joined = try await api.join(leagueCode: code.uppercased(), name: name, emoji: emoji, auth0Sub: auth0Sub)
            playerId = joined.playerId
            leagueCode = joined.league.code
            playerName = name
            playerEmoji = emoji
            league = joined.league
            fighter = joined.league.players.first { $0.playerId == joined.playerId }?.fighter ?? .empty
            persist()
            listenForEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createLeague(named name: String) async -> String? {
        errorMessage = nil
        do {
            return try await api.createLeague(name: name)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func refresh() async {
        guard let playerId, let leagueCode else { return }
        errorMessage = nil
        do {
            async let fighterToday = api.fighterToday(playerId: playerId)
            async let leagueNow = api.league(code: leagueCode)
            fighter = try await fighterToday
            league = try await leagueNow
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func intake(_ kind: String) async {
        guard let playerId else { return }
        do {
            fighter = try await api.intake(playerId: playerId, kind: kind).fighter
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func apply(meal: MealResponse) {
        fighter = meal.fighter
    }

    func listenForEvents() {
        guard let leagueCode else { return }
        eventTask?.cancel()
        eventTask = Task {
            // The stream ends whenever the server closes the socket: 20 s of silence, a
            // Redis blip, or venue wifi. Reconnect and catch up from the API.
            while !Task.isCancelled {
                for await event in api.leagueEvents(code: leagueCode) {
                    switch event {
                    case .fighterUpdate(let updatedId, let updatedFighter):
                        if updatedId == playerId { fighter = updatedFighter }
                        await refresh()
                    case .fightEnded(let fight):
                        lastFight = fight
                        await refresh()
                    case .other:
                        break
                    }
                }
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(3))
                await refresh()
            }
        }
    }

    func leave() {
        eventTask?.cancel()
        playerId = nil
        leagueCode = nil
        league = nil
        fighter = .empty
        try? FileManager.default.removeItem(at: Self.stateURL)
    }

    private static var stateURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appending(path: "state.json")
    }

    private func persist() {
        guard let playerId, let leagueCode else { return }
        let state = Persisted(playerId: playerId, leagueCode: leagueCode, playerName: playerName, playerEmoji: playerEmoji)
        try? JSONEncoder.mealee.encode(state).write(to: Self.stateURL)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? JSONDecoder.mealee.decode(Persisted.self, from: data) else { return }
        playerId = state.playerId
        leagueCode = state.leagueCode
        playerName = state.playerName
        playerEmoji = state.playerEmoji
        Task {
            await refresh()
            listenForEvents()
        }
    }
}
