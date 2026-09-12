import SwiftUI

struct FightPlaybackView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: FightViewModel

    // Whoever acted on the most recent shown turn is mid-lunge.
    private var attacker: String? { viewModel.isPlaying ? viewModel.shownTurns.last?.actor : nil }
    private var defender: String? { attacker.map { $0 == "a" ? "b" : "a" } }

    var body: some View {
        VStack(spacing: 12) {
            if let fight = viewModel.fight {
                arena(fight)
                callout
                log
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

    // Depth is faked the way a battle screen does it: the far fighter sits higher and
    // smaller, the near fighter lower and full size.
    private func arena(_ fight: FightResponse) -> some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Spacer(minLength: 0)
                    far(fight.b)
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom) {
                    near(fight.a)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func far(_ combatant: Combatant) -> some View {
        VStack(spacing: 2) {
            ArenaNameplate(combatant: combatant, hp: viewModel.bHp)
            ZStack(alignment: .bottom) {
                GroundShadow(width: 96)
                SquiggleFighter(combatant: combatant, facingRight: false,
                                lunge: attacker == "b" ? 1 : 0, defeated: viewModel.bHp <= 0)
                    .modifier(Shake(hits: CGFloat(viewModel.bHits)))
                    .animation(.easeOut(duration: 0.4), value: viewModel.bHits)
                damagePop(over: "b")
            }
        }
        .scaleEffect(0.72, anchor: .bottom)
        .frame(height: 150)
    }

    private func near(_ combatant: Combatant) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                GroundShadow(width: 132)
                SquiggleFighter(combatant: combatant, facingRight: true,
                                lunge: attacker == "a" ? 1 : 0, defeated: viewModel.aHp <= 0)
                    .modifier(Shake(hits: CGFloat(viewModel.aHits)))
                    .animation(.easeOut(duration: 0.4), value: viewModel.aHits)
                damagePop(over: "a")
            }
            ArenaNameplate(combatant: combatant, hp: viewModel.aHp)
        }
    }

    @ViewBuilder
    private func damagePop(over side: String) -> some View {
        if let damage = viewModel.lastDamage, viewModel.isPlaying, defender == side {
            PopNumber(value: damage, prefix: "-")
                .id(viewModel.shownTurns.count)
                .offset(y: -150)
        }
    }

    private var callout: some View {
        Text(viewModel.callout)
            .font(viewModel.isFinished ? TypeScale.title : TypeScale.heading)
            .foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            .contentTransition(.numericText())
            .frame(minHeight: 34)
            .animation(Motion.bounce, value: viewModel.callout)
    }

    private var log: some View {
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
            .frame(maxHeight: 132)
            .glassCard(tint: Palette.mist, padding: 12)
            .animation(Motion.settle, value: viewModel.shownTurns.count)
            .onChange(of: viewModel.shownTurns.count) { _, _ in
                if let last = viewModel.shownTurns.last { withAnimation(Motion.settle) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
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
