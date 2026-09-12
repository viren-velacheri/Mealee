import SwiftUI

struct JoinView: View {
    @Environment(AppState.self) private var appState
    @Environment(Auth0Session.self) private var auth
    @State private var form = JoinForm()
    @State private var emoji = "🍗"
    @State private var busyLabel: String?
    @State private var startingOne = false
    @State private var blocker: String?
    @State private var showingCustomEmoji = false

    private let emojiChoices = ["🍗", "🥦", "🍩", "🍕", "🍣", "🥑", "🌶️", "🧀", "🍜", "🍎", "🥯", "🍪"]

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    fighterCard
                    joinCard
                    startOwnButton
                    if startingOne { newLeagueCard.transition(.liquid) }
                    if let blocker { Notice(kind: .problem, text: blocker) }
                    if let message = appState.errorMessage { Notice(kind: .problem, text: message) }
                    if appState.api.isMock {
                        Notice(kind: .guidance, text: "Offline mode: any 4-letter code joins the DEMO league.")
                    }
                    if APIConfig.auth0Enabled {
                        Button("Log out") { auth.logout() }.font(TypeScale.caption).foregroundStyle(Palette.slate)
                    }
                }
                .buttonStyle(Pressable())
                .padding(Layout.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay { if let busyLabel { BusyOverlay(label: busyLabel) } }
        }
        .onAppear { if form.name.isEmpty { form.name = auth.user?.nickname ?? auth.user?.name ?? "" } }
        .onChange(of: form.name) { clearBlocker() }
        .onChange(of: form.code) { clearBlocker() }
        .onChange(of: form.leagueName) { clearBlocker() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Who's fighting?").font(TypeScale.display).foregroundStyle(Palette.ink)
            Text("Name yourself, pick a face, then join a league or start one.")
                .font(TypeScale.caption).foregroundStyle(Palette.sage).multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    private var fighterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldLabel(text: "Your name", required: true)
            TextField("Display name", text: $form.name).font(TypeScale.title)
                .textInputAutocapitalization(.words).foregroundStyle(Palette.ink).submitLabel(.done)
            FieldLabel(text: "Your face")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(emojiChoices, id: \.self) { choice in
                        Text(choice).font(.system(size: 34)).padding(8)
                            .background(choice == emoji ? Palette.leaf.opacity(0.5) : .clear, in: Circle())
                            .scaleEffect(choice == emoji ? 1.15 : 1)
                            .onTapGesture { Haptics.tap(); withAnimation(Motion.bounce) { emoji = choice } }
                    }
                    Button { showingCustomEmoji = true } label: {
                        VStack(spacing: 2) {
                            Text(emojiChoices.contains(emoji) ? "+" : emoji).font(.system(size: 30, weight: .medium))
                            Text("custom").font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Palette.ink).frame(width: 50, height: 50)
                        .background(emojiChoices.contains(emoji) ? .clear : Palette.leaf.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel("Choose a custom emoji")
                }
            }
            Notice(kind: .guidance, text: "\(emoji) is picked. Tap another to change it.")
        }
        .glassCard()
        .sheet(isPresented: $showingCustomEmoji) {
            CustomEmojiSheet(current: emoji) { choice in
                withAnimation(Motion.bounce) { emoji = choice }
            }
        }
    }

    private var joinCard: some View {
        VStack(spacing: 12) {
            FieldLabel(text: "League code", required: true)
            TextField("ABCD", text: $form.code)
                .font(.system(size: 40, weight: .bold, design: .monospaced)).multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .foregroundStyle(Palette.ink).submitLabel(.go)
                .onSubmit { Task { await joinTapped() } }
            Notice(kind: .guidance, text: "Ask whoever made the league for its 4-letter code.")
            Button { Task { await joinTapped() } } label: { Text("Join league").primaryPill() }
        }
        .glassCard()
    }

    private var startOwnButton: some View {
        Button { Haptics.tap(); clearBlocker(); withAnimation(Motion.bounce) { startingOne.toggle() } } label: {
            Text(startingOne ? "Never mind" : "Or start a new league")
                .font(TypeScale.label).foregroundStyle(Palette.sage)
        }
    }

    private var newLeagueCard: some View {
        VStack(spacing: 12) {
            FieldLabel(text: "League name", required: true)
            TextField("Hall 3 Lunch", text: $form.leagueName).font(TypeScale.title)
                .foregroundStyle(Palette.ink).submitLabel(.go)
                .onSubmit { Task { await createTapped() } }
            Notice(kind: .guidance, text: "You get a 4-letter code to share with everyone else.")
            Button { Task { await createTapped() } } label: { Text("Create and join").primaryPill(filled: false) }
        }
        .glassCard()
    }

    private func clearBlocker() {
        blocker = nil
        appState.errorMessage = nil
    }

    // Every button stays tappable. A disabled pill tells you nothing; a tap that names the
    // one missing thing tells you exactly what to do next.
    private func joinTapped() async {
        if let missing = form.missingForJoin {
            blocker = missing
            Haptics.thud()
            return
        }
        busyLabel = "Joining \(form.trimmedCode.uppercased())…"
        await appState.join(code: form.trimmedCode, name: form.trimmedName, emoji: emoji, auth0Sub: auth.subject)
        busyLabel = nil
    }

    private func createTapped() async {
        if let missing = form.missingForCreate {
            blocker = missing
            Haptics.thud()
            return
        }
        busyLabel = "Creating \(form.trimmedLeagueName)…"
        if let created = await appState.createLeague(named: form.trimmedLeagueName) {
            busyLabel = "Joining \(created)…"
            await appState.join(code: created, name: form.trimmedName, emoji: emoji, auth0Sub: auth.subject)
        }
        busyLabel = nil
    }
}
