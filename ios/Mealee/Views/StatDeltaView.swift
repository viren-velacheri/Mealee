import SwiftUI

struct StatDeltaView: View {
    let before: FighterStats
    let after: FighterStats
    let onDone: () -> Void
    @State private var shown: FighterStats
    @State private var visibleReasons = 0
    @State private var celebrate = false

    init(before: FighterStats, after: FighterStats, onDone: @escaping () -> Void) {
        self.before = before
        self.after = after
        self.onDone = onDone
        _shown = State(initialValue: before)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 18) {
                Text("Your fighter grew").font(TypeScale.display).foregroundStyle(Palette.ink).padding(.top, 40)
                HStack(spacing: 8) {
                    Pill(text: "HP \(shown.hpMax)", tint: Palette.leaf)
                    if after.firstStrike && !before.firstStrike { Pill(text: "⚡ first strike unlocked", tint: Palette.sage) }
                }
                StatMeters(stats: shown).glassCard()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(after.reasons.prefix(visibleReasons).enumerated()), id: \.offset) { _, reason in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Palette.leaf).frame(width: 6, height: 6).padding(.top, 6)
                            StreamingText(text: reason, charactersPerSecond: 90, font: TypeScale.caption, color: Palette.slate)
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button { Haptics.tap(); onDone() } label: { Text("Done").primaryPill() }.buttonStyle(Pressable())
            }
            .padding(Layout.gutter)
            if celebrate { WinnerBurst(seed: UInt32(after.hpMax)) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            Haptics.success()
            withAnimation(Motion.settle) { shown = after }
            celebrate = true
            for _ in after.reasons {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(Motion.bounce) { visibleReasons += 1 }
            }
        }
    }
}
