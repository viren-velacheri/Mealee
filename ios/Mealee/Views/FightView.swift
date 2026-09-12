import SwiftUI

struct FightView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = FightViewModel()

    var body: some View {
        ZStack {
            AuroraBackground()
            if viewModel.fight == nil {
                picker.transition(.liquid)
            } else {
                FightPlaybackView(viewModel: viewModel).transition(.liquid)
            }
        }
        .animation(Motion.settle, value: viewModel.fight == nil)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        // The challenged phone has to play the fight too, whichever screen it was on.
        .task { await appState.refresh() }
        .onChange(of: appState.lastFight) { _, fight in
            guard let fight, fight.fightId != viewModel.fight?.fightId, isMine(fight) else { return }
            if viewModel.fight == nil || viewModel.isFinished {
                Haptics.thud()
                viewModel.load(fight)
            }
        }
    }

    private func isMine(_ fight: FightResponse) -> Bool {
        guard let playerId = appState.playerId else { return false }
        return fight.a.playerId == playerId || fight.b.playerId == playerId
    }

    // A vertical list, one tap to fight. The old horizontal card rail fought three
    // gestures at once: its own scroll, a swipe-up-to-fight per card, and the tab swipe.
    private var picker: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                Text("Choose a rival").font(TypeScale.display).foregroundStyle(Palette.ink).padding(.top, 8)
                Text("Tap anyone to fight them").font(TypeScale.caption).foregroundStyle(Palette.muted)

                if appState.opponents.isEmpty {
                    Notice(kind: .guidance, text: "Nobody else has entered the arena yet. Pull down to refresh.")
                        .padding(.horizontal, Layout.gutter)
                } else {
                    VStack(spacing: 8) {
                        ForEach(rivals) { rival in
                            RivalRow(player: rival, busy: viewModel.isStarting) {
                                Haptics.thud()
                                Task { await start(against: rival.playerId) }
                            }
                        }
                    }
                    .padding(.horizontal, Layout.gutter)
                }

                if let message = viewModel.errorMessage {
                    Notice(kind: .problem, text: message).padding(.horizontal, Layout.gutter)
                }

                if appState.opponents.count > 1 {
                    Button {
                        guard let any = appState.opponents.randomElement()?.playerId else { return }
                        Haptics.tap()
                        Task { await start(against: any) }
                    } label: {
                        Label("Quick match", systemImage: "shuffle").primaryPill(filled: false)
                    }
                    .buttonStyle(Pressable())
                    .disabled(viewModel.isStarting)
                    .padding(.horizontal, Layout.gutter).padding(.top, 4)
                }
            }
            .padding(.bottom, 20)
        }
        .overlay { if viewModel.isStarting { ProgressView().tint(Palette.leaf).scaleEffect(1.4) } }
        .refreshable { await appState.refresh() }
    }

    // Strongest first, so the interesting fight is the one at the top.
    private var rivals: [LeaguePlayer] {
        appState.opponents.sorted {
            ($0.fighter?.attack ?? 0) > ($1.fighter?.attack ?? 0)
        }
    }

    private func start(against opponentId: String) async {
        guard let me = appState.playerId else { return }
        await viewModel.start(me: me, opponent: opponentId, api: appState.api)
    }
}
