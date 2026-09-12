import SwiftUI

@main
struct MealeeApp: App {
    @State private var appState = AppState(api: APIConfig.make())
    @State private var auth = Auth0Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(auth)
                .preferredColorScheme(.light)
                .tint(Palette.leaf)
                .task { auth.restoreSession() }
        }
    }
}

enum Tab: Int, CaseIterable {
    case fighter, fight, league
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(Auth0Session.self) private var auth
    @State private var tab = Tab.fighter

    var body: some View {
        ZStack {
            if APIConfig.auth0Enabled && auth.user == nil {
                LoginView().transition(.liquid)
            } else if !appState.isJoined {
                JoinView().transition(.liquid)
            } else {
                TabView(selection: $tab) {
                    NavigationStack { HomeView() }
                        .tabItem { Label("Fighter", systemImage: "figure.boxing") }.tag(Tab.fighter)
                    NavigationStack { FightView() }
                        .tabItem { Label("Fight", systemImage: "bolt.fill") }.tag(Tab.fight)
                    NavigationStack { LeagueView() }
                        .tabItem { Label("League", systemImage: "trophy.fill") }.tag(Tab.league)
                }
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .simultaneousGesture(tabSwipe)
                .transition(.liquid)
            }
        }
        .animation(Motion.settle, value: appState.isJoined)
        .animation(Motion.settle, value: auth.user == nil)
    }

    // Swiping between tabs is not a stock iOS behaviour, so it has to earn the gesture:
    // it must be clearly horizontal, travel a real distance, and start away from the
    // left edge, which belongs to the system back swipe.
    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { drag in
                guard drag.startLocation.x > 32,
                      abs(drag.translation.width) > 72,
                      abs(drag.translation.width) > abs(drag.translation.height) * 1.8 else { return }
                let step = drag.translation.width < 0 ? 1 : -1
                guard let next = Tab(rawValue: tab.rawValue + step) else { return }
                Haptics.tap()
                withAnimation(Motion.settle) { tab = next }
            }
    }
}
