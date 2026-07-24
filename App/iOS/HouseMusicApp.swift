import SwiftUI
import HouseMusicKit

@main
struct HouseMusicApp: App {
    @State private var model = AppModel.shared
    @State private var spotifyVerifier: String?

    init() {
        SyncBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.needsOnboarding {
                    WizardView()
                } else {
                    MainView()
                }
            }
            .environment(model)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleSpotifyCallback(url)
            }
        }
    }

    private func handleSpotifyCallback(_ url: URL) {
        guard url.scheme == "housemusic",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = SpotifyAuth.pendingVerifier else { return }
        Task {
            try? await model.spotify.exchangeCode(code, verifier: verifier)
            SpotifyAuth.pendingVerifier = nil
        }
    }
}

/// Holds the PKCE verifier between launching the auth page and the callback.
enum SpotifyAuth {
    static var pendingVerifier: String?

    @MainActor
    static func begin() {
        let request = SpotifyClient.makeAuthRequest()
        pendingVerifier = request.codeVerifier
        UIApplication.shared.open(request.url)
    }
}
