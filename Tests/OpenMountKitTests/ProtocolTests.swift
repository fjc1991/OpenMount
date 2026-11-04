import XCTest
@testable import OpenMountKit

final class ProtocolTests: XCTestCase {
    func hex(_ s: String) -> [UInt8] {
        let h = s.replacingOccurrences(of: " ", with: "")
        return stride(from: 0, to: h.count, by: 2).map { i in
            let a = h.index(h.startIndex, offsetBy: i); return UInt8(h[a..<h.index(a, offsetBy: 2)], radix: 16)!
        }
    }

    /// Open-session reply captured from a real Light Mount.
    func testDecodeCapturedReply() throws {
        var r = hex("0d000000010101000000000101 03") + [UInt8](repeating: 0, count: 48)
        r += [0x84, 0x2d]
        XCTAssertEqual(r.count, 64)
        let f = try QLinkFrame.decode(r)
        XCTAssertEqual(f.session, 0)
        XCTAssertFalse(f.more)
        let m = try XCTUnwrap(QLinkMessage(bytes: f.bytes))
        XCTAssertEqual(m.status, 0); XCTAssertEqual(m.requestID, 1); XCTAssertEqual(m.feature, 1); XCTAssertEqual(m.command, 1)
        XCTAssertEqual(m.payload, hex("00000000010103"))
    }

    func testBadCRCRejected() {
        var r = [UInt8](repeating: 0, count: 64); r[0] = 6
        XCTAssertThrowsError(try QLinkFrame.decode(r))
    }

    func testEncodeSingleFrame() throws {
        let frames = QLinkFrame.encode(message: QLinkMessage(requestID: 2, feature: 1, command: 5).bytes, session: 2)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(Array(frames[0][0...6]), hex("06 00 02 00 02 01 05"))
        XCTAssertEqual(try QLinkFrame.decode(frames[0]).bytes, hex("00 02 01 05"))
    }

    func testEncodeMultiFrame() throws {
        let msg = [UInt8](repeating: 0xAB, count: 130)
        let frames = QLinkFrame.encode(message: msg, session: 7)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0][1], 0x80); XCTAssertEqual(frames[1][1], 0x81); XCTAssertEqual(frames[2][1], 0x02)
        let joined = try frames.flatMap { try QLinkFrame.decode($0).bytes }
        XCTAssertEqual(joined, msg)
    }

    /// The exact payload that turned the keyboard orange.
    func testStaticLightingPayload() {
        var g = GlobalLighting(); g.effect = .staticColor; g.brightness = 100; g.speed = 50; g.primary = .beQuietOrange
        XCTAssertEqual(g.encode(), hex("00 00 64 32 00 e63000"))
    }

    func testRealtimeEncoding() {
        let p = RealtimeCommand.encode([.fill(first: 0, count: 168, color: .off), .single(index: 46, color: RGB(255, 0, 0)), .commit])
        XCTAssertEqual(p, hex("03 02 0000 a8 000000 03 2e00 ff0000 00"))
    }

    func testBindingRoundTrip() {
        let cases: [([UInt8], KeyBinding)] = [
            (hex("010029"), .key(modifiers: [], usage: 0x29)),
            (hex("010100"), .key(modifiers: .leftCtrl, usage: 0)),
            (hex("0207"), .media(.playPause)),
            (hex("0902"), .lighting(.nextEffect)),
            (hex("0a0100"), .macro(1)),
            (hex("1b"), .fnLayer),                       // factory Fn key, read from hardware
            (hex("01012c"), .languageSwitch),            // ⌃Space, verified switching EN/KO on macOS
        ]
        for (bytes, b) in cases {
            XCTAssertEqual(KeyBinding.decode(bytes), b)
            XCTAssertEqual(b.encode(), bytes)
        }
        XCTAssertEqual(KeyBinding.decode(hex("12")), .raw([0x12]))
    }

    func testMacroDelay() {
        XCTAssertEqual(MacroDelay.encode(10), 10)
        XCTAssertEqual(MacroDelay.encode(16383), 0x3FFF)
        XCTAssertEqual(MacroDelay.encode(20000), 1 << 14 | 2000)
        XCTAssertEqual(MacroDelay.decode(1 << 14 | 2000), 20000)
        XCTAssertEqual(MacroDelay.decode(3 << 14 | 5), 5000)
    }

    /// The macro that typed "hi" on the real keyboard.
    func testMacroEventEncoding() throws {
        let events = Macro.typing("hi", delayMs: 10)
        var w = ByteWriter(); events.forEach { $0.write(&w) }
        XCTAssertEqual(w.bytes, hex("020b0a00 030b0a00 020c0a00 030c0a00"))
        var r = ByteReader(w.bytes)
        XCTAssertEqual(try MacroEvent.read(&r).action, .keyDown(0x0b))
    }

    func testKeyTables() {
        XCTAssertEqual(KeyID.escape.bindingIndex, 1)
        XCTAssertEqual(KeyID.escape.ledIndex, 46)
        XCTAssertEqual(KeyID.capsLock.bindingIndex, 9)
        XCTAssertEqual(Set(KeyID.allCases.map(\.bindingIndex)).count, KeyID.allCases.count)
        for p in PhysicalLayout.allCases {
            let ids = KeyboardLayout.lightMount(p).keys.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate keys in \(p)")
        }
    }

    /// Validates every community layout in Layouts/ (this is the check contributors' PRs must pass).
    func testCommunityLayouts() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Layouts").standardized
        let (layouts, problems) = LayoutLibrary.load(from: dir)
        XCTAssert(problems.isEmpty, "Layout problems:\n" + problems.map(\.description).joined(separator: "\n"))
        XCTAssertTrue(layouts.contains { $0.id == "ko-2set" })
        let template = try JSONDecoder().decode(LanguageLayout.self, from: Data(contentsOf: dir.appendingPathComponent("TEMPLATE.json")))
        XCTAssertEqual(LayoutLibrary.validate(template, fileName: "xx-name.json").count, 0, "the template itself should be valid")
    }

    func testLayoutValidatorCatchesMistakes() {
        let bad = LanguageLayout(id: "Korean", name: "", language: "korean", authors: [], macInputSources: [],
                                 physicalLayout: .ansi, keys: ["Qq": .init(base: ""), "A": .init(base: "a", shift: "a")])
        let problems = LayoutLibrary.validate(bad, fileName: "x.json").map(\.message)
        XCTAssertGreaterThanOrEqual(problems.count, 6)
    }

    func testHIDUsageMapping() {
        XCTAssertEqual(KeyID.q.hidUsage, 0x14)
        XCTAssertEqual(KeyID.fromHIDUsage(0x04), .a)
        XCTAssertEqual(KeyID.fromHIDUsage(0xE3), .leftGui)
    }

    func testVersionComparison() {
        XCTAssertTrue(Versioning.isNewer("0.2.1", than: "0.2.0"))
        XCTAssertTrue(Versioning.isNewer("v0.10.0", than: "0.9.9"))
        XCTAssertTrue(Versioning.isNewer("1.0", than: "0.99.99"))
        XCTAssertFalse(Versioning.isNewer("0.2.0", than: "0.2.0"))
        XCTAssertFalse(Versioning.isNewer("0.2", than: "0.2.0"))
        XCTAssertFalse(Versioning.isNewer("0.1.9", than: "0.2.0"))
    }
}
