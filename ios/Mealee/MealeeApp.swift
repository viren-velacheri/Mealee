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

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(Auth0Session.self) private var auth

    var body: some View {
        ZStack {
            if APIConfig.auth0Enabled && auth.user == nil {
                LoginView().transition(.liquid)
            } else if !appState.isJoined {
                JoinView().transition(.liquid)
            } else {
                TabView {
                    NavigationStack { HomeView() }
                        .tabItem { Label("Fighter", systemImage: "figure.boxing") }
                    NavigationStack { FightView() }
                        .tabItem { Label("Fight", systemImage: "bolt.fill") }
                    NavigationStack { LeagueView() }
                        .tabItem { Label("League", systemImage: "trophy.fill") }
                }
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .transition(.liquid)
            }
        }
        .animation(Motion.settle, value: appState.isJoined)
        .animation(Motion.settle, value: auth.user == nil)
    }
}
