import Foundation
import Observation

@Observable
@MainActor
final class FightViewModel {
    var fight: FightResponse?
    var shownTurns: [BattleTurn] = []
    var aHp = 0
    var bHp = 0
    var callout = ""
    var lastDamage: Int?
    var aHits = 0
    var bHits = 0
    var isPlaying = false
    var isFinished = false
    var replayMatches: Bool?
    var errorMessage: String?
    var isStarting = false

    private var playback: Task<Void, Never>?

    func start(me: String, opponent: String, api: MealeeAPI) async {
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }
        do {
            load(try await api.startFight(aPlayerId: me, bPlayerId: opponent))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load(_ fight: FightResponse) {
        playback?.cancel()
        self.fight = fight
        shownTurns = []
        aHp = fight.a.hpMax
        bHp = fight.b.hpMax
        callout = "\(fight.a.name) vs \(fight.b.name)"
        lastDamage = nil
        aHits = 0
        bHits = 0
        isFinished = false
        replayMatches = nil
        play(fight)
    }

    private func play(_ fight: FightResponse) {
        isPlaying = true
        let interval = min(0.9, max(0.25, 20.0 / Double(max(1, fight.turns.count))))
        playback = Task {
            for turn in fight.turns {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                shownTurns.append(turn)
                aHp = turn.aHp
                bHp = turn.bHp
                lastDamage = turn.action == "hit" ? turn.damage : nil
                if turn.action == "hit" {
                    if turn.actor == "a" { bHits += 1 } else { aHits += 1 }
                }
                switch turn.action {
                case "hit": callout = "\(turn.damage) damage"
                case "miss": callout = "miss"
                case "crash": callout = "Sugar crash: speed halved"
                default: callout = turn.note
                }
            }
            let winner = fight.winnerId == fight.a.playerId ? fight.a : fight.b
            callout = "\(winner.emoji) \(winner.name) wins"
            isPlaying = false
            isFinished = true
        }
    }

    func skip() {
        guard let fight else { return }
        playback?.cancel()
        shownTurns = fight.turns
        aHp = fight.turns.last?.aHp ?? fight.a.hpMax
        bHp = fight.turns.last?.bHp ?? fight.b.hpMax
        let winner = fight.winnerId == fight.a.playerId ? fight.a : fight.b
        callout = "\(winner.emoji) \(winner.name) wins"
        isPlaying = false
        isFinished = true
    }

    // Proves the phone can reproduce the server's fight from the seed alone.
    func verifyReplay() {
        guard let fight else { return }
        let replay = BattleSim.simulate(seed: fight.seed, fighterA: fight.a.simFighter, fighterB: fight.b.simFighter)
        replayMatches = replay.turns == fight.turns
    }
}
