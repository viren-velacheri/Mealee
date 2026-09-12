import Auth0
import Foundation
import Observation

// Wraps the Auth0.swift SDK. Universal Login via webAuth, credentials in the Keychain via
// CredentialsManager, profile read from the ID token. Never implements OAuth by hand.
@Observable
@MainActor
final class Auth0Session {
    var user: UserInfo?
    var isLoading = true
    var errorMessage: String?

    private let credentialsManager = CredentialsManager(authentication: Auth0.authentication())

    private static let useUniversalLinks: Bool = {
        guard let path = Bundle.main.path(forResource: "Auth0", ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path) else { return false }
        return values["CallbackMode"] as? String == "universal-links"
    }()

    private func webAuth() -> WebAuth {
        let webAuth = Auth0.webAuth()
        return Self.useUniversalLinks ? webAuth.useHTTPS() : webAuth
    }

    var subject: String? { user?.sub }

    func restoreSession() {
        guard credentialsManager.canRenew() else {
            isLoading = false
            return
        }
        credentialsManager.credentials { [weak self] result in
            Task { @MainActor in
                if case .success = result { self?.user = self?.credentialsManager.user }
                self?.isLoading = false
            }
        }
    }

    func login(screenHint: String? = nil) {
        errorMessage = nil
        var auth = webAuth().scope("openid profile email offline_access")
        if let screenHint { auth = auth.parameters(["screen_hint": screenHint]) }
        auth.start { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let credentials):
                    _ = self?.credentialsManager.store(credentials: credentials)
                    self?.user = self?.credentialsManager.user
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func logout() {
        errorMessage = nil
        webAuth().clearSession { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    _ = self?.credentialsManager.clear()
                    self?.user = nil
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
