import Foundation

/// A typing-language overlay: what each key produces in a given input source, drawn on top of the
/// keyboard's physical (US) legends. Community-contributed as JSON files in `Layouts/`.
public struct LanguageLayout: Codable, Identifiable, Hashable, Sendable {
    public struct Legend: Codable, Hashable, Sendable {
        /// Character produced without modifiers.
        public var base: String
        /// Character produced with Shift. Omit when it's the same as `base`.
        public var shift: String?
        public init(base: String, shift: String? = nil) { self.base = base; self.shift = shift }
    }

    /// Unique, lowercase id, e.g. "ko-2set". Must match the file name.
    public var id: String
    /// Name shown in the app, e.g. "Korean – 2-Set (두벌식)".
    public var name: String
    /// BCP 47 language code, e.g. "ko".
    public var language: String
    /// GitHub username(s) of the contributor(s).
    public var authors: [String]
    /// macOS input source ids this layout corresponds to (used to follow the active input source).
    /// Find yours with `defaults read com.apple.HIToolbox AppleSelectedInputSources`.
    public var macInputSources: [String]
    /// Physical layout the legends assume: "ANSI" or "ISO".
    public var physicalLayout: PhysicalLayout
    /// Legends keyed by OpenMount key name (see `KeyID`, e.g. "Q", "SemicolonAndColon").
    /// Keys you leave out keep their normal printed legend.
    public var keys: [String: Legend]

    public func legend(for key: KeyID) -> Legend? { keys[key.rawValue] }
}

public enum LayoutLibrary {
    public struct Problem: CustomStringConvertible, Sendable {
        public var file: String
        public var message: String
        public var description: String { "\(file): \(message)" }
    }

    /// Loads every `*.json` in `dir` except files starting with an underscore or named TEMPLATE.
    public static func load(from dir: URL) -> (layouts: [LanguageLayout], problems: [Problem]) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix("_") && $0.lastPathComponent != "TEMPLATE.json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var layouts: [LanguageLayout] = []
        var problems: [Problem] = []
        for f in files {
            do {
                let l = try JSONDecoder().decode(LanguageLayout.self, from: Data(contentsOf: f))
                let p = validate(l, fileName: f.lastPathComponent)
                problems += p
                if p.isEmpty { layouts.append(l) }
            } catch {
                problems.append(Problem(file: f.lastPathComponent, message: "isn't valid layout JSON (\(error))"))
            }
        }
        var seen: Set<String> = []
        for l in layouts where !seen.insert(l.id).inserted {
            problems.append(Problem(file: "\(l.id).json", message: "duplicate id \(l.id)"))
        }
        return (layouts.sorted { $0.name < $1.name }, problems)
    }

    /// Rules a submitted layout must pass (enforced in CI by the unit tests).
    public static func validate(_ l: LanguageLayout, fileName: String) -> [Problem] {
        var out: [Problem] = []
        func bad(_ m: String) { out.append(Problem(file: fileName, message: m)) }
        let idPattern = #"^[a-z]{2,3}(-[a-z0-9]+)*$"#
        if l.id.range(of: idPattern, options: .regularExpression) == nil { bad("id \"\(l.id)\" must look like \"ko-2set\" (lowercase, starts with a language code)") }
        if fileName != "\(l.id).json" { bad("file name must be \(l.id).json") }
        if l.name.trimmingCharacters(in: .whitespaces).isEmpty { bad("name is empty") }
        if l.language.range(of: #"^[a-z]{2,3}(-[A-Za-z0-9]+)*$"#, options: .regularExpression) == nil { bad("language must be a code like \"ko\" or \"pt-BR\"") }
        if l.authors.isEmpty || l.authors.contains(where: { $0.isEmpty }) { bad("add your GitHub username to authors") }
        if l.keys.isEmpty { bad("keys is empty") }
        let valid = Set(KeyID.allCases.map(\.rawValue))
        for (k, v) in l.keys.sorted(by: { $0.key < $1.key }) {
            if !valid.contains(k) { bad("unknown key \"\(k)\" (see the key names in Layouts/README.md)") }
            if v.base.isEmpty { bad("\(k): base is empty") }
            if v.base.count > 3 || (v.shift?.count ?? 0) > 3 { bad("\(k): legends should be at most 3 characters") }
            if let s = v.shift, s == v.base { bad("\(k): shift is the same as base, leave it out") }
        }
        if l.physicalLayout == .ansi, l.keys["NonUsTilde"] != nil || l.keys["NonUsBackslash"] != nil {
            bad("NonUsTilde / NonUsBackslash only exist on ISO keyboards; set physicalLayout to ISO")
        }
        return out
    }
}

public extension KeyID {
    /// HID keyboard usage (page 7) for keys that produce one, used to light up keys as they're typed.
    var hidUsage: UInt8? { KeyID.usageTable[self] }

    static func fromHIDUsage(_ u: UInt8) -> KeyID? { reverseUsageTable[u] }

    private static let usageTable: [KeyID: UInt8] = {
        var t: [KeyID: UInt8] = [
            .escape: 0x29, .graveAccentAndTilde: 0x35, .minusAndUnderscore: 0x2D, .equalsAndPlus: 0x2E, .backspace: 0x2A,
            .tab: 0x2B, .bracketLeft: 0x2F, .bracketRight: 0x30, .backslash: 0x31, .capsLock: 0x39,
            .semicolonAndColon: 0x33, .apostropheAndDoubleQuote: 0x34, .nonUsTilde: 0x32, .enter: 0x28,
            .leftShift: 0xE1, .nonUsBackslash: 0x64, .commaAndLessThan: 0x36, .periodAndBiggerThan: 0x37,
            .slashAndQuestionMark: 0x38, .rightShift: 0xE5, .leftCtrl: 0xE0, .leftGui: 0xE3, .leftAlt: 0xE2,
            .space: 0x2C, .rightAlt: 0xE6, .rightGui: 0xE7, .rightCtrl: 0xE4,
            .printScreen: 0x46, .scrollLock: 0x47, .pauseBreak: 0x48, .insert: 0x49, .home: 0x4A, .pageUp: 0x4B,
            .delete: 0x4C, .end: 0x4D, .pageDown: 0x4E, .rightArrow: 0x4F, .leftArrow: 0x50, .downArrow: 0x51, .upArrow: 0x52,
            .numLock: 0x53, .numpadSlash: 0x54, .numpadAsterisk: 0x55, .numpadMinus: 0x56, .numpadPlus: 0x57,
            .numpadEnter: 0x58, .numpad1: 0x59, .numpad2: 0x5A, .numpad3: 0x5B, .numpad4: 0x5C, .numpad5: 0x5D,
            .numpad6: 0x5E, .numpad7: 0x5F, .numpad8: 0x60, .numpad9: 0x61, .numpad0: 0x62, .numpadPeriodAndDelete: 0x63,
        ]
        let letters: [KeyID] = [.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z]
        for (i, k) in letters.enumerated() { t[k] = UInt8(0x04 + i) }
        let digits: [KeyID] = [.digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9, .digit0]
        for (i, k) in digits.enumerated() { t[k] = UInt8(0x1E + i) }
        let fkeys: [KeyID] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        for (i, k) in fkeys.enumerated() { t[k] = UInt8(0x3A + i) }
        return t
    }()

    private static let reverseUsageTable: [UInt8: KeyID] = Dictionary(usageTable.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
}
