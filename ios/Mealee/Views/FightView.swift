import SwiftUI

struct FightView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = FightViewModel()

    var body: some View {
        Group {
            if viewModel.fight == nil {
                opponentPicker
            } else {
                playback
            }
        }
        .navigationTitle("Fight")
        .background(Color(white: 0.04).ignoresSafeArea())
    }

    private var opponentPicker: some View {
        List {
            Section {
                Button {
                    guard let opponent = appState.opponents.randomElement() else { return }
                    Task { await start(against: opponent.playerId) }
                } label: {
                    Label("Quick match", systemImage: "bolt.fill").font(.headline)
                }
                .disabled(appState.opponents.isEmpty || viewModel.isStarting)
            }
            Section("Pick an opponent") {
                ForEach(appState.opponents) { opponent in
                    Button { Task { await start(against: opponent.playerId) } } label: {
                        HStack {
                            Text(opponent.emoji).font(.title)
                            VStack(alignment: .leading) {
                                Text(opponent.name).font(.headline)
                                if let fighter = opponent.fighter {
                                    Text("ATK \(Int(fighter.attack + 0.5)) · DEF \(Int(fighter.defense + 0.5)) · HP \(fighter.hpMax)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if appState.opponents.isEmpty { Text("Nobody else in the league yet").foregroundStyle(.secondary) }
            }
            if let message = viewModel.errorMessage { Section { Text(message).foregroundStyle(.red) } }
        }
        .overlay { if viewModel.isStarting { ProgressView("Matching") } }
        .refreshable { await appState.refresh() }
    }

    private var playback: some View {
        VStack(spacing: 14) {
            if let fight = viewModel.fight {
                HStack(alignment: .top, spacing: 12) {
                    FighterCard(combatant: fight.a, hp: viewModel.aHp, tint: .orange)
                    FighterCard(combatant: fight.b, hp: viewModel.bHp, tint: .cyan)
                }
                Text(viewModel.callout).font(.title2.bold()).multilineTextAlignment(.center).frame(minHeight: 60)
                    .contentTransition(.numericText())
                ScrollViewReader { proxy in
                    List(viewModel.shownTurns) { turn in
                        HStack(alignment: .top) {
                            Text("t\(turn.turn)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30)
                            Text(turn.note).font(.callout)
                        }
                        .listRowBackground(turn.actor == "a" ? Color.orange.opacity(0.12) : Color.cyan.opacity(0.12))
                        .id(turn.id)
                    }
                    .scrollContentBackground(.hidden)
                    .onChange(of: viewModel.shownTurns.count) { _, _ in
                        if let last = viewModel.shownTurns.last { withAnimation { proxy.scrollTo(last.id) } }
                    }
                }
                HStack {
                    if viewModel.isPlaying {
                        Button("Skip") { viewModel.skip() }
                    } else {
                        Button("Fight again") { viewModel.fight = nil }
                        Button("Verify replay") { viewModel.verifyReplay() }
                        if let matches = viewModel.replayMatches {
                            Text(matches ? "✓ replayed on device" : "✗ replay differs").font(.caption)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onChange(of: appState.lastFight) { _, fight in
            if let fight, fight.fightId != viewModel.fight?.fightId, viewModel.isFinished { viewModel.load(fight) }
        }
    }

    private func start(against opponentId: String) async {
        guard let me = appState.playerId else { return }
        await viewModel.start(me: me, opponent: opponentId, api: appState.api)
    }
}

struct FighterCard: View {
    let combatant: Combatant
    let hp: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(combatant.emoji).font(.system(size: 44))
            Text(combatant.name).font(.headline).foregroundStyle(tint).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(hp * 10 < combatant.hpMax * 3 ? Color.red : Color.green)
                        .frame(width: geo.size.width * CGFloat(max(0, hp)) / CGFloat(combatant.hpMax))
                }
            }
            .frame(height: 12)
            .animation(.easeOut(duration: 0.35), value: hp)
            Text("\(hp) / \(combatant.hpMax)").font(.caption.monospacedDigit())
            Text("ATK \(combatant.attack) DEF \(combatant.defense) SPD \(combatant.speed) FOC \(combatant.focus)")
                .font(.caption2).foregroundStyle(.secondary)
            if combatant.firstStrike { Text("⚡ first strike").font(.caption2) }
            if let crash = combatant.crashTurn { Text("🍬 crash turn \(crash)").font(.caption2) }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
