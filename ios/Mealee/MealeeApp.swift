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
                .preferredColorScheme(.dark)
                .task { auth.restoreSession() }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(Auth0Session.self) private var auth

    var body: some View {
        if APIConfig.auth0Enabled && auth.user == nil {
            LoginView()
        } else if !appState.isJoined {
            JoinView()
        } else {
            TabView {
                NavigationStack { HomeView() }
                    .tabItem { Label("Fighter", systemImage: "figure.boxing") }
                NavigationStack { FightView() }
                    .tabItem { Label("Fight", systemImage: "bolt.fill") }
                NavigationStack { LeagueView() }
                    .tabItem { Label("League", systemImage: "trophy.fill") }
            }
            .tint(.orange)
        }
    }
}
