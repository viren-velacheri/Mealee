import SwiftUI

// A wobbling line between two points in the unit square. The wave tapers to nothing at
// both ends so limbs stay attached to the body and to the ground.
struct Squiggle: Shape {
    var from: CGPoint
    var to: CGPoint
    var waves: Double = 2.5
    var amplitude: CGFloat = 7
    var phase: Double = 0

    func path(in rect: CGRect) -> Path {
        let start = CGPoint(x: from.x * rect.width, y: from.y * rect.height)
        let end = CGPoint(x: to.x * rect.width, y: to.y * rect.height)
        let run = end.x - start.x
        let rise = end.y - start.y
        let length = max(sqrt(run * run + rise * rise), 0.001)
        let normal = CGPoint(x: -rise / length, y: run / length)

        var path = Path()
        let steps = 26
        for step in 0...steps {
            let travel = Double(step) / Double(steps)
            let taper = sin(travel * .pi)
            let wave = sin(travel * .pi * waves * 2 + phase) * amplitude * taper
            let point = CGPoint(x: start.x + run * travel + normal.x * wave,
                                y: start.y + rise * travel + normal.y * wave)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

// The food emoji with four squiggly limbs. Nothing is drawn behind or over the emoji,
// so the food stays the character.
struct SquiggleBody: View {
    let emoji: String
    var limbWidth: CGFloat = 5
    var reach: CGFloat = 1
    var time: Double = 0
    var swing: Double = 1
    var emojiSize: CGFloat = 62

    var body: some View {
        ZStack {
            limb(from: CGPoint(x: 0.46, y: 0.34), to: CGPoint(x: 0.14, y: 0.52 * reach), phase: time * 3.1)
            limb(from: CGPoint(x: 0.54, y: 0.34), to: CGPoint(x: 0.90, y: 0.44 * reach), phase: time * 3.6 + 1.2)
            limb(from: CGPoint(x: 0.46, y: 0.48), to: CGPoint(x: 0.33, y: 0.96), phase: time * 2.4 + 2.1)
            limb(from: CGPoint(x: 0.55, y: 0.48), to: CGPoint(x: 0.69, y: 0.96), phase: time * 2.7 + 3.4)
            Text(emoji).font(.system(size: emojiSize)).offset(y: -30)
        }
        .frame(width: 150, height: 160)
    }

    private func limb(from: CGPoint, to: CGPoint, phase: Double) -> some View {
        Squiggle(from: from, to: to, amplitude: 7 * swing, phase: phase)
            .stroke(LinearGradient(colors: [Palette.ink, Palette.sage], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: limbWidth, lineCap: .round))
    }
}

struct SquiggleFighter: View {
    let combatant: Combatant
    var facingRight = true
    var lunge: CGFloat = 0
    var defeated = false

    private var limbWidth: CGFloat { 4 + min(CGFloat(combatant.defense), 60) * 0.05 }
    private var reach: CGFloat { 1 + min(Double(combatant.attack), 60) * 0.003 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let swing = defeated ? 0.4 : 1.0
            SquiggleBody(emoji: combatant.emoji, limbWidth: limbWidth, reach: reach,
                         time: time, swing: swing)
                .grayscale(defeated ? 1 : 0)
                .opacity(defeated ? 0.6 : 1)
                .rotationEffect(.degrees(defeated ? 74 : 0), anchor: .bottom)
                .scaleEffect(x: facingRight ? 1 : -1)
        }
        .offset(x: (facingRight ? 1 : -1) * lunge * 42, y: -lunge * 10)
        .animation(Motion.snappy, value: lunge)
        .animation(Motion.bounce, value: defeated)
    }

}

// Name and HP sit beside the fighter rather than in a card, so the arena reads as one
// scene instead of two panels.
struct ArenaNameplate: View {
    let combatant: Combatant
    let hp: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(combatant.name).font(TypeScale.label).foregroundStyle(Palette.ink).lineLimit(1)
                if combatant.firstStrike { Text("⚡").font(TypeScale.caption) }
                if let crash = combatant.crashTurn { Text("🍬t\(crash)").font(TypeScale.caption) }
            }
            HPBar(hp: hp, hpMax: combatant.hpMax)
        }
        .frame(width: 150)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
    }
}

// The ground each fighter stands on. Sells the fake perspective: the far fighter's
// shadow is smaller and fainter.
struct GroundShadow: View {
    var width: CGFloat

    var body: some View {
        Ellipse()
            .fill(RadialGradient(colors: [Palette.sage.opacity(0.35), .clear],
                                 center: .center, startRadius: 2, endRadius: width * 0.6))
            .frame(width: width, height: width * 0.26)
    }
}
