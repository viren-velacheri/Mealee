import SwiftUI

struct JoinView: View {
    @Environment(AppState.self) private var appState
    @Environment(Auth0Session.self) private var auth
    @State private var code = ""
    @State private var name = ""
    @State private var emoji = "🍗"
    @State private var newLeagueName = ""
    @State private var isBusy = false
    @State private var startingOne = false

    private let emojiChoices = ["🍗", "🥦", "🍩", "🍕", "🍣", "🥑", "🌶️", "🧀", "🍜", "🍎", "🥯", "🍪"]

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    Text("Who's fighting?").font(TypeScale.display).foregroundStyle(Palette.ink).padding(.top, 30)
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Display name", text: $name).font(TypeScale.title).textInputAutocapitalization(.words)
                            .foregroundStyle(Palette.ink)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(emojiChoices, id: \.self) { choice in
                                    Text(choice).font(.system(size: 34)).padding(8)
                                        .background(choice == emoji ? Palette.leaf.opacity(0.5) : .clear, in: Circle())
                                        .scaleEffect(choice == emoji ? 1.15 : 1)
                                        .onTapGesture { Haptics.tap(); withAnimation(Motion.bounce) { emoji = choice } }
                                }
                            }
                        }
                    }
                    .glassCard()
                    VStack(spacing: 12) {
                        TextField("4-letter code", text: $code)
                            .font(.system(size: 40, weight: .bold, design: .monospaced)).multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled().foregroundStyle(Palette.ink)
                        Button { Task { await join(code) } } label: { Text("Join league").primaryPill() }
                            .disabled(code.count != 4 || name.isEmpty || isBusy)
                    }
                    .glassCard()
                    Button { Haptics.tap(); withAnimation(Motion.bounce) { startingOne.toggle() } } label: {
                        Text(startingOne ? "Never mind" : "Or start a new league").font(TypeScale.label).foregroundStyle(Palette.sage)
                    }
                    if startingOne {
                        VStack(spacing: 12) {
                            TextField("League name", text: $newLeagueName).font(TypeScale.title).foregroundStyle(Palette.ink)
                            Button { Task { await createAndJoin() } } label: { Text("Create and join").primaryPill(filled: false) }
                                .disabled(newLeagueName.isEmpty || name.isEmpty || isBusy)
                        }
                        .glassCard().transition(.liquid)
                    }
                    if let message = appState.errorMessage {
                        Text(message).font(TypeScale.caption).foregroundStyle(Palette.slate).multilineTextAlignment(.center)
                    }
                    if appState.api.isMock {
                        Text("Offline mode: any code joins the DEMO league.").font(TypeScale.caption).foregroundStyle(Palette.slate)
                    }
                    if APIConfig.auth0Enabled {
                        Button("Log out") { auth.logout() }.font(TypeScale.caption).foregroundStyle(Palette.slate)
                    }
                }
                .buttonStyle(Pressable())
                .padding(Layout.gutter)
            }
            .overlay { if isBusy { ProgressView().tint(Palette.leaf).scaleEffect(1.4) } }
        }
        .onAppear { if name.isEmpty { name = auth.user?.nickname ?? auth.user?.name ?? "" } }
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
