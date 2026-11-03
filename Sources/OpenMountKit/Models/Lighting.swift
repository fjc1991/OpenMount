import Foundation

public struct RGB: Hashable, Codable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    public static let off = RGB(0, 0, 0)
    public static let beQuietOrange = RGB(0xE6, 0x30, 0x00)
    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    public init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8(v >> 16), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }
}

/// On-device effects the Light Mount firmware supports.
public enum LightingEffect: String, CaseIterable, Codable, Sendable, Identifiable {
    case staticColor = "Static"
    case colorWave = "ColorWave"
    case tornado = "Tornado"
    case breathing = "Breathing"
    case reactive = "Reactive"
    case matrix = "Matrix"
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .staticColor: return "Static"
        case .colorWave: return "Color Wave"
        case .tornado: return "Tornado"
        case .breathing: return "Breathing"
        case .reactive: return "Reactive"
        case .matrix: return "Matrix"
        }
    }
}
