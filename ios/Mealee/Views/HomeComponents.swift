import SwiftUI

struct FighterHeroCard: View {
    let stats: FighterStats
    let name: String
    let emoji: String
    let wins: Int
    let offline: Bool

    var body: some View {
        VStack(spacing: 10) {
            FighterSpriteView(stats: stats, emoji: emoji)
            Text(name).font(TypeScale.title).foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                Pill(text: "HP \(stats.hpMax)", tint: Palette.leaf)
                Pill(text: "\(wins) W this week", tint: Palette.mint)
                if stats.firstStrike { Pill(text: "⚡ first strike", tint: Palette.sage) }
                if offline { Pill(text: "offline", tint: Palette.slate) }
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(tint: Palette.mint)
    }
}

struct Pill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text).font(TypeScale.label).foregroundStyle(Palette.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
    }
}

// The fighter breathes, and can be tugged around and let go: it snaps back with a thud.
struct FighterSpriteView: View {
    let stats: FighterStats
    let emoji: String
    @State private var drag: CGSize = .zero

    private func rubber(_ value: CGFloat) -> CGFloat {
        let limit: CGFloat = 56
        return limit * tanh(value / limit)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breath = 1 + 0.02 * sin(time * 1.6)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.leaf.opacity(0.5), Palette.mint.opacity(0.0)],
                                         center: .center, startRadius: 10, endRadius: 110))
                    .frame(width: 220, height: 220)
                    .scaleEffect(breath * (0.85 + stats.stamina / 400))
                GroundShadow(width: 128).offset(y: 74)
                SquiggleBody(emoji: emoji, limbWidth: 4 + min(stats.defense, 60) * 0.05,
                             reach: 1 + min(stats.attack, 60) * 0.003, time: time)
                    .scaleEffect(breath)
            }
        }
        .frame(height: 210)
        .offset(drag)
        .rotationEffect(.degrees(drag.width / 10))
        .gesture(
            DragGesture()
                .onChanged { value in drag = CGSize(width: rubber(value.translation.width), height: rubber(value.translation.height)) }
                .onEnded { _ in
                    Haptics.thud()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.42)) { drag = .zero }
                }
        )
    }
}

struct ReasonList: View {
    let reasons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Palette.leaf).frame(width: 6, height: 6).padding(.top, 7)
                    StreamingText(text: reason, charactersPerSecond: 90, font: TypeScale.caption, color: Palette.slate)
                }
            }
        }
    }
}

struct IntakeChips: View {
    @Environment(AppState.self) private var appState
    @State private var waterBounce = 0
    @State private var coffeeBounce = 0

    var body: some View {
        HStack(spacing: 12) {
            chip("💧", "Water", "+250 ml", bounce: waterBounce) {
                waterBounce += 1
                Task { await appState.intake("water") }
            }
            chip("☕", "Coffee", "+1 cup", bounce: coffeeBounce) {
                coffeeBounce += 1
                Task { await appState.intake("coffee") }
            }
        }
    }

    private func chip(_ icon: String, _ title: String, _ subtitle: String, bounce: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(icon).font(.system(size: 26))
                    .scaleEffect(bounce % 2 == 0 ? 1 : 1.25)
                    .animation(Motion.bounce, value: bounce)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(TypeScale.heading).foregroundStyle(Palette.ink)
                    Text(subtitle).font(TypeScale.caption).foregroundStyle(Palette.slate)
                }
                Spacer()
            }
            .glassCard(tint: Palette.mint, padding: 14)
        }
        .buttonStyle(Pressable())
        .sensoryFeedback(.impact(weight: .medium), trigger: bounce)
    }
}
