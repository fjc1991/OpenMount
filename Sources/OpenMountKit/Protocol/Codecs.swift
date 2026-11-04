import Foundation

// MARK: - Lighting

public enum LightingMode: UInt8, Codable, Sendable { case disabled = 0, global = 1, custom = 2, realtime = 3 }

public enum LightingDirection: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case up = 0, down, left, right, clockwise, counterclockwise, omnidirectional, horizontal, vertical, cross
    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .up: return "Up"; case .down: return "Down"; case .left: return "Left"; case .right: return "Right"
        case .clockwise: return "Clockwise"; case .counterclockwise: return "Counter-clockwise"
        case .omnidirectional: return "Outward"; case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"; case .cross: return "Cross"
        }
    }
}

public extension LightingEffect {
    var wireValue: UInt8 {
        switch self {
        case .staticColor: return 0; case .colorWave: return 1; case .tornado: return 2
        case .breathing: return 3; case .reactive: return 4; case .matrix: return 5
        }
    }
    /// Which controls make sense for each effect.
    var usesSpeed: Bool { self != .staticColor }
    var usesDirection: Bool { self == .colorWave || self == .tornado }
    var directions: [LightingDirection] {
        switch self {
        case .colorWave: return [.left, .right, .up, .down]
        case .tornado: return [.clockwise, .counterclockwise]
        default: return []
        }
    }
    var colorModes: [ColorMode] {
        switch self {
        case .colorWave, .tornado: return [.gradient, .single]
        case .breathing: return [.single, .dual]
        default: return [.single]
        }
    }
}

public enum ColorMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case single, dual, gradient
    public var id: String { rawValue }
    public var displayName: String { self == .single ? "Single colour" : self == .dual ? "Two colours" : "Rainbow gradient" }
}

public struct GlobalLighting: Codable, Equatable, Sendable {
    public var effect: LightingEffect = .staticColor
    public var direction: LightingDirection = .right
    public var brightness: UInt8 = 100
    public var speed: UInt8 = 50
    public var colorMode: ColorMode = .single
    public var primary: RGB = .beQuietOrange
    public var secondary: RGB = RGB(0, 0x60, 0xFF)
    public init() {}

    public static let rainbow: [RGB] = [RGB(255, 0, 0), RGB(255, 160, 0), RGB(255, 255, 0), RGB(0, 255, 0),
                                        RGB(0, 200, 255), RGB(0, 0, 255), RGB(180, 0, 255)]

    /// Layer-config payload for SetLayerConfig (without the layer id).
    public func encode() -> [UInt8] {
        var w = ByteWriter()
        w.u8(effect.wireValue)
        w.u8(effect.usesDirection ? direction.rawValue : 0)
        w.u8(min(brightness, 100))
        w.u8(min(speed, 100))
        let mode = effect.colorModes.contains(colorMode) ? colorMode : effect.colorModes[0]
        switch mode {
        case .single:
            w.u8(0); w.raw([primary.r, primary.g, primary.b])
        case .dual:
            w.u8(1); w.raw([primary.r, primary.g, primary.b, secondary.r, secondary.g, secondary.b])
        case .gradient:
            w.u8(2); w.u8(UInt8(Self.rainbow.count))
            for (i, c) in Self.rainbow.enumerated() {
                w.raw([c.r, c.g, c.b]); w.u8(UInt8(i * 100 / (Self.rainbow.count - 1)))
            }
        }
        return w.bytes
    }
}

public enum RealtimeCommand: Equatable, Sendable {
    case commit
    case range(first: UInt16, colors: [RGB])
    case fill(first: UInt16, count: UInt8, color: RGB)
    case single(index: UInt16, color: RGB)

    func write(_ w: inout ByteWriter) {
        switch self {
        case .commit: w.u8(0)
        case .range(let f, let cs):
            w.u8(1); w.u16(f); w.u8(UInt8(cs.count)); for c in cs { w.raw([c.r, c.g, c.b]) }
        case .fill(let f, let n, let c):
            w.u8(2); w.u16(f); w.u8(n); w.raw([c.r, c.g, c.b])
        case .single(let i, let c):
            w.u8(3); w.u16(i); w.raw([c.r, c.g, c.b])
        }
    }

    public static func encode(_ cmds: [RealtimeCommand]) -> [UInt8] {
        var w = ByteWriter(); w.u8(UInt8(cmds.count)); for c in cmds { c.write(&w) }; return w.bytes
    }
}

// MARK: - Bindings

public enum BindingLayer: String, CaseIterable, Codable, Sendable, Identifiable {
    case base, fn
    public var id: String { rawValue }
    public var keyOffset: UInt16 { self == .fn ? 132 : 0 }
    public var displayName: String { self == .fn ? "Fn layer" : "Main layer" }
}

public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let leftCtrl = Modifiers(rawValue: 1 << 0)
    public static let leftShift = Modifiers(rawValue: 1 << 1)
    public static let leftAlt = Modifiers(rawValue: 1 << 2)
    public static let leftGui = Modifiers(rawValue: 1 << 3)
    public static let rightCtrl = Modifiers(rawValue: 1 << 4)
    public static let rightShift = Modifiers(rawValue: 1 << 5)
    public static let rightAlt = Modifiers(rawValue: 1 << 6)
    public static let rightGui = Modifiers(rawValue: 1 << 7)

    /// macOS-style symbols (Gui = ⌘, Alt = ⌥).
    public var symbols: String {
        var s = ""
        if contains(.leftCtrl) || contains(.rightCtrl) { s += "⌃" }
        if contains(.leftAlt) || contains(.rightAlt) { s += "⌥" }
        if contains(.leftShift) || contains(.rightShift) { s += "⇧" }
        if contains(.leftGui) || contains(.rightGui) { s += "⌘" }
        return s
    }
}

public enum MediaAction: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case volumeUp = 1, volumeDown, mute, micMute, nextTrack, previousTrack, playPause, stop
    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .volumeUp: return "Volume up"; case .volumeDown: return "Volume down"; case .mute: return "Mute"
        case .micMute: return "Mic mute"; case .nextTrack: return "Next track"; case .previousTrack: return "Previous track"
        case .playPause: return "Play / Pause"; case .stop: return "Stop"
        }
    }
}

public enum MouseButton: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case left = 0, right, middle, forward, back
    public var id: UInt8 { rawValue }
    public var displayName: String { ["Left click", "Right click", "Middle click", "Forward", "Back"][Int(rawValue)] }
}

public enum LightingAction: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case nextEffect = 2, previousEffect = 3, brighter = 4, dimmer = 5
    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .nextEffect: return "Next effect"; case .previousEffect: return "Previous effect"
        case .brighter: return "Brightness up"; case .dimmer: return "Brightness down"
        }
    }
}

public enum KeyBinding: Equatable, Hashable, Codable, Sendable {
    case disabled
    case key(modifiers: Modifiers, usage: UInt8)
    case media(MediaAction)
    case mouse(MouseButton)
    case lighting(LightingAction)
    case macro(UInt16)
    /// Activates the Fn layer while held (the factory action of the Fn key).
    case fnLayer
    case raw([UInt8])

    /// ⌃Space: macOS's default "Select the previous input source" shortcut.
    public static let languageSwitch = KeyBinding.key(modifiers: .leftCtrl, usage: 0x2C)

    public func encode() -> [UInt8] {
        switch self {
        case .disabled: return [0]
        case .key(let m, let u): return [1, m.rawValue, u]
        case .media(let a): return [2, a.rawValue]
        case .mouse(let b): return [3, 1, b.rawValue, 0]
        case .lighting(let a): return [9, a.rawValue]
        case .macro(let id): return [10, UInt8(id & 0xFF), UInt8(id >> 8)]
        case .fnLayer: return [0x1B]
        case .raw(let b): return b
        }
    }

    public static func decode(_ b: [UInt8]) -> KeyBinding {
        guard let a = b.first else { return .raw(b) }
        switch a {
        case 0: return .disabled
        case 1 where b.count >= 3: return .key(modifiers: Modifiers(rawValue: b[1]), usage: b[2])
        case 2 where b.count >= 2: return MediaAction(rawValue: b[1]).map { .media($0) } ?? .raw(b)
        case 3 where b.count >= 3 && b[1] == 1: return MouseButton(rawValue: b[2]).map { .mouse($0) } ?? .raw(b)
        case 9 where b.count >= 2: return LightingAction(rawValue: b[1]).map { .lighting($0) } ?? .raw(b)
        case 10 where b.count >= 3: return .macro(UInt16(b[1]) | UInt16(b[2]) << 8)
        case 0x1B: return .fnLayer
        default: return .raw(b)
        }
    }

    public var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .fnLayer: return "Fn layer"
        case .key(let m, let u) where m == .leftCtrl && u == 0x2C: return "Switch language (⌃Space)"
        case .key(let m, let u) where m == .leftGui && u == 0x50: return "Start of line (⌘←)"
        case .key(let m, let u) where m == .leftGui && u == 0x4F: return "End of line (⌘→)"
        case .key(let m, let u):
            let name = HIDUsage.name(u)
            if u == 0 { return m.symbols.isEmpty ? "None" : m.symbols }
            return m.symbols + name
        case .media(let a): return a.displayName
        case .mouse(let b): return b.displayName
        case .lighting(let a): return a.displayName
        case .macro(let id): return "Macro \(id)"
        case .raw(let b): return "Special (" + b.map { String(format: "%02X", $0) }.joined(separator: " ") + ")"
        }
    }
}

// MARK: - Macros

public enum MacroPlayback: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case once = 0, whileHeld = 1, toggleRepeat = 2
    public var id: UInt8 { rawValue }
    public var displayName: String { ["Play once", "Repeat while held", "Repeat until pressed again"][Int(rawValue)] }
}

public enum MacroDelayMode: UInt8, CaseIterable, Codable, Sendable, Identifiable {
    case recorded = 0, fixed = 1, random = 2
    public var id: UInt8 { rawValue }
}

public enum MacroAction: Equatable, Hashable, Codable, Sendable {
    case keyDown(UInt8)
    case keyUp(UInt8)
    case modifiers(Modifiers)
    case consumerDown(UInt16)
    case consumerUp(UInt16)
    case mouseButtons(UInt8)
    case scroll(Int8)
    case raw(type: UInt8, body: [UInt8])
}

public struct MacroEvent: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id = UUID()
    public var action: MacroAction
    /// Delay after this event, in milliseconds.
    public var delayMs: UInt32
    public init(_ action: MacroAction, delayMs: UInt32 = 20) { self.action = action; self.delayMs = delayMs }
    public static func == (a: MacroEvent, b: MacroEvent) -> Bool { a.action == b.action && a.delayMs == b.delayMs }
    public func hash(into h: inout Hasher) { h.combine(action); h.combine(delayMs) }
}

public enum MacroDelay {
    /// Top two bits: unit (1 ms, 10 ms, 100 ms, 1 s); low 14 bits: count.
    public static func encode(_ ms: UInt32) -> UInt16 {
        for scale in 0..<4 {
            let unit = UInt32(pow(10.0, Double(scale)))
            let count = (ms + unit / 2) / unit
            if count <= 0x3FFF { return UInt16(scale) << 14 | UInt16(count) }
        }
        return 3 << 14 | 0x3FFF
    }
    public static func decode(_ v: UInt16) -> UInt32 {
        UInt32(v & 0x3FFF) * UInt32(pow(10.0, Double(v >> 14)))
    }
}

extension MacroEvent {
    func write(_ w: inout ByteWriter) {
        switch action {
        case .modifiers(let m): w.u8(1); w.u8(m.rawValue)
        case .keyDown(let u): w.u8(2); w.u8(u)
        case .keyUp(let u): w.u8(3); w.u8(u)
        case .consumerDown(let u): w.u8(6); w.u16(u)
        case .consumerUp(let u): w.u8(7); w.u16(u)
        case .mouseButtons(let m): w.u8(10); w.u8(m)
        case .scroll(let d): w.u8(11); w.u8(UInt8(bitPattern: d))
        case .raw(let t, let b): w.u8(t); w.raw(b)
        }
        w.u16(MacroDelay.encode(delayMs))
    }

    static func read(_ r: inout ByteReader) throws -> MacroEvent {
        let t = try r.u8()
        let action: MacroAction
        switch t {
        case 1: action = .modifiers(Modifiers(rawValue: try r.u8()))
        case 2: action = .keyDown(try r.u8())
        case 3: action = .keyUp(try r.u8())
        case 4, 5, 10, 12: action = .raw(type: t, body: [try r.u8()])
        case 6: action = .consumerDown(try r.u16())
        case 7: action = .consumerUp(try r.u16())
        case 8, 9: action = .raw(type: t, body: try r.raw(2))
        case 11: action = .scroll(Int8(bitPattern: try r.u8()))
        default: action = .raw(type: t, body: [])
        }
        return MacroEvent(action, delayMs: MacroDelay.decode(try r.u16()))
    }

    public var displayName: String {
        switch action {
        case .keyDown(let u): return "↓ " + HIDUsage.name(u)
        case .keyUp(let u): return "↑ " + HIDUsage.name(u)
        case .modifiers(let m): return "Modifiers " + (m.symbols.isEmpty ? "released" : m.symbols)
        case .consumerDown(let u): return String(format: "↓ Media 0x%03X", u)
        case .consumerUp(let u): return String(format: "↑ Media 0x%03X", u)
        case .mouseButtons(let m): return m == 0 ? "Mouse buttons released" : "Mouse buttons \(m)"
        case .scroll(let d): return "Scroll \(d > 0 ? "up" : "down") \(abs(Int(d)))"
        case .raw(let t, let b): return "Event \(t) " + b.map { String(format: "%02X", $0) }.joined()
        }
    }
}

public struct Macro: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: UInt16
    public var name: String
    public var playback: MacroPlayback = .once
    public var events: [MacroEvent] = []
    public init(id: UInt16, name: String, playback: MacroPlayback = .once, events: [MacroEvent] = []) {
        self.id = id; self.name = name; self.playback = playback; self.events = events
    }

    /// Builds press/release events that type `text` (US layout, ASCII only).
    public static func typing(_ text: String, delayMs: UInt32 = 15) -> [MacroEvent] {
        var out: [MacroEvent] = []
        for ch in text {
            guard let (usage, shift) = HIDUsage.forCharacter(ch) else { continue }
            if shift { out.append(MacroEvent(.modifiers(.leftShift), delayMs: 5)) }
            out.append(MacroEvent(.keyDown(usage), delayMs: delayMs))
            out.append(MacroEvent(.keyUp(usage), delayMs: shift ? 5 : delayMs))
            if shift { out.append(MacroEvent(.modifiers([]), delayMs: delayMs)) }
        }
        return out
    }
}
