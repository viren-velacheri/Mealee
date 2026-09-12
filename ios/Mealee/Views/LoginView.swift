import SwiftUI

struct LoginView: View {
    @Environment(Auth0Session.self) private var auth

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 22) {
                Spacer()
                FighterSpriteView(stats: .empty, emoji: "🍽️")
                Text("Mealee").font(TypeScale.display).foregroundStyle(Palette.ink)
                Text("Your meals become your fighter.").font(TypeScale.body).foregroundStyle(Palette.muted)
                Spacer()
                VStack(spacing: 12) {
                    if auth.isLoading {
                        ProgressView().tint(Palette.leaf)
                    } else {
                        Button { Haptics.tap(); auth.login(screenHint: "signup") } label: { Text("Sign up").primaryPill() }
                        Button { Haptics.tap(); auth.login() } label: { Text("Log in").primaryPill(filled: false) }
                    }
                    if let message = auth.errorMessage {
                        Text(message).font(TypeScale.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(Pressable())
                .glassCard()
            }
            .padding(Layout.gutter)
        }
    }
}
