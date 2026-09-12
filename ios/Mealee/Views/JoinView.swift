import SwiftUI

struct JoinView: View {
    @Environment(AppState.self) private var appState
    @Environment(Auth0Session.self) private var auth
    @State private var code = ""
    @State private var name = ""
    @State private var emoji = "🍗"
    @State private var newLeagueName = ""
    @State private var isBusy = false

    private let emojiChoices = ["🍗", "🥦", "🍩", "🍕", "🍣", "🥑", "🌶️", "🧀", "🍜", "🍎", "🥯", "🍪"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Your fighter") {
                    TextField("Display name", text: $name).textInputAutocapitalization(.words)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(emojiChoices, id: \.self) { choice in
                                Text(choice).font(.system(size: 34))
                                    .padding(6)
                                    .background(choice == emoji ? Color.orange.opacity(0.35) : .clear, in: Circle())
                                    .onTapGesture { emoji = choice }
                            }
                        }
                    }
                }
                Section("Join a league") {
                    TextField("4-letter code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title2, design: .monospaced))
                    Button("Join") { Task { await join(code) } }
                        .disabled(code.count != 4 || name.isEmpty || isBusy)
                }
                Section("Or start one") {
                    TextField("League name", text: $newLeagueName)
                    Button("Create and join") { Task { await createAndJoin() } }
                        .disabled(newLeagueName.isEmpty || name.isEmpty || isBusy)
                }
                if let message = appState.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
                if appState.api.isMock {
                    Section { Text("Offline mode: running on bundled fixtures. Any code joins the DEMO league.").font(.footnote) }
                }
            }
            .navigationTitle("Mealee")
            .toolbar {
                if APIConfig.auth0Enabled {
                    Button("Log out") { auth.logout() }
                }
            }
            .onAppear { if name.isEmpty { name = auth.user?.nickname ?? auth.user?.name ?? "" } }
        }
    }

    private func join(_ leagueCode: String) async {
        isBusy = true
        await appState.join(code: leagueCode, name: name, emoji: emoji, auth0Sub: auth.subject)
        isBusy = false
    }

    private func createAndJoin() async {
        isBusy = true
        if let created = await appState.createLeague(named: newLeagueName) {
            await appState.join(code: created, name: name, emoji: emoji, auth0Sub: auth.subject)
        }
        isBusy = false
    }
}
