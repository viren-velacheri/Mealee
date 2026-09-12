import SwiftUI

struct StatBarsView: View {
    let stats: FighterStats

    private var rows: [(String, Double, Color)] {
        [("Attack", stats.attack, .red), ("Defense", stats.defense, .green),
         ("Stamina", stats.stamina, .yellow), ("Speed", stats.speed, .cyan),
         ("Focus", stats.focus, .purple), ("Recovery", stats.recovery * 10, .blue)]
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.0) { name, value, color in
                HStack {
                    Text(name).font(.subheadline.weight(.semibold)).frame(width: 84, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(color.gradient)
                                .frame(width: geo.size.width * min(1, max(0, value / 100)))
                        }
                    }
                    .frame(height: 14)
                    Text(name == "Recovery" ? String(format: "%.1f", stats.recovery) : "\(Int(value + 0.5))")
                        .font(.subheadline.monospacedDigit()).frame(width: 40, alignment: .trailing)
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: stats)
    }
}

struct FighterSpriteView: View {
    let stats: FighterStats
    let emoji: String

    var body: some View {
        ZStack {
            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height * 0.62)
                let bulk = 0.55 + stats.attack / 250
                let height = 0.5 + stats.stamina / 300
                var body = Path()
                body.addEllipse(in: CGRect(x: centre.x - 40 * bulk, y: centre.y - 70 * height,
                                           width: 80 * bulk, height: 110 * height))
                context.fill(body, with: .linearGradient(
                    Gradient(colors: [.orange, .red.opacity(0.7)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                var shield = Path()
                shield.addArc(center: CGPoint(x: centre.x + 48 * bulk, y: centre.y - 10), radius: 14 + stats.defense / 8,
                              startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                context.stroke(shield, with: .color(.green.opacity(0.85)), lineWidth: 4)
            }
            Text(emoji).font(.system(size: 54)).offset(y: -48)
            if stats.firstStrike {
                Text("⚡").font(.title).offset(x: 60, y: -60)
            }
        }
        .frame(height: 190)
    }
}
