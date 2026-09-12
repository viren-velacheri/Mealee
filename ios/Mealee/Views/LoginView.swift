import SwiftUI

struct LoginView: View {
    @Environment(Auth0Session.self) private var auth

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("🍽️").font(.system(size: 96))
            Text("Mealee").font(.system(size: 44, weight: .black, design: .rounded))
            Text("Your meals become your fighter.").foregroundStyle(.secondary)
            Spacer()
            if auth.isLoading {
                ProgressView("Checking session")
            } else {
                Button { auth.login(screenHint: "signup") } label: {
                    Text("Sign Up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button { auth.login() } label: {
                    Text("Log In").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            if let message = auth.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Text("Sign in with Auth0. Set AUTH0_ENABLED = NO in Config.xcconfig to skip this.")
                .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(28)
    }
}
