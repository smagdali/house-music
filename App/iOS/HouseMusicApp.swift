import SwiftUI
import CloudKit
import HouseMusicKit

@main
struct HouseMusicApp: App {
    @UIApplicationDelegateAdaptor(ShareAcceptDelegate.self) var delegate
    @State private var model = AppModel.shared

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
            .task {
                await model.cloudReconcile()
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

/// Accepts a CloudKit share invite (the household config from the other phone).
final class ShareAcceptDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            await CloudSync.shared.accept(metadata)
            await AppModel.shared.cloudReconcile()
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
