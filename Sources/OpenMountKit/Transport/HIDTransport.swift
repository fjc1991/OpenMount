import Foundation
import IOKit.hid

/// Raw 64-byte packet channel to the keyboard's vendor HID interface (usage page 0xFF00, usage 0x01).
public protocol PacketTransport: AnyObject, Sendable {
    func send(_ packet: [UInt8]) throws
    /// Waits for the next input report. Returns nil on timeout.
    func receive(timeout: TimeInterval) throws -> [UInt8]?
    func drain()
}

public enum TransportError: Error, CustomStringConvertible {
    case deviceNotFound
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case packetTooLarge(Int)

    public var description: String {
        switch self {
        case .deviceNotFound: return "Light Mount keyboard not found"
        case .openFailed(let r): return String(format: "Could not open the keyboard (IOReturn 0x%08x)", r)
        case .writeFailed(let r): return String(format: "Write to the keyboard failed (IOReturn 0x%08x)", r)
        case .packetTooLarge(let n): return "Packet of \(n) bytes is larger than 64"
        }
    }
}

public struct DeviceMatch: Sendable, Hashable {
    public var vendorID: Int
    public var productID: Int
    public var name: String
    public static let lightMount = DeviceMatch(vendorID: 0x373F, productID: 0x0002, name: "Light Mount")
    public static let lightMountTKL = DeviceMatch(vendorID: 0x373F, productID: 0x0018, name: "Light Mount TKL")
    public static let all: [DeviceMatch] = [.lightMount]
}

/// IOHIDManager-backed transport. Input reports are queued on a private run-loop thread.
public final class HIDTransport: PacketTransport, @unchecked Sendable {
    public static let reportSize = 64
    public static let vendorUsagePage = 0xFF00

    private let device: IOHIDDevice
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private var queue: [[UInt8]] = []
    private let cond = NSCondition()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    public let match: DeviceMatch

    /// Finds the vendor interface of the first connected supported keyboard.
    public static func open(matches: [DeviceMatch] = DeviceMatch.all) throws -> HIDTransport {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let dicts = matches.map {
            [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID,
             kIOHIDPrimaryUsagePageKey: vendorUsagePage, kIOHIDPrimaryUsageKey: 1] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, dicts as CFArray)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let dev = devices.first else {
            throw TransportError.deviceNotFound
        }
        let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let m = matches.first { $0.productID == pid } ?? .lightMount
        return try HIDTransport(device: dev, match: m)
    }

    init(device: IOHIDDevice, match: DeviceMatch) throws {
        self.device = device
        self.match = match
        inputBuffer = .allocate(capacity: Self.reportSize)
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { inputBuffer.deallocate(); throw TransportError.openFailed(r) }
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [unowned self] in
            self.runLoop = CFRunLoopGetCurrent()
            IOHIDDeviceScheduleWithRunLoop(self.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(self.device, self.inputBuffer, Self.reportSize, { ctx, _, _, _, _, report, length in
                guard let ctx else { return }
                let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
                me.enqueue(Array(UnsafeBufferPointer(start: report, count: length)))
            }, ctx)
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "OpenMount.HID"
        thread = t
        t.start()
        ready.wait()
    }

    deinit { close() }

    public func close() {
        if let rl = runLoop {
            IOHIDDeviceUnscheduleFromRunLoop(device, rl, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopStop(rl)
            runLoop = nil
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func enqueue(_ p: [UInt8]) {
        cond.lock(); queue.append(p); cond.signal(); cond.unlock()
    }

    public func send(_ packet: [UInt8]) throws {
        guard packet.count <= Self.reportSize else { throw TransportError.packetTooLarge(packet.count) }
        var buf = packet + [UInt8](repeating: 0, count: Self.reportSize - packet.count)
        let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &buf, buf.count)
        guard r == kIOReturnSuccess else { throw TransportError.writeFailed(r) }
    }

    public func receive(timeout: TimeInterval) throws -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock(); defer { cond.unlock() }
        while queue.isEmpty {
            if !cond.wait(until: deadline) { return nil }
        }
        return queue.removeFirst()
    }

    public func drain() {
        cond.lock(); queue.removeAll(); cond.unlock()
    }
}
