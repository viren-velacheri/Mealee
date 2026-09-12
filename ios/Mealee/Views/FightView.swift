import SwiftUI

struct FightView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = FightViewModel()
    @State private var selectedId: String?
    @State private var lift: CGFloat = 0

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
    }

    private var picker: some View {
        VStack(spacing: 18) {
            Text("Choose a rival").font(TypeScale.display).foregroundStyle(Palette.ink).padding(.top, 8)
            Text("Tap a card, then swipe it up into the ring").font(TypeScale.caption).foregroundStyle(Palette.slate)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(appState.opponents) { opponent in
                        OpponentCard(player: opponent, selected: opponent.playerId == selectedId)
                            .offset(y: opponent.playerId == selectedId ? lift : 0)
                            .onTapGesture {
                                Haptics.tap()
                                withAnimation(Motion.bounce) { selectedId = opponent.playerId }
                            }
                            .gesture(swipeUp(for: opponent))
                    }
                }
                .padding(.horizontal, Layout.gutter).padding(.vertical, 30)
            }
            .frame(height: 260)
            if appState.opponents.isEmpty {
                Text("Nobody else in the league yet").font(TypeScale.body).foregroundStyle(Palette.slate)
            }
            Spacer()
            if let message = viewModel.errorMessage {
                Text(message).font(TypeScale.caption).foregroundStyle(Palette.slate)
            }
            Button {
                guard let opponent = selectedId ?? appState.opponents.randomElement()?.playerId else { return }
                Task { await start(against: opponent) }
            } label: {
                Label(selectedId == nil ? "Quick match" : "Fight", systemImage: "bolt.fill").primaryPill()
            }
            .buttonStyle(Pressable())
            .disabled(appState.opponents.isEmpty || viewModel.isStarting)
            .padding(.horizontal, Layout.gutter).padding(.bottom, 12)
        }
        .overlay { if viewModel.isStarting { ProgressView().tint(Palette.leaf).scaleEffect(1.4) } }
        .refreshable { await appState.refresh() }
    }

    private func swipeUp(for opponent: LeaguePlayer) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard opponent.playerId == selectedId, value.translation.height < 0 else { return }
                lift = 80 * tanh(value.translation.height / 80)
            }
            .onEnded { value in
                guard opponent.playerId == selectedId else { return }
                if value.translation.height < -90 {
                    Haptics.success()
                    withAnimation(Motion.snappy) { lift = -160 }
                    Task { await start(against: opponent.playerId); lift = 0 }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { lift = 0 }
                }
            }
    }

    private func start(against opponentId: String) async {
        guard let me = appState.playerId else { return }
        await viewModel.start(me: me, opponent: opponentId, api: appState.api)
    }
}
