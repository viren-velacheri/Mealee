import Foundation

final class LiveAPI: MealeeAPI {
    let isMock = false
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    private func request(_ path: String, method: String = "GET", body: Encodable? = nil,
                         timeout: TimeInterval = 5) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.mealee.encode(body)
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let apiError = try? JSONDecoder.mealee.decode(APIError.self, from: data) { throw apiError }
            throw APIError(error: "http \(status)", hint: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder.mealee.decode(T.self, from: data)
    }

    func createLeague(name: String) async throws -> String {
        struct Body: Encodable { let name: String }
        struct Reply: Decodable { let code: String }
        let reply: Reply = try await send(try request("/leagues", method: "POST", body: Body(name: name)))
        return reply.code
    }

    func join(leagueCode: String, name: String, emoji: String, auth0Sub: String?) async throws -> JoinResponse {
        struct Body: Encodable { let leagueCode: String; let name: String; let emoji: String; let auth0Sub: String? }
        return try await send(try request("/players", method: "POST",
                                          body: Body(leagueCode: leagueCode, name: name, emoji: emoji, auth0Sub: auth0Sub)))
    }

    func league(code: String) async throws -> LeagueResponse {
        try await send(try request("/leagues/\(code)"))
    }

    func uploadMeal(playerId: String, jpeg: Data) async throws -> MealResponse {
        let boundary = "mealee-\(UUID().uuidString)"
        var request = try request("/meals", method: "POST", timeout: 10)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"player_id\"\r\n\r\n\(playerId)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"plate.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return try await send(request)
    }

    func relabel(mealId: String, itemId: String, label: String) async throws -> MealResponse {
        struct Body: Encodable { let label: String }
        return try await send(try request("/meals/\(mealId)/items/\(itemId)", method: "PATCH", body: Body(label: label)))
    }

    func confirmMeal(mealId: String) async throws -> MealResponse {
        try await send(try request("/meals/\(mealId)/confirm", method: "POST"))
    }

    func discardMeal(mealId: String) async throws {
        struct Reply: Decodable { let ok: Bool }
        let reply: Reply = try await send(try request("/meals/\(mealId)", method: "DELETE"))
        guard reply.ok else { throw APIError(error: "discard failed", hint: "Try again.") }
    }

    func intake(playerId: String, kind: String) async throws -> IntakeResponse {
        struct Body: Encodable { let playerId: String; let kind: String }
        return try await send(try request("/intake", method: "POST", body: Body(playerId: playerId, kind: kind)))
    }

    func fighterToday(playerId: String) async throws -> FighterStats {
        try await send(try request("/fighters/\(playerId)/today"))
    }

    func startFight(aPlayerId: String, bPlayerId: String) async throws -> FightResponse {
        struct Body: Encodable { let aPlayerId: String; let bPlayerId: String; let kind: String }
        return try await send(try request("/fights", method: "POST",
                                          body: Body(aPlayerId: aPlayerId, bPlayerId: bPlayerId, kind: "quick")))
    }

    func fight(id: String) async throws -> FightResponse {
        try await send(try request("/fights/\(id)"))
    }

    func discoveries(playerId: String) async throws -> DiscoveriesResponse {
        try await send(try request("/players/\(playerId)/discoveries"))
    }

    func imageURL(path: String) -> URL? {
        baseURL.appending(path: path)
    }

    func leagueEvents(code: String) -> AsyncStream<LeagueEvent> {
        AsyncStream { continuation in
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            components.scheme = components.scheme == "https" ? "wss" : "ws"
            components.path = "/ws/league/\(code)"
            let task = session.webSocketTask(with: components.url!)
            task.resume()

            let pinger = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    try? await task.send(.string("ping"))
                }
            }
            let reader = Task {
                while !Task.isCancelled {
                    guard let message = try? await task.receive(),
                          case .string(let text) = message,
                          let data = text.data(using: .utf8) else { break }
                    continuation.yield(Self.decodeEvent(data))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                pinger.cancel()
                reader.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private static func decodeEvent(_ data: Data) -> LeagueEvent {
        struct Envelope: Decodable { let type: String; let playerId: String?; let fighter: FighterStats?; let fight: FightResponse? }
        guard let envelope = try? JSONDecoder.mealee.decode(Envelope.self, from: data) else { return .other("undecodable") }
        switch envelope.type {
        case "fighter_update":
            if let playerId = envelope.playerId, let fighter = envelope.fighter { return .fighterUpdate(playerId: playerId, fighter: fighter) }
        case "fight_ended":
            if let fight = envelope.fight { return .fightEnded(fight) }
        default: break
        }
        return .other(envelope.type)
    }
}
