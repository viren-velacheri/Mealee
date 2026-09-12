import SwiftUI

// Who has found the most food this week. The League tab ranks by wins; this ranks by
// discovery, which is the thing Foodex is about.
struct FoodexLeaderboard: View {
    let players: [LeaguePlayer]
    let meId: String?

    private var ranked: [LeaguePlayer] {
        players.sorted {
            $0.discovered == $1.discovered ? $0.name < $1.name : $0.discovered > $1.discovered
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Explorers").font(TypeScale.heading).foregroundStyle(Palette.ink)
                Spacer()
                Text("this week").font(TypeScale.caption).foregroundStyle(Palette.muted)
            }
            if ranked.isEmpty {
                Notice(kind: .guidance, text: "Nobody has found anything yet. Log a meal to get on the board.")
            } else {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { place, player in
                    LeaderboardRow(place: place + 1, player: player, isMe: player.playerId == meId)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct LeaderboardRow: View {
    let place: Int
    let player: LeaguePlayer
    let isMe: Bool

    // Gold, silver and bronze read as medals without leaving the palette's temperature.
    private var medal: Color? {
        switch place {
        case 1: Color(hex: 0xE8C15A)
        case 2: Color(hex: 0xC2CBD2)
        case 3: Color(hex: 0xCE9A6B)
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(medal ?? Palette.mint.opacity(0.5)).frame(width: 28, height: 28)
                Text("\(place)").font(TypeScale.label).foregroundStyle(Palette.ink)
            }
            Text(player.emoji).font(.system(size: 26))
            Text(isMe ? "\(player.name) (you)" : player.name)
                .font(TypeScale.body).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(player.discovered)").font(TypeScale.number).foregroundStyle(Palette.ink)
            Text("found").font(TypeScale.caption).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background {
            if isMe {
                RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous)
                    .fill(Palette.leaf.opacity(0.3))
                    .overlay(RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place). \(player.name)\(isMe ? ", you" : "")")
        .accessibilityValue("\(player.discovered) foods found")
    }
}
