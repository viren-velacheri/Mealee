import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var showCapture = false
    @State private var showFoodex = false
    @State private var showReasons = false

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Button { Haptics.tap(); showCapture = true } label: {
                        Label("Log a meal", systemImage: "camera.fill").primaryPill()
                    }
                    .buttonStyle(Pressable())
                    FighterHeroCard(stats: appState.fighter, name: appState.playerName, emoji: appState.playerEmoji,
                                    wins: appState.weekWins, offline: appState.api.isMock)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Today").font(TypeScale.heading).foregroundStyle(Palette.ink)
                            Spacer()
                            Button {
                                Haptics.tap()
                                withAnimation(Motion.bounce) { showReasons.toggle() }
                            } label: {
                                Label(showReasons ? "Hide why" : "Why", systemImage: "sparkles")
                                    .font(TypeScale.label).foregroundStyle(Palette.muted)
                                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                                    .contentShape(Rectangle())
                            }
                        }
                        StatMeters(stats: appState.fighter)
                        if showReasons {
                            ReasonList(reasons: appState.fighter.reasons).transition(.liquid)
                        }
                    }
                    .glassCard()
                    IntakeChips()
                    MealTimelineView(entries: appState.timeline)
                    if let message = appState.errorMessage {
                        Text(message).font(TypeScale.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }
                }
                .padding(Layout.gutter)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); showFoodex = true } label: {
                    Image(systemName: "book.closed.fill").foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Foodex")
            }
        }
        .fullScreenCover(isPresented: $showCapture) { CaptureView() }
        .sheet(isPresented: $showFoodex) { FoodexView().presentationBackground(.ultraThinMaterial) }
        .refreshable { await appState.refresh() }
        .task { await appState.refresh() }
    }
}
