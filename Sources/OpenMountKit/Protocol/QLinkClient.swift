import Foundation

public enum Feature: UInt8, Sendable {
    case root = 0x01, firmwareUpdate = 0x02, deviceInfo = 0x03, storage = 0x04, hub = 0x05, pollingRate = 0x06
    case keyboard = 0x07, mouse = 0x08, battery = 0x09, pairing = 0x0A
    case lightings = 0x10, bindings = 0x11, macros = 0x12
}

public enum QLinkError: Error, CustomStringConvertible {
    case timeout(feature: UInt8, command: UInt8)
    case deviceStatus(UInt8, feature: UInt8, command: UInt8)
    case blocked(feature: UInt8, command: UInt8)
    case noSession

    public var description: String {
        switch self {
        case .timeout(let f, let c): return String(format: "No reply from keyboard (feature 0x%02x, command 0x%02x)", f, c)
        case .deviceStatus(let s, let f, let c): return String(format: "Keyboard rejected request (status %d, feature 0x%02x, command 0x%02x)", s, f, c)
        case .blocked(let f, let c): return String(format: "Command 0x%02x/0x%02x is blocked by OpenMount for safety", f, c)
        case .noSession: return "No session open with the keyboard"
        }
    }
}

/// Request/response client. All calls are synchronous and serialized; use from a background queue.
public final class QLinkClient: @unchecked Sendable {
    public let transport: PacketTransport
    public private(set) var session: UInt8 = 0
    private var nextRID: UInt8 = 1
    private let lock = NSLock()
    public var timeout: TimeInterval = 1.5
    public var log: ((String) -> Void)?
    public var onNotification: ((QLinkMessage) -> Void)?

    /// Commands that can brick the keyboard or erase its identity. Never sent.
    static let blocked: Set<[UInt8]> = [
        [Feature.firmwareUpdate.rawValue, 0], // any DFU command (checked by feature below)
        [Feature.deviceInfo.rawValue, 0x03],  // set serial number
        [Feature.deviceInfo.rawValue, 0x04],  // reset serial number
    ]

    public init(transport: PacketTransport) { self.transport = transport }

    @discardableResult
    public func request(_ feature: UInt8, _ command: UInt8, _ payload: [UInt8] = []) throws -> [UInt8] {
        if feature == Feature.firmwareUpdate.rawValue || Self.blocked.contains([feature, command]) {
            throw QLinkError.blocked(feature: feature, command: command)
        }
        lock.lock(); defer { lock.unlock() }
        let rid = nextRID
        nextRID = nextRID == 255 ? 1 : nextRID + 1
        let msg = QLinkMessage(requestID: rid, feature: feature, command: command, payload: payload)
        transport.drain()
        for f in QLinkFrame.encode(message: msg.bytes, session: session) {
            log?("OUT " + f.prefix(Int(f[0]) + 1).map { String(format: "%02x", $0) }.joined(separator: " "))
            try transport.send(f)
        }
        let deadline = Date().addingTimeInterval(timeout)
        var assembled: [UInt8] = []
        while true {
            let left = deadline.timeIntervalSinceNow
            guard left > 0, let r = try transport.receive(timeout: left) else {
                throw QLinkError.timeout(feature: feature, command: command)
            }
            guard let fr = try? QLinkFrame.decode(r) else { log?("IN  (undecodable frame)"); continue }
            log?("IN  " + r.prefix(Int(r[0]) + 1).map { String(format: "%02x", $0) }.joined(separator: " "))
            if fr.sequence == 0 { assembled = fr.bytes } else { assembled += fr.bytes }
            if fr.more { continue }
            guard let m = QLinkMessage(bytes: assembled) else { continue }
            assembled = []
            if m.isNotification { onNotification?(m); continue }
            guard m.requestID == rid else { continue }
            guard m.status == 0 else { throw QLinkError.deviceStatus(m.status, feature: feature, command: command) }
            return m.payload
        }
    }

    // MARK: Root feature

    public struct SessionInfo: Sendable { public var id: UInt8; public var active: Bool; public var extra: UInt8 }

    public func openSession(clientType: UInt8 = 0) throws -> SessionInfo {
        session = 0
        var w = ByteWriter(); w.u32(0); w.u8(clientType)
        var r = ByteReader(try request(Feature.root.rawValue, 0x01, w.bytes))
        _ = try r.u32()
        let info = SessionInfo(id: try r.u8(), active: try r.bool(), extra: (try? r.u8()) ?? 0)
        session = info.id
        return info
    }

    public func closeSession() throws {
        guard session != 0 else { return }
        var w = ByteWriter(); w.u8(session)
        _ = try? request(Feature.root.rawValue, 0x02, w.bytes)
        session = 0
    }

    public func keepAlive() throws { try request(Feature.root.rawValue, 0x03) }

    public func qlinkVersion() throws -> UInt32 {
        var r = ByteReader(try request(Feature.root.rawValue, 0x05)); return try r.u32()
    }

    public func supportedFeatures() throws -> [UInt8] {
        try request(Feature.root.rawValue, 0x04, [0])
    }

    public struct DeviceInfo: Sendable, CustomStringConvertible {
        public var productID: UInt16
        public var deviceType: UInt8
        public var flag: UInt8
        public var firmware: UInt32
        public var firmwareString: String {
            "\(firmware >> 24 & 0xFF).\(firmware >> 16 & 0xFF).\(firmware & 0xFFFF)"
        }
        public var description: String {
            String(format: "product 0x%04x, type %d, firmware %@ (0x%08x)", productID, deviceType, firmwareString, firmware)
        }
    }

    public func deviceInfo() throws -> DeviceInfo {
        var r = ByteReader(try request(Feature.deviceInfo.rawValue, 0x01))
        return DeviceInfo(productID: try r.u16(), deviceType: try r.u8(), flag: try r.u8(), firmware: try r.u32())
    }
}
