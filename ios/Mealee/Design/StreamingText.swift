import SwiftUI

// Reveals text a character at a time with a soft glowing head, the way a fight log line
// should land: felt, not dumped. Respects reduced motion by showing the whole line.
struct StreamingText: View {
    let text: String
    var charactersPerSecond: Double = 60
    var font: Font = TypeScale.body
    var color: Color = Palette.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        HStack(spacing: 0) {
            Text(String(text.prefix(shown))).font(font).foregroundStyle(color)
            if shown < text.count {
                Circle().fill(Palette.leaf).frame(width: 6, height: 6)
                    .shadow(color: Palette.leaf, radius: 6)
                    .padding(.leading, 2)
            }
        }
        .task(id: text) {
            if reduceMotion { shown = text.count; return }
            shown = 0
            let step = UInt64(1_000_000_000 / charactersPerSecond)
            while shown < text.count {
                try? await Task.sleep(nanoseconds: step)
                shown += 1
            }
        }
    }
}

// A number that lands with a bounce and a leaf glow, for damage and stat changes.
struct PopNumber: View {
    let value: Int
    var prefix = ""
    @State private var landed = false

    var body: some View {
        Text("\(prefix)\(value)")
            .font(TypeScale.bigNumber).foregroundStyle(Palette.ink)
            .shadow(color: Palette.leaf.opacity(landed ? 0.0 : 0.9), radius: landed ? 2 : 18)
            .scaleEffect(landed ? 1 : 1.7)
            .opacity(landed ? 1 : 0.2)
            .onAppear { withAnimation(Motion.bounce) { landed = true } }
    }
}
