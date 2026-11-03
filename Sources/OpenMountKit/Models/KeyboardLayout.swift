import Foundation

/// One physical key cap, positioned in key units (1u = one standard key).
public struct KeyCap: Identifiable, Hashable, Sendable {
    public var id: KeyID
    public var x: Double
    public var y: Double
    public var width: Double = 1
    public var height: Double = 1
    public var isRound = false
    public var label: String { id.label }
}

public enum PhysicalLayout: String, CaseIterable, Codable, Sendable {
    case ansi = "ANSI"
    case iso = "ISO"
}

public struct KeyboardLayout: Sendable {
    public var keys: [KeyCap]
    public var width: Double { keys.map { $0.x + $0.width }.max() ?? 0 }
    public var height: Double { keys.map { $0.y + $0.height }.max() ?? 0 }

    public static func lightMount(_ physical: PhysicalLayout) -> KeyboardLayout {
        var k: [KeyCap] = []
        // Left macro column and dial. Main block starts at x = 1.5.
        let o = 1.5
        k.append(KeyCap(id: .dial, x: 0.1, y: 0, width: 1.1, height: 1.1, isRound: true))
        for (i, m) in [KeyID.m1, .m2, .m3, .m4, .m5].enumerated() {
            k.append(KeyCap(id: m, x: 0.2, y: 1.25 + Double(i)))
        }
        func row(_ y: Double, _ start: Double, _ items: [(KeyID, Double)]) {
            var x = o + start
            for (id, w) in items { k.append(KeyCap(id: id, x: x, y: y, width: w)); x += w }
        }
        // Function row
        k.append(KeyCap(id: .escape, x: o, y: 0))
        for (i, f) in [KeyID.f1, .f2, .f3, .f4].enumerated() { k.append(KeyCap(id: f, x: o + 2 + Double(i), y: 0)) }
        for (i, f) in [KeyID.f5, .f6, .f7, .f8].enumerated() { k.append(KeyCap(id: f, x: o + 6.5 + Double(i), y: 0)) }
        for (i, f) in [KeyID.f9, .f10, .f11, .f12].enumerated() { k.append(KeyCap(id: f, x: o + 11 + Double(i), y: 0)) }
        let nav = o + 15.25, pad = o + 18.5
        for (i, f) in [KeyID.printScreen, .scrollLock, .pauseBreak].enumerated() { k.append(KeyCap(id: f, x: nav + Double(i), y: 0)) }

        let y1 = 1.25
        row(y1, 0, [(.graveAccentAndTilde, 1), (.digit1, 1), (.digit2, 1), (.digit3, 1), (.digit4, 1), (.digit5, 1), (.digit6, 1),
                    (.digit7, 1), (.digit8, 1), (.digit9, 1), (.digit0, 1), (.minusAndUnderscore, 1), (.equalsAndPlus, 1), (.backspace, 2)])
        let iso = physical == .iso
        row(y1 + 1, 0, [(.tab, 1.5), (.q, 1), (.w, 1), (.e, 1), (.r, 1), (.t, 1), (.y, 1), (.u, 1), (.i, 1), (.o, 1), (.p, 1),
                        (.bracketLeft, 1), (.bracketRight, 1)] + (iso ? [] : [(.backslash, 1.5)]))
        row(y1 + 2, 0, [(.capsLock, 1.75), (.a, 1), (.s, 1), (.d, 1), (.f, 1), (.g, 1), (.h, 1), (.j, 1), (.k, 1), (.l, 1),
                        (.semicolonAndColon, 1), (.apostropheAndDoubleQuote, 1)] + (iso ? [(.nonUsTilde, 1)] : [(.enter, 2.25)]))
        if iso { k.append(KeyCap(id: .enter, x: o + 13.75, y: y1 + 1, width: 1.25, height: 2)) }
        row(y1 + 3, 0, (iso ? [(.leftShift, 1.25), (.nonUsBackslash, 1)] : [(.leftShift, 2.25)]) +
            [(.z, 1), (.x, 1), (.c, 1), (.v, 1), (.b, 1), (.n, 1), (.m, 1), (.commaAndLessThan, 1), (.periodAndBiggerThan, 1),
             (.slashAndQuestionMark, 1), (.rightShift, 2.75)])
        row(y1 + 4, 0, [(.leftCtrl, 1.25), (.leftGui, 1.25), (.leftAlt, 1.25), (.space, 6.25), (.rightAlt, 1.25), (.rightGui, 1.25),
                        (.fn, 1.25), (.rightCtrl, 1.25)])
        // Navigation cluster
        for (i, id) in [KeyID.insert, .home, .pageUp].enumerated() { k.append(KeyCap(id: id, x: nav + Double(i), y: y1)) }
        for (i, id) in [KeyID.delete, .end, .pageDown].enumerated() { k.append(KeyCap(id: id, x: nav + Double(i), y: y1 + 1)) }
        k.append(KeyCap(id: .upArrow, x: nav + 1, y: y1 + 3))
        for (i, id) in [KeyID.leftArrow, .downArrow, .rightArrow].enumerated() { k.append(KeyCap(id: id, x: nav + Double(i), y: y1 + 4)) }
        // Numpad
        for (i, id) in [KeyID.numLock, .numpadSlash, .numpadAsterisk, .numpadMinus].enumerated() { k.append(KeyCap(id: id, x: pad + Double(i), y: y1)) }
        for (i, id) in [KeyID.numpad7, .numpad8, .numpad9].enumerated() { k.append(KeyCap(id: id, x: pad + Double(i), y: y1 + 1)) }
        k.append(KeyCap(id: .numpadPlus, x: pad + 3, y: y1 + 1, height: 2))
        for (i, id) in [KeyID.numpad4, .numpad5, .numpad6].enumerated() { k.append(KeyCap(id: id, x: pad + Double(i), y: y1 + 2)) }
        for (i, id) in [KeyID.numpad1, .numpad2, .numpad3].enumerated() { k.append(KeyCap(id: id, x: pad + Double(i), y: y1 + 3)) }
        k.append(KeyCap(id: .numpadEnter, x: pad + 3, y: y1 + 3, height: 2))
        k.append(KeyCap(id: .numpad0, x: pad, y: y1 + 4, width: 2))
        k.append(KeyCap(id: .numpadPeriodAndDelete, x: pad + 2, y: y1 + 4))
        return KeyboardLayout(keys: k)
    }
}

public extension KeyID {
    /// Short legend for drawing on a key cap (US legends).
    var label: String {
        switch self {
        case .escape: return "Esc"
        case .graveAccentAndTilde: return "`"
        case .digit1: return "1"; case .digit2: return "2"; case .digit3: return "3"; case .digit4: return "4"; case .digit5: return "5"
        case .digit6: return "6"; case .digit7: return "7"; case .digit8: return "8"; case .digit9: return "9"; case .digit0: return "0"
        case .minusAndUnderscore: return "-"
        case .equalsAndPlus: return "="
        case .backspace: return "⌫"
        case .tab: return "Tab"
        case .bracketLeft: return "["
        case .bracketRight: return "]"
        case .backslash: return "\\"
        case .capsLock: return "Caps"
        case .semicolonAndColon: return ";"
        case .apostropheAndDoubleQuote: return "'"
        case .nonUsTilde: return "#"
        case .nonUsBackslash: return "\\"
        case .enter: return "Enter"
        case .leftShift, .rightShift: return "Shift"
        case .commaAndLessThan: return ","
        case .periodAndBiggerThan: return "."
        case .slashAndQuestionMark: return "/"
        case .leftCtrl, .rightCtrl: return "Ctrl"
        case .leftGui, .rightGui: return "Win"
        case .leftAlt, .rightAlt: return "Alt"
        case .space: return ""
        case .fn: return "Fn"
        case .printScreen: return "PrtSc"
        case .scrollLock: return "ScrLk"
        case .pauseBreak: return "Pause"
        case .insert: return "Ins"
        case .home: return "Home"
        case .pageUp: return "PgUp"
        case .delete: return "Del"
        case .end: return "End"
        case .pageDown: return "PgDn"
        case .upArrow: return "↑"; case .downArrow: return "↓"; case .leftArrow: return "←"; case .rightArrow: return "→"
        case .numLock: return "Num"
        case .numpadSlash: return "/"; case .numpadAsterisk: return "*"; case .numpadMinus: return "-"; case .numpadPlus: return "+"
        case .numpadEnter: return "Ent"
        case .numpadPeriodAndDelete: return "."
        case .numpad0: return "0"; case .numpad1: return "1"; case .numpad2: return "2"; case .numpad3: return "3"; case .numpad4: return "4"
        case .numpad5: return "5"; case .numpad6: return "6"; case .numpad7: return "7"; case .numpad8: return "8"; case .numpad9: return "9"
        case .dial: return "◉"
        case .dialRotateLeft: return "⟲"
        case .dialRotateRight: return "⟳"
        default: return rawValue
        }
    }
}
