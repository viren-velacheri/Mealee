import Foundation

// Port of server/app/battle.py. The two must produce identical turn logs for the same
// seed and fighters; BattleSimTests pins them to ios/Mealee/Fixtures/battle_fixtures.json.
// All combat arithmetic is integer so the two languages cannot drift in a low bit.

struct Mulberry32 {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func nextU32() -> UInt32 {
        state = state &+ 0x6D2B79F5
        var t = (state ^ (state >> 15)) &* (state | 1)
        t = ((t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t)
        return t ^ (t >> 14)
    }
}

func seedFromFightID(_ fightID: String) -> UInt32 {
    var hash: UInt32 = 0x811C9DC5
    for byte in fightID.utf8 {
        hash = (hash ^ UInt32(byte)) &* 0x01000193
    }
    return hash
}

struct SimFighter: Codable, Equatable {
    let name: String
    let attack: Int
    let defense: Int
    let stamina: Int
    let speed: Int
    let focus: Int
    let recoveryMilli: Int
    let hpMax: Int
    let crashTurn: Int?
    let firstStrike: Bool
}

struct BattleTurn: Codable, Equatable, Identifiable {
    let turn: Int
    let actor: String
    let action: String
    let damage: Int
    let aHp: Int
    let bHp: Int
    let note: String

    var id: String { "\(turn)-\(actor)-\(action)-\(aHp)-\(bHp)" }
}

struct BattleResult: Codable, Equatable {
    let seed: UInt32
    let winner: String
    let aHp: Int
    let bHp: Int
    let turns: [BattleTurn]
}

enum BattleSim {
    static let maxTurns = 20

    // Truncating rather than rounding, matching int(recovery * 1000 + 0.5) on the server.
    // Swift .rounded() and Python round() disagree on exact halves.
    static func recoveryMilli(fromHitPointsPerTurn recovery: Double) -> Int {
        Int(recovery * 1000 + 0.5)
    }

    static func displayHP(milli: Int) -> Int {
        milli <= 0 ? 0 : (milli + 500) / 1000
    }

    static func simulate(seed: UInt32, fighterA: SimFighter, fighterB: SimFighter) -> BattleResult {
        var rng = Mulberry32(seed: seed)
        var speed = ["a": fighterA.speed, "b": fighterB.speed]
        var hpMilli = ["a": fighterA.hpMax * 1000, "b": fighterB.hpMax * 1000]
        let hpMaxMilli = ["a": fighterA.hpMax * 1000, "b": fighterB.hpMax * 1000]
        let fighters = ["a": fighterA, "b": fighterB]

        var turns: [BattleTurn] = []
        var winner: String?

        func log(_ turn: Int, _ actor: String, _ action: String, _ damageMilli: Int, _ note: String) {
            turns.append(BattleTurn(
                turn: turn,
                actor: actor,
                action: action,
                damage: displayHP(milli: damageMilli),
                aHp: displayHP(milli: hpMilli["a"]!),
                bHp: displayHP(milli: hpMilli["b"]!),
                note: note
            ))
        }

        for turn in 1...maxTurns {
            let order: [String]
            if fighterA.firstStrike != fighterB.firstStrike {
                order = fighterA.firstStrike ? ["a", "b"] : ["b", "a"]
            } else if speed["a"]! != speed["b"]! {
                order = speed["a"]! > speed["b"]! ? ["a", "b"] : ["b", "a"]
            } else {
                order = seed % 2 == 0 ? ["a", "b"] : ["b", "a"]
            }

            for actor in order {
                let target = actor == "a" ? "b" : "a"
                let attacker = fighters[actor]!

                if attacker.crashTurn == turn {
                    speed[actor] = speed[actor]! / 2
                    log(turn, actor, "crash", 0, "Sugar crash: speed halved to \(speed[actor]!)")
                }

                if Int(rng.nextU32() % 1000) < attacker.focus * 10 {
                    let variance = 850 + Int(rng.nextU32() % 300)
                    let damageMilli = attacker.attack * (200 - fighters[target]!.defense) * variance / 200
                    hpMilli[target]! -= damageMilli
                    log(turn, actor, "hit", damageMilli,
                        "\(attacker.name) hits for \(displayHP(milli: damageMilli))")
                } else {
                    log(turn, actor, "miss", 0, "\(attacker.name) misses")
                }

                if hpMilli[target]! <= 0 {
                    hpMilli[target] = 0
                    winner = actor
                    break
                }
            }

            if winner != nil { break }

            for actor in ["a", "b"] {
                let healed = min(fighters[actor]!.recoveryMilli, hpMaxMilli[actor]! - hpMilli[actor]!)
                if healed <= 0 { continue }
                hpMilli[actor]! += healed
                log(turn, actor, "recover", 0,
                    "\(fighters[actor]!.name) recovers \(displayHP(milli: healed))")
            }
        }

        if winner == nil {
            let left = hpMilli["a"]! * hpMaxMilli["b"]!
            let right = hpMilli["b"]! * hpMaxMilli["a"]!
            if left != right {
                winner = left > right ? "a" : "b"
            } else {
                winner = seed % 2 == 0 ? "a" : "b"
            }
        }

        return BattleResult(
            seed: seed,
            winner: winner!,
            aHp: displayHP(milli: hpMilli["a"]!),
            bHp: displayHP(milli: hpMilli["b"]!),
            turns: turns
        )
    }
}
