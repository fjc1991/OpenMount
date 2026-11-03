import Foundation
import OpenMountKit

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
func parseHex(_ s: String) -> [UInt8] {
    let h = s.replacingOccurrences(of: " ", with: "")
    return stride(from: 0, to: h.count, by: 2).map { i in
        let a = h.index(h.startIndex, offsetBy: i); return UInt8(h[a..<h.index(a, offsetBy: 2)], radix: 16)!
    }
}

var args = Array(CommandLine.arguments.dropFirst())
let verbose = args.contains("-v"); args.removeAll { $0 == "-v" }
guard let cmd = args.first else {
    print("""
    usage: omctl [-v] <command>
      info                       firmware and device info
      req <feature> <cmd> [hex]  send one QLink request inside a session (hex values)
    """)
    exit(1)
}
do {
    let client = QLinkClient(transport: try HIDTransport.open())
    if verbose { client.log = { print($0) } }
    let s = try client.openSession(clientType: UInt8(ProcessInfo.processInfo.environment["OM_CLIENT"] ?? "1") ?? 1)
    defer { try? client.closeSession() }
    if verbose { print("session \(s.id) active=\(s.active)") }
    switch cmd {
    case "info":
        print("QLink version: " + String(format: "0x%08x", try client.qlinkVersion()))
        print("Device: \(try client.deviceInfo())")
        print("Features: " + hex(try client.supportedFeatures()))
    case "seq":
        // omctl seq "01 07 01" "10 0e" ...  (several requests in one session)
        for spec in args.dropFirst() {
            let parts = spec.split(separator: " ").map(String.init)
            let f = UInt8(parts[0], radix: 16)!, c = UInt8(parts[1], radix: 16)!
            let p = parts.count > 2 ? parseHex(parts[2...].joined()) : []
            do { print(spec, "->", hex(try client.request(f, c, p))) } catch { print(spec, "->", error) }
            Thread.sleep(forTimeInterval: 0.15)
        }
    case "paint-test":
        let dev = LightMountDevice(client: client)
        let colors = (0..<LightMountLEDs.count).map { i -> RGB in
            let h = Double(i) / Double(LightMountLEDs.count) * 6
            let x = UInt8(255 * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)))
            switch Int(h) { case 0: return RGB(255, x, 0); case 1: return RGB(x, 255, 0); case 2: return RGB(0, 255, x)
            case 3: return RGB(0, x, 255); case 4: return RGB(x, 0, 255); default: return RGB(255, 0, x) }
        }
        try dev.paint(colors)
        print("painted \(colors.count) LEDs")
    case "macro-text":
        let dev = LightMountDevice(client: client)
        var list = try dev.macros()
        let id = UInt16(args[1])!
        list.removeAll { $0.id == id }
        list.append(Macro(id: id, name: args[2], events: Macro.typing(args[3])))
        try dev.saveMacros(list.sorted { $0.id < $1.id })
        let back = try dev.macro(id)
        print("stored \(back.events.count) events:", back.events.map(\.displayName).joined(separator: ", "))
    case "restore-default":
        let dev = LightMountDevice(client: client)
        try dev.apply(GlobalLighting())
        print("restored static orange")
    case "req":
        let f = UInt8(args[1], radix: 16)!, c = UInt8(args[2], radix: 16)!
        let p = args.count > 3 ? parseHex(args[3...].joined()) : []
        print(hex(try client.request(f, c, p)))
    default:
        print("unknown command \(cmd)"); exit(1)
    }
} catch { print("error:", error); exit(2) }
