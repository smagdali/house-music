import Foundation
import Network

/// Finds MusicCast devices. Primary path: SSDP M-Search for MediaRenderer,
/// then confirm via YXC getDeviceInfo/getNameText. Fallback: probe previously
/// known IPs directly (IPs are DHCP-reserved in this house, but we re-key by
/// device_id anyway).
public struct DeviceDiscovery: Sendable {
    let client: YXCClient

    public init(client: YXCClient = YXCClient()) {
        self.client = client
    }

    /// Probe a specific host for a MusicCast device; returns nil quietly if absent.
    public func probe(host: String) async -> Device? {
        guard let info = try? await client.deviceInfo(host: host),
              let names = try? await client.nameText(host: host) else { return nil }
        let room = names.zoneList.first { $0.id == "main" }?.text ?? info.modelName
        return Device(id: info.deviceID, modelName: info.modelName, roomName: room, ipAddress: host)
    }

    /// SSDP M-Search sweep. Returns confirmed MusicCast devices, deduped by device_id.
    public func discover(timeout: TimeInterval = 3) async -> [Device] {
        let hosts = await ssdpHosts(timeout: timeout)
        var found: [DeviceID: Device] = [:]
        await withTaskGroup(of: Device?.self) { group in
            for host in hosts {
                group.addTask { await probe(host: host) }
            }
            for await device in group {
                if let device { found[device.id] = device }
            }
        }
        return found.values.sorted { $0.roomName < $1.roomName }
    }

    /// Send an SSDP M-Search and collect responder IPs.
    func ssdpHosts(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            var hosts = Set<String>()
            let lock = NSLock()
            let message =
                "M-SEARCH * HTTP/1.1\r\n" +
                "HOST: 239.255.255.250:1900\r\n" +
                "MAN: \"ssdp:discover\"\r\n" +
                "MX: 2\r\n" +
                "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"

            guard let multicast = try? NWMulticastGroup(for: [.hostPort(host: "239.255.255.250", port: 1900)]) else {
                continuation.resume(returning: [])
                return
            }
            let group = NWConnectionGroup(with: multicast, using: .udp)
            group.setReceiveHandler(maximumMessageSize: 4096) { context, _, _ in
                if case let .hostPort(host, _) = context.remoteEndpoint,
                   case let .ipv4(v4) = host {
                    lock.lock(); hosts.insert("\(v4)"); lock.unlock()
                }
            }
            group.stateUpdateHandler = { state in
                if case .ready = state {
                    group.send(content: message.data(using: .utf8)) { _ in }
                }
            }
            group.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                group.cancel()
                lock.lock(); let result = Array(hosts); lock.unlock()
                continuation.resume(returning: result)
            }
        }
    }

    /// Re-resolve a configured device list: confirm each device still answers at
    /// its recorded IP; if any moved, run a discovery sweep and re-match by id.
    public func refresh(_ devices: [Device]) async -> [Device] {
        var resolved: [Device] = []
        var missing: [Device] = []
        for device in devices {
            if let probed = await probe(host: device.ipAddress), probed.id == device.id {
                resolved.append(probed)
            } else {
                missing.append(device)
            }
        }
        if !missing.isEmpty {
            let swept = await discover()
            for device in missing {
                if let found = swept.first(where: { $0.id == device.id }) {
                    resolved.append(found)
                }
            }
        }
        return resolved
    }
}
