import SwiftUI

struct StatMeter: View {
    let name: String
    let fraction: Double
    let display: String
    let tint: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(TypeScale.label).foregroundStyle(Palette.slate)
                Spacer()
                Text(display).font(TypeScale.number).foregroundStyle(Palette.ink).contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.mint.opacity(0.35))
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let seconds = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600))
                        Capsule()
                            .fill(LinearGradient(colors: tint, startPoint: .leading, endPoint: .trailing))
                            .colorEffect(ShaderLibrary.shimmer(.float(seconds), .boundingRect))
                    }
                    .frame(width: max(10, geo.size.width * min(1, max(0, fraction))))
                    .shadow(color: tint[0].opacity(0.5), radius: 6, y: 2)
                }
            }
            .frame(height: 10)
        }
        .animation(Motion.settle, value: fraction)
    }
}

struct StatMeters: View {
    let stats: FighterStats

    var body: some View {
        VStack(spacing: 14) {
            StatMeter(name: "Attack", fraction: stats.attack / 100, display: "\(Int(stats.attack + 0.5))", tint: Palette.attack)
            StatMeter(name: "Defense", fraction: stats.defense / 100, display: "\(Int(stats.defense + 0.5))", tint: Palette.defense)
            StatMeter(name: "Stamina", fraction: stats.stamina / 100, display: "\(Int(stats.stamina + 0.5))", tint: Palette.stamina)
            StatMeter(name: "Speed", fraction: stats.speed / 100, display: "\(Int(stats.speed + 0.5))", tint: Palette.speed)
            StatMeter(name: "Focus", fraction: stats.focus / 100, display: "\(Int(stats.focus + 0.5))", tint: Palette.focus)
            StatMeter(name: "Recovery", fraction: stats.recovery / 10, display: String(format: "%.1f", stats.recovery), tint: Palette.recovery)
        }
    }
}

// HP as a liquid bar with a spring, used in fights.
struct HPBar: View {
    let hp: Int
    let hpMax: Int

    private var fraction: Double { Double(max(0, hp)) / Double(max(1, hpMax)) }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.mint.opacity(0.4))
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let seconds = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600))
                        Capsule()
                            .fill(LinearGradient(colors: fraction < 0.3 ? [Palette.sage, Palette.slate] : [Palette.leaf, Palette.mint],
                                                 startPoint: .leading, endPoint: .trailing))
                            .colorEffect(ShaderLibrary.shimmer(.float(seconds), .boundingRect))
                    }
                    .frame(width: max(8, geo.size.width * fraction))
                }
            }
            .frame(height: 14)
            Text("\(max(0, hp))").font(TypeScale.number).foregroundStyle(Palette.ink).contentTransition(.numericText())
        }
        .animation(Motion.bounce, value: hp)
    }
}
