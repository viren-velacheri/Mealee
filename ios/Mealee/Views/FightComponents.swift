import SwiftUI

struct OpponentCard: View {
    let player: LeaguePlayer
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(player.emoji).font(.system(size: 52))
            Text(player.name).font(TypeScale.heading).foregroundStyle(Palette.ink).lineLimit(1)
            if let fighter = player.fighter {
                HStack(spacing: 10) {
                    mini("ATK", Int(fighter.attack + 0.5))
                    mini("DEF", Int(fighter.defense + 0.5))
                    mini("HP", fighter.hpMax)
                }
            } else {
                Text("no meals yet").font(TypeScale.caption).foregroundStyle(Palette.slate)
            }
        }
        .frame(width: 150)
        .glassCard(tint: selected ? Palette.leaf : Palette.mint, padding: 16)
        .overlay(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous)
            .strokeBorder(Palette.leaf, lineWidth: selected ? 2 : 0))
        .scaleEffect(selected ? 1.04 : 1)
        .animation(Motion.bounce, value: selected)
    }

    private func mini(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(value)").font(TypeScale.number).foregroundStyle(Palette.ink)
            Text(label).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Palette.slate)
        }
    }
}

// Sideways shake driven by a counter, so every hit lands visibly on the target.
struct Shake: GeometryEffect {
    var hits: CGFloat
    var animatableData: CGFloat {
        get { hits }
        set { hits = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let fraction = hits - floor(hits)
        let offset = 9 * sin(fraction * .pi * 3) * (1 - fraction)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

struct FighterCard: View {
    let combatant: Combatant
    let hp: Int
    let hits: Int
    let leading: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(combatant.emoji).font(.system(size: 48))
                .scaleEffect(hp <= 0 ? 0.7 : 1).grayscale(hp <= 0 ? 1 : 0)
                .animation(Motion.bounce, value: hp <= 0)
            Text(combatant.name).font(TypeScale.heading).foregroundStyle(Palette.ink).lineLimit(1)
            HPBar(hp: hp, hpMax: combatant.hpMax)
            HStack(spacing: 6) {
                if combatant.firstStrike { Pill(text: "⚡", tint: Palette.sage) }
                if let crash = combatant.crashTurn { Pill(text: "🍬 t\(crash)", tint: Palette.mint) }
            }
            .frame(height: 24)
        }
        .frame(maxWidth: .infinity)
        .glassCard(tint: leading ? Palette.leaf : Palette.sage, padding: 14)
        .modifier(Shake(hits: CGFloat(hits)))
        .animation(.easeOut(duration: 0.4), value: hits)
    }
}

struct TurnRow: View {
    let turn: BattleTurn
    let streams: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("t\(turn.turn)").font(TypeScale.label).foregroundStyle(Palette.slate).frame(width: 26, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(turn.actor == "a" ? Palette.leaf : Palette.sage).frame(width: 3, height: 18)
            if streams {
                StreamingText(text: turn.note, charactersPerSecond: 80)
            } else {
                Text(turn.note).font(TypeScale.body).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// A short shower of palette dots for the winner. Deterministic from the seed so it
// looks the same on both phones.
struct WinnerBurst: View {
    let seed: UInt32
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { canvasContext, size in
                var rng = Mulberry32(seed: seed)
                let colors = [Palette.leaf, Palette.mint, Palette.sage, Palette.slate]
                for index in 0..<48 {
                    let angle = Double(rng.nextU32() % 3600) / 10 * .pi / 180
                    let speed = 180 + Double(rng.nextU32() % 160)
                    let life = min(1, elapsed / 1.3)
                    let x = size.width / 2 + cos(angle) * speed * life
                    let y = size.height * 0.35 + sin(angle) * speed * life + 380 * life * life
                    let radius = 4 + Double(index % 3) * 2
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    canvasContext.opacity = 1 - life
                    canvasContext.fill(Path(ellipseIn: rect), with: .color(colors[index % colors.count]))
                }
            }
            .opacity(elapsed < 1.3 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}
