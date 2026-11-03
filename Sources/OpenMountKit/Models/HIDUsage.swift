import Foundation

/// USB HID keyboard usages (page 0x07) with readable names.
public enum HIDUsage {
    public struct Entry: Identifiable, Hashable, Sendable {
        public var id: UInt8 { usage }
        public let usage: UInt8
        public let name: String
        public let group: String
    }

    public static let all: [Entry] = {
        var e: [Entry] = []
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { e.append(Entry(usage: UInt8(0x04 + i), name: String(c), group: "Letters")) }
        for (i, c) in "1234567890".enumerated() { e.append(Entry(usage: UInt8(0x1E + i), name: String(c), group: "Numbers")) }
        let misc: [(UInt8, String)] = [
            (0x28, "Return"), (0x29, "Esc"), (0x2A, "Backspace"), (0x2B, "Tab"), (0x2C, "Space"),
            (0x2D, "-"), (0x2E, "="), (0x2F, "["), (0x30, "]"), (0x31, "\\"), (0x32, "# (ISO)"), (0x33, ";"),
            (0x34, "'"), (0x35, "`"), (0x36, ","), (0x37, "."), (0x38, "/"), (0x39, "Caps Lock"),
            (0x64, "\\ (ISO)"), (0x65, "Menu"),
        ]
        e += misc.map { Entry(usage: $0.0, name: $0.1, group: "Symbols & editing") }
        for i in 0..<12 { e.append(Entry(usage: UInt8(0x3A + i), name: "F\(i + 1)", group: "Function keys")) }
        for i in 0..<12 { e.append(Entry(usage: UInt8(0x68 + i), name: "F\(i + 13)", group: "Function keys")) }
        let nav: [(UInt8, String)] = [
            (0x46, "Print Screen"), (0x47, "Scroll Lock"), (0x48, "Pause"), (0x49, "Insert"), (0x4A, "Home"),
            (0x4B, "Page Up"), (0x4C, "Delete"), (0x4D, "End"), (0x4E, "Page Down"), (0x4F, "→"), (0x50, "←"),
            (0x51, "↓"), (0x52, "↑"),
        ]
        e += nav.map { Entry(usage: $0.0, name: $0.1, group: "Navigation") }
        let pad: [(UInt8, String)] = [
            (0x53, "Num Lock"), (0x54, "Num /"), (0x55, "Num *"), (0x56, "Num -"), (0x57, "Num +"), (0x58, "Num Enter"),
            (0x59, "Num 1"), (0x5A, "Num 2"), (0x5B, "Num 3"), (0x5C, "Num 4"), (0x5D, "Num 5"), (0x5E, "Num 6"),
            (0x5F, "Num 7"), (0x60, "Num 8"), (0x61, "Num 9"), (0x62, "Num 0"), (0x63, "Num ."),
        ]
        e += pad.map { Entry(usage: $0.0, name: $0.1, group: "Numpad") }
        let mods: [(UInt8, String)] = [
            (0xE0, "Left Ctrl"), (0xE1, "Left Shift"), (0xE2, "Left ⌥ Option"), (0xE3, "Left ⌘ Command"),
            (0xE4, "Right Ctrl"), (0xE5, "Right Shift"), (0xE6, "Right ⌥ Option"), (0xE7, "Right ⌘ Command"),
        ]
        e += mods.map { Entry(usage: $0.0, name: $0.1, group: "Modifiers") }
        return e
    }()

    private static let byUsage: [UInt8: String] = Dictionary(all.map { ($0.usage, $0.name) }, uniquingKeysWith: { a, _ in a })

    public static func name(_ u: UInt8) -> String { byUsage[u] ?? String(format: "Key 0x%02X", u) }

    /// Modifier keys are bound as a modifier bit with usage 0 (that's how the keyboard stores them).
    public static func modifierBit(_ u: UInt8) -> Modifiers? {
        (0xE0...0xE7).contains(u) ? Modifiers(rawValue: 1 << (u - 0xE0)) : nil
    }

    /// US-layout usage for a printable character.
    public static func forCharacter(_ c: Character) -> (UInt8, Bool)? {
        let lower = "abcdefghijklmnopqrstuvwxyz"
        if let i = lower.firstIndex(of: c) { return (UInt8(0x04 + lower.distance(from: lower.startIndex, to: i)), false) }
        if let i = lower.uppercased().firstIndex(of: c) { return (UInt8(0x04 + lower.uppercased().distance(from: lower.startIndex, to: i)), true) }
        let plain: [Character: UInt8] = ["1": 0x1E, "2": 0x1F, "3": 0x20, "4": 0x21, "5": 0x22, "6": 0x23, "7": 0x24, "8": 0x25,
                                         "9": 0x26, "0": 0x27, "\n": 0x28, "\t": 0x2B, " ": 0x2C, "-": 0x2D, "=": 0x2E, "[": 0x2F,
                                         "]": 0x30, "\\": 0x31, ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38]
        if let u = plain[c] { return (u, false) }
        let shifted: [Character: UInt8] = ["!": 0x1E, "@": 0x1F, "#": 0x20, "$": 0x21, "%": 0x22, "^": 0x23, "&": 0x24, "*": 0x25,
                                           "(": 0x26, ")": 0x27, "_": 0x2D, "+": 0x2E, "{": 0x2F, "}": 0x30, "|": 0x31, ":": 0x33,
                                           "\"": 0x34, "~": 0x35, "<": 0x36, ">": 0x37, "?": 0x38]
        if let u = shifted[c] { return (u, true) }
        return nil
    }

    /// macOS virtual key code → HID usage, for recording macros from key presses in the app window.
    public static func fromMacKeyCode(_ k: UInt16) -> UInt8? {
        let map: [UInt16: UInt8] = [
            0: 0x04, 11: 0x05, 8: 0x06, 2: 0x07, 14: 0x08, 3: 0x09, 5: 0x0A, 4: 0x0B, 34: 0x0C, 38: 0x0D, 40: 0x0E, 37: 0x0F,
            46: 0x10, 45: 0x11, 31: 0x12, 35: 0x13, 12: 0x14, 15: 0x15, 1: 0x16, 17: 0x17, 32: 0x18, 9: 0x19, 13: 0x1A, 7: 0x1B,
            16: 0x1C, 6: 0x1D, 18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 23: 0x22, 22: 0x23, 26: 0x24, 28: 0x25, 25: 0x26, 29: 0x27,
            36: 0x28, 53: 0x29, 51: 0x2A, 48: 0x2B, 49: 0x2C, 27: 0x2D, 24: 0x2E, 33: 0x2F, 30: 0x30, 42: 0x31, 41: 0x33, 39: 0x34,
            50: 0x35, 43: 0x36, 47: 0x37, 44: 0x38, 57: 0x39, 10: 0x64,
            122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D, 96: 0x3E, 97: 0x3F, 98: 0x40, 100: 0x41, 101: 0x42, 109: 0x43, 103: 0x44, 111: 0x45,
            114: 0x49, 115: 0x4A, 116: 0x4B, 117: 0x4C, 119: 0x4D, 121: 0x4E, 124: 0x4F, 123: 0x50, 125: 0x51, 126: 0x52,
            71: 0x53, 75: 0x54, 67: 0x55, 78: 0x56, 69: 0x57, 76: 0x58, 83: 0x59, 84: 0x5A, 85: 0x5B, 86: 0x5C, 87: 0x5D, 88: 0x5E,
            89: 0x5F, 91: 0x60, 92: 0x61, 82: 0x62, 65: 0x63,
            59: 0xE0, 56: 0xE1, 58: 0xE2, 55: 0xE3, 62: 0xE4, 60: 0xE5, 61: 0xE6, 54: 0xE7,
        ]
        return map[k]
    }
}
