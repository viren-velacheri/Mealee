import SwiftUI

struct JoinView: View {
    @Environment(AppState.self) private var appState
    @Environment(Auth0Session.self) private var auth
    @State private var form = JoinForm()
    @State private var emoji = "🍗"
    @State private var busyLabel: String?
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
                    Button { Task { await enterTapped() } } label: { Text("Enter the arena").primaryPill() }
                    if let blocker { Notice(kind: .problem, text: blocker) }
                    if let message = appState.errorMessage { Notice(kind: .problem, text: message) }
                    if appState.api.isMock {
                        Notice(kind: .guidance, text: "Offline mode: fighters and rivals come from fixtures.")
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
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Who's fighting?").font(TypeScale.display).foregroundStyle(Palette.ink)
            Text("Name yourself and pick a face. Everyone fights in the same arena.")
                .font(TypeScale.caption).foregroundStyle(Palette.sage).multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    private var fighterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldLabel(text: "Your name", required: true)
            TextField("Display name", text: $form.name).font(TypeScale.title)
                .textInputAutocapitalization(.words).foregroundStyle(Palette.ink).submitLabel(.go)
                .onSubmit { Task { await enterTapped() } }
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

    private func clearBlocker() {
        blocker = nil
        appState.errorMessage = nil
    }

    // The button stays tappable. A disabled pill tells you nothing; a tap that names the
    // one missing thing tells you exactly what to do next.
    private func enterTapped() async {
        if let missing = form.missingToEnter {
            blocker = missing
            Haptics.thud()
            return
        }
        busyLabel = "Entering the arena…"
        await appState.join(code: "", name: form.trimmedName, emoji: emoji, auth0Sub: auth.subject)
        busyLabel = nil
    }
}
