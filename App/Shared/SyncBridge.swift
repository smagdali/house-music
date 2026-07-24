import Foundation
import HouseMusicKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Pushes the household config from phone to watch (and accepts it on the
/// watch). Interim transport until CloudKit sync covers both devices; also a
/// useful immediate path since the watch has no discovery UI.
final class SyncBridge: NSObject {
    static let shared = SyncBridge()

    #if canImport(WatchConnectivity)
    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }
    #endif

    func activate() {
        #if canImport(WatchConnectivity)
        session?.delegate = self
        session?.activate()
        #endif
    }

    func pushConfig(_ config: HouseConfig) {
        #if os(iOS) && canImport(WatchConnectivity)
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(config) else { return }
        try? session.updateApplicationContext(["config": data])
        #endif
    }
}

#if canImport(WatchConnectivity)
extension SyncBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        Task { @MainActor in
            SyncBridge.shared.pushConfig(AppModel.shared.config)
        }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["config"] as? Data,
              let config = try? JSONDecoder().decode(HouseConfig.self, from: data) else { return }
        Task { @MainActor in
            AppModel.shared.adoptConfig(config)
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
