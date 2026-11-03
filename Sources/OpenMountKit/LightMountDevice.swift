import Foundation

/// High-level, synchronous API for one connected Light Mount. Not thread-safe: call from one queue.
public final class LightMountDevice: @unchecked Sendable {
    public let client: QLinkClient
    public let match: DeviceMatch
    public private(set) var info: QLinkClient.DeviceInfo?
    public private(set) var serial: String = ""

    public static let maxMacros = 10
    public static let maxMacroEvents = 56

    public init(transport: HIDTransport) throws {
        client = QLinkClient(transport: transport)
        match = transport.match
        _ = try client.openSession(clientType: 1)
        info = try? client.deviceInfo()
        if let s = try? client.request(Feature.deviceInfo.rawValue, 0x02), let n = s.first {
            serial = String(decoding: s.dropFirst().prefix(Int(n)), as: UTF8.self)
        }
    }

    /// Wraps an already-open client session (used by the CLI).
    public init(client: QLinkClient) {
        self.client = client
        match = .lightMount
        info = try? client.deviceInfo()
    }

    public static func connect() throws -> LightMountDevice { try LightMountDevice(transport: try HIDTransport.open()) }

    public func close() { try? client.closeSession() }

    public func keepAlive() throws { try client.keepAlive() }

    // MARK: Lighting

    public func lightingMode() throws -> LightingMode {
        LightingMode(rawValue: try client.request(0x10, 0x01).first ?? 1) ?? .global
    }

    public func setLightingMode(_ m: LightingMode) throws { try client.request(0x10, 0x02, [m.rawValue]) }

    /// Applies an on-board effect. Stored on the keyboard, so it works without the app.
    public func apply(_ g: GlobalLighting) throws {
        if try lightingMode() != .global { try setLightingMode(.global) }
        try client.request(0x10, 0x06, [0] + g.encode())
    }

    /// Paints LEDs directly (Realtime mode). Not saved to flash; the app re-applies it on connect.
    public func paint(_ colors: [RGB]) throws {
        if try lightingMode() != .realtime { try setLightingMode(.realtime) }
        var cmds: [RealtimeCommand] = []
        var start = 0
        // Up to 16 LEDs per range command, 4 commands per request keeps each request small.
        while start < colors.count {
            let end = min(colors.count, start + 16)
            cmds.append(.range(first: UInt16(start), colors: Array(colors[start..<end])))
            start = end
            if cmds.count == 4 { try client.request(0x10, 0x0D, RealtimeCommand.encode(cmds)); cmds = [] }
        }
        cmds.append(.commit)
        try client.request(0x10, 0x0D, RealtimeCommand.encode(cmds))
    }

    // MARK: Bindings

    public func binding(_ key: KeyID, layer: BindingLayer) throws -> KeyBinding {
        var w = ByteWriter(); w.u16(UInt16(key.bindingIndex) + layer.keyOffset)
        return KeyBinding.decode(try client.request(0x11, 0x06, w.bytes))
    }

    public func setBinding(_ b: KeyBinding, for key: KeyID, layer: BindingLayer) throws {
        var w = ByteWriter(); w.u16(UInt16(key.bindingIndex) + layer.keyOffset); w.raw(b.encode())
        try client.request(0x11, 0x02, w.bytes)
    }

    public func resetBinding(_ key: KeyID, layer: BindingLayer) throws {
        var w = ByteWriter(); w.u16(UInt16(key.bindingIndex) + layer.keyOffset)
        try client.request(0x11, 0x03, w.bytes)
    }

    /// Keys whose binding differs from the factory default, as (raw key id, binding).
    public func customBindings() throws -> [(UInt16, KeyBinding)] {
        var r = ByteReader(try client.request(0x11, 0x01, [0, 0]))
        let n = try r.u16()
        var out: [(UInt16, KeyBinding)] = []
        for _ in 0..<n {
            let key = try r.u16()
            let a = try r.u8()
            let len: Int = [0: 0, 1: 2, 2: 1, 3: 3, 9: 1, 10: 2][Int(a)] ?? 0
            out.append((key, KeyBinding.decode([a] + (try r.raw(len)))))
        }
        return out
    }

    public func allBindings(layer: BindingLayer) throws -> [KeyID: KeyBinding] {
        var d: [KeyID: KeyBinding] = [:]
        for k in KeyID.allCases where k != .fn { d[k] = try binding(k, layer: layer) }
        return d
    }

    // MARK: Macros

    public func macroIDs() throws -> [UInt16] {
        var r = ByteReader(try client.request(0x12, 0x01, [0, 0]))
        return try (0..<r.u16()).map { _ in try r.u16() }
    }

    public func macro(_ id: UInt16) throws -> Macro {
        var idw = ByteWriter(); idw.u16(id)
        var name = ""
        if let n = try? client.request(0x12, 0x07, idw.bytes), let len = n.first {
            name = String(decoding: n.dropFirst().prefix(Int(len)), as: UTF8.self)
        }
        var cfg = ByteReader(try client.request(0x12, 0x03, idw.bytes))
        let playback = MacroPlayback(rawValue: try cfg.u8()) ?? .once
        // GetMacroEvents pages through the raw event byte stream (offset in bytes, replies may cut an event).
        var stream: [UInt8] = []
        var total = -1
        var events: [MacroEvent] = []
        for _ in 0..<32 {
            var w = idw; w.u16(UInt16(stream.count))
            let page = try client.request(0x12, 0x05, w.bytes)
            guard page.count > 2 else { break }
            total = Int(page[0]) | Int(page[1]) << 8
            stream += page[2...]
            var r = ByteReader(stream)
            events = []
            while events.count < total, let e = try? MacroEvent.read(&r) { events.append(e) }
            if events.count >= total || total == 0 { break }
        }
        return Macro(id: id, name: name.isEmpty ? "Macro \(id)" : name, playback: playback, events: events)
    }

    public func macros() throws -> [Macro] { try macroIDs().map { try macro($0) } }

    /// Replaces the whole macro set on the keyboard.
    public func saveMacros(_ list: [Macro]) throws {
        precondition(list.count <= Self.maxMacros)
        var w = ByteWriter(); w.u16(UInt16(list.count)); w.u16(0); list.forEach { w.u16($0.id) }
        try client.request(0x12, 0x02, w.bytes)
        for m in list {
            var c = ByteWriter(); c.u16(m.id); c.u8(m.playback.rawValue); c.u8(MacroDelayMode.recorded.rawValue); c.u16(0)
            try client.request(0x12, 0x04, c.bytes)
            // Firmware 0x35 replaces the whole event list on every SetMacroEvents, so send it in one
            // (multi-frame) request rather than in chunks.
            let events = Array(m.events.prefix(Self.maxMacroEvents))
            var e = ByteWriter(); e.u16(m.id); e.u16(UInt16(events.count)); e.u16(0)
            events.forEach { $0.write(&e) }
            try client.request(0x12, 0x06, e.bytes)
            let name = Array(m.name.utf8.prefix(32))
            var n = ByteWriter(); n.u16(m.id); n.u8(UInt8(name.count)); n.raw(name)
            try client.request(0x12, 0x08, n.bytes)
        }
    }

    // MARK: Other

    public func pollingRate() throws -> UInt16 { var r = ByteReader(try client.request(0x06, 0x01)); return try r.u16() }
}
