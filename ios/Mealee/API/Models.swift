import Foundation

// Every struct mirrors a server response exactly. Decoded with convertFromSnakeCase.
// A field the server guarantees is non-optional here; a missing one is a visible error.

struct FighterStats: Codable, Equatable {
    let attack: Double
    let defense: Double
    let stamina: Double
    let speed: Double
    let focus: Double
    let recovery: Double
    let crashTurn: Int?
    let hpMax: Int
    let firstStrike: Bool
    let reasons: [String]

    static let empty = FighterStats(attack: 0, defense: 0, stamina: 0, speed: 50, focus: 70,
                                    recovery: 0, crashTurn: nil, hpMax: 100, firstStrike: false,
                                    reasons: ["Log a meal to build your fighter"])
}

struct DayTotals: Codable, Equatable {
    let kcal: Double
    let proteinG: Double
    let fiberG: Double
    let vegG: Double
    let addedSugarG: Double
    let caffeineMg: Double
    let waterMl: Double
    let sodiumMg: Double
}

struct ScaleReference: Codable, Equatable {
    let type: String
    let pxPerMm: Double
}

struct MealItem: Codable, Equatable, Identifiable {
    let itemId: String
    let label: String
    let fdcId: Int
    let grams: Double
    let gramsLow: Double
    let gramsHigh: Double
    let confidence: Double
    let polygon: [[Int]]
    let isNew: Bool

    var id: String { itemId }
}

struct MealResponse: Codable, Equatable {
    let mealId: String
    let imageW: Int
    let imageH: Int
    let imageUrl: String
    let items: [MealItem]
    let scale: ScaleReference
    let dayTotals: DayTotals
    let fighter: FighterStats
}

struct FoodSearchResult: Codable, Equatable, Identifiable {
    let fdcId: Int
    let label: String
    let source: String
    let kcal: Double
    let proteinG: Double
    let fiberG: Double
    let sodiumMg: Double
    let caffeineMg: Double

    var id: Int { fdcId }
}

struct FoodSearchResponse: Codable, Equatable {
    let items: [FoodSearchResult]
}

struct Combatant: Codable, Equatable {
    let playerId: String
    let name: String
    let emoji: String
    let attack: Int
    let defense: Int
    let stamina: Int
    let speed: Int
    let focus: Int
    let recoveryMilli: Int
    let hpMax: Int
    let crashTurn: Int?
    let firstStrike: Bool

    var simFighter: SimFighter {
        SimFighter(name: name, attack: attack, defense: defense, stamina: stamina, speed: speed,
                   focus: focus, recoveryMilli: recoveryMilli, hpMax: hpMax, crashTurn: crashTurn,
                   firstStrike: firstStrike)
    }

    // Truncating conversion shared with the server's combat_int. Never .rounded().
    static func from(playerId: String, name: String, emoji: String, stats: FighterStats) -> Combatant {
        Combatant(playerId: playerId, name: name, emoji: emoji,
                  attack: Int(stats.attack + 0.5), defense: Int(stats.defense + 0.5),
                  stamina: Int(stats.stamina + 0.5), speed: Int(stats.speed + 0.5),
                  focus: Int(stats.focus + 0.5),
                  recoveryMilli: BattleSim.recoveryMilli(fromHitPointsPerTurn: stats.recovery),
                  hpMax: stats.hpMax, crashTurn: stats.crashTurn, firstStrike: stats.firstStrike)
    }
}

struct FightResponse: Codable, Equatable {
    let fightId: String
    let seed: UInt32
    let kind: String
    let leagueCode: String
    let winnerId: String
    let createdAt: String
    let a: Combatant
    let b: Combatant
    let turns: [BattleTurn]
}

struct PlayerRef: Codable, Equatable, Identifiable {
    let playerId: String
    let name: String
    let emoji: String

    var id: String { playerId }
}

struct LeaguePlayer: Codable, Equatable, Identifiable {
    let playerId: String
    let name: String
    let emoji: String
    let discovered: Int
    let fighter: FighterStats?

    var id: String { playerId }
    var ref: PlayerRef { PlayerRef(playerId: playerId, name: name, emoji: emoji) }
}

struct Standing: Codable, Equatable, Identifiable {
    let playerId: String
    let name: String
    let emoji: String
    let wins: Int
    let damage: Int
    let rank: Int

    var id: String { playerId }
}

struct Matchup: Codable, Equatable, Identifiable {
    let a: PlayerRef
    let b: PlayerRef?

    var id: String { a.playerId + (b?.playerId ?? "bye") }
}

struct LeagueResponse: Codable, Equatable {
    let code: String
    let name: String
    let weekStart: String
    let players: [LeaguePlayer]
    let standings: [Standing]
    let tonight: [Matchup]
}

struct JoinResponse: Codable, Equatable {
    let playerId: String
    let league: LeagueResponse
}

struct IntakeResponse: Codable, Equatable {
    let dayTotals: DayTotals
    let fighter: FighterStats
}

struct Discovery: Codable, Equatable, Identifiable {
    let label: String
    let thumbnailUrl: String

    var id: String { label }
}

struct DiscoveriesResponse: Codable, Equatable {
    let weekStart: String
    let total: Int
    let discovered: [Discovery]
}

struct APIError: Codable, Error, LocalizedError, Equatable {
    let error: String
    let hint: String

    var errorDescription: String? { hint.isEmpty ? error : "\(error): \(hint)" }
}

enum LeagueEvent: Equatable {
    case fighterUpdate(playerId: String, fighter: FighterStats)
    case fightEnded(FightResponse)
    case other(String)
}

let foodClassLabels: [String] = [
    "pizza slice", "salad greens", "rice", "pasta", "chicken breast", "beef", "tofu", "eggs",
    "bread", "bagel", "fries", "burger", "sandwich", "banana", "apple", "orange", "grapes",
    "broccoli", "carrots", "beans", "yogurt", "cookie", "cake", "chips", "cereal", "soup",
    "sushi", "noodles", "cheese", "coffee",
]

let foodClassEmoji: [String: String] = [
    "pizza slice": "🍕", "salad greens": "🥬", "rice": "🍚", "pasta": "🍝", "chicken breast": "🍗",
    "beef": "🥩", "tofu": "🧊", "eggs": "🍳", "bread": "🍞", "bagel": "🥯", "fries": "🍟",
    "burger": "🍔", "sandwich": "🥪", "banana": "🍌", "apple": "🍎", "orange": "🍊",
    "grapes": "🍇", "broccoli": "🥦", "carrots": "🥕", "beans": "🫘", "yogurt": "🥛",
    "cookie": "🍪", "cake": "🍰", "chips": "🥔", "cereal": "🥣", "soup": "🍲", "sushi": "🍣",
    "noodles": "🍜", "cheese": "🧀", "coffee": "☕",
]

extension JSONDecoder {
    static let mealee: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

extension JSONEncoder {
    static let mealee: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
