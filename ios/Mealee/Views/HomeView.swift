import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var showCapture = false
    @State private var showFoodex = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FighterSpriteView(stats: appState.fighter, emoji: appState.playerEmoji)
                Text(appState.playerName).font(.title.bold())
                Text("HP \(appState.fighter.hpMax)  ·  \(appState.weekWins) W this week")
                    .font(.subheadline).foregroundStyle(.secondary)
                StatBarsView(stats: appState.fighter)
                    .padding(.horizontal)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.fighter.reasons, id: \.self) { reason in
                        Text("• \(reason)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Button { showCapture = true } label: {
                    Label("Log a meal", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)

                NavigationLink { FightView() } label: {
                    Label("Fight", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)

                HStack(spacing: 12) {
                    Button("💧 +250 ml") { Task { await appState.intake("water") } }
                    Button("☕ +1 coffee") { Task { await appState.intake("coffee") } }
                }
                .buttonStyle(.bordered)

                if let message = appState.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                if appState.api.isMock {
                    Text("Offline mode").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding()
        }
        .navigationTitle("Today's fighter")
        .toolbar {
            Button { showFoodex = true } label: { Image(systemName: "book.closed.fill") }
                .accessibilityLabel("Foodex")
        }
        .fullScreenCover(isPresented: $showCapture) { CaptureView() }
        .sheet(isPresented: $showFoodex) { FoodexView() }
        .refreshable { await appState.refresh() }
        .task { await appState.refresh() }
    }
}
