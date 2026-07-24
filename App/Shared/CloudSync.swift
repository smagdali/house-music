import Foundation
import CloudKit
import HouseMusicKit

/// Household config sync via CloudKit. The whole HouseConfig lives as one
/// record (JSON blob + modification stamp) in a "Household" zone of the
/// owner's private database, shared zone-wide with the family via CKShare.
/// Two writers, rare writes: last-writer-wins on the whole config is fine.
/// The watch gets its config over WatchConnectivity from the phone instead.
actor CloudSync {
    static let shared = CloudSync()

    let container = CKContainer(identifier: "iCloud.org.whitelabel.housemusic")
    static let zoneName = "Household"
    static let recordName = "houseConfig"
    static let recordType = "HouseConfig"

    enum Location {
        case privateDB(CKRecordZone.ID)
        case sharedDB(CKRecordZone.ID)

        var zoneID: CKRecordZone.ID {
            switch self {
            case .privateDB(let id), .sharedDB(let id): return id
            }
        }
    }

    private var location: Location?

    func database(for location: Location) -> CKDatabase {
        switch location {
        case .privateDB: return container.privateCloudDatabase
        case .sharedDB: return container.sharedCloudDatabase
        }
    }

    /// Find the Household zone: ours in the private DB, or an accepted share.
    func resolveLocation() async -> Location? {
        if let location { return location }
        if let zones = try? await container.sharedCloudDatabase.allRecordZones(),
           let zone = zones.first(where: { $0.zoneID.zoneName == Self.zoneName }) {
            location = .sharedDB(zone.zoneID)
            return location
        }
        if let zones = try? await container.privateCloudDatabase.allRecordZones(),
           let zone = zones.first(where: { $0.zoneID.zoneName == Self.zoneName }) {
            location = .privateDB(zone.zoneID)
            return location
        }
        return nil
    }

    /// Create our own Household zone (first launch of the owning household member).
    func createZoneIfNeeded() async throws -> Location {
        if let existing = await resolveLocation() { return existing }
        let zone = CKRecordZone(zoneName: Self.zoneName)
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
        let loc = Location.privateDB(zone.zoneID)
        location = loc
        return loc
    }

    struct Remote {
        let config: HouseConfig
        let modified: Date
    }

    func pull() async -> Remote? {
        guard let location = await resolveLocation() else { return nil }
        let recordID = CKRecord.ID(recordName: Self.recordName, zoneID: location.zoneID)
        guard let record = try? await database(for: location).record(for: recordID),
              let data = record["json"] as? Data,
              let config = try? JSONDecoder().decode(HouseConfig.self, from: data) else { return nil }
        return Remote(config: config, modified: record["stamp"] as? Date ?? .distantPast)
    }

    func push(_ config: HouseConfig) async {
        guard let location = try? await createZoneIfNeeded() else { return }
        let recordID = CKRecord.ID(recordName: Self.recordName, zoneID: location.zoneID)
        let db = database(for: location)
        let record: CKRecord
        if let existing = try? await db.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        guard let data = try? JSONEncoder().encode(config) else { return }
        record["json"] = data
        record["stamp"] = Date()
        _ = try? await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    /// Zone-wide share for the household; returns an invite URL to send to Kay.
    func makeShareURL() async throws -> URL {
        let location = try await createZoneIfNeeded()
        guard case .privateDB(let zoneID) = location else {
            throw HouseMusicError.notConfigured("Only the household owner can invite")
        }
        let db = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await db.record(for: shareID) as? CKShare, let url = existing.url {
            return url
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "House Music" as CKRecordValue
        share.publicPermission = .none
        let result = try await db.modifyRecords(saving: [share], deleting: [], savePolicy: .ifServerRecordUnchanged)
        for (_, saveResult) in result.saveResults {
            if case .success(let record) = saveResult, let saved = record as? CKShare, let url = saved.url {
                return url
            }
        }
        throw HouseMusicError.notConfigured("Share URL")
    }

    func accept(_ metadata: CKShare.Metadata) async {
        _ = try? await container.accept(metadata)
        location = nil // re-resolve; the shared zone now exists
    }
}

extension AppModel {
    /// Reconcile with CloudKit: newer remote wins; otherwise push local.
    func cloudReconcile() async {
        let localStamp = UserDefaults.standard.object(forKey: "cloudStamp") as? Date ?? .distantPast
        if let remote = await CloudSync.shared.pull() {
            if remote.modified > localStamp, remote.config != config {
                adoptConfig(remote.config)
                UserDefaults.standard.set(remote.modified, forKey: "cloudStamp")
                return
            }
        }
        await cloudPush()
    }

    func cloudPush() async {
        await CloudSync.shared.push(config)
        UserDefaults.standard.set(Date(), forKey: "cloudStamp")
    }
}
