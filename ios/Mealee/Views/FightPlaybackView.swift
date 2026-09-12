import SwiftUI

struct FightPlaybackView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: FightViewModel

    var body: some View {
        VStack(spacing: 14) {
            if let fight = viewModel.fight {
                HStack(alignment: .top, spacing: 12) {
                    FighterCard(combatant: fight.a, hp: viewModel.aHp, hits: viewModel.aHits, leading: viewModel.aHp >= viewModel.bHp)
                    FighterCard(combatant: fight.b, hp: viewModel.bHp, hits: viewModel.bHits, leading: viewModel.bHp > viewModel.aHp)
                }
                callout
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.shownTurns) { turn in
                                TurnRow(turn: turn, streams: turn.id == viewModel.shownTurns.last?.id)
                                    .id(turn.id)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .glassCard(tint: Palette.mist, padding: 12)
                    .animation(Motion.settle, value: viewModel.shownTurns.count)
                    .onChange(of: viewModel.shownTurns.count) { _, _ in
                        if let last = viewModel.shownTurns.last { withAnimation(Motion.settle) { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                controls
            }
        }
        .padding(Layout.gutter)
        .overlay {
            if viewModel.isFinished, let fight = viewModel.fight { WinnerBurst(seed: fight.seed) }
        }
        .onChange(of: appState.lastFight) { _, fight in
            if let fight, fight.fightId != viewModel.fight?.fightId, viewModel.isFinished { viewModel.load(fight) }
        }
    }

    private var callout: some View {
        ZStack {
            if let damage = viewModel.lastDamage, viewModel.isPlaying {
                PopNumber(value: damage, prefix: "-").id(viewModel.shownTurns.count)
            } else {
                Text(viewModel.callout).font(viewModel.isFinished ? TypeScale.title : TypeScale.heading)
                    .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(minHeight: 56)
        .animation(Motion.bounce, value: viewModel.callout)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if viewModel.isPlaying {
                Button { Haptics.tap(); viewModel.skip() } label: { Text("Skip").primaryPill(filled: false) }
            } else {
                Button { Haptics.tap(); viewModel.fight = nil } label: { Text("Fight again").primaryPill() }
                Button { Haptics.tap(); viewModel.verifyReplay() } label: {
                    Text(viewModel.replayMatches.map { $0 ? "✓ replayed on device" : "✗ replay differs" } ?? "Verify replay")
                        .primaryPill(filled: false)
                }
            }
        }
        .buttonStyle(Pressable())
    }
}
