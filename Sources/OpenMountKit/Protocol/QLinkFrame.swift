import Foundation

/// QLink over USB HID: every 64-byte report is one frame.
///
///     [0]      length L of bytes [1 ... L]
///     [1]      sequence number (bits 0-6) | 0x80 when more frames follow
///     [2]      session id (0 before a session is opened)
///     [3...L]  message bytes (first frame starts with the 4-byte message header)
///     [62-63]  CRC-16/MODBUS of bytes 0...61, little-endian
///
/// Message header: [status/type, request id, feature id, command id], then the payload.
/// A request id of 0 marks an unsolicited notification from the device.
public enum QLinkFrame {
    public static let reportSize = 64
    public static let maxMessageBytesPerFrame = reportSize - 1 - 2 - 2   // 59

    public static func crc16(_ data: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in data {
            crc ^= UInt16(b)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }

    /// Splits a whole message (header + payload) into frames.
    public static func encode(message: [UInt8], session: UInt8) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        var offset = 0
        var seq: UInt8 = 0
        repeat {
            let chunk = Array(message[offset..<min(message.count, offset + maxMessageBytesPerFrame)])
            offset += chunk.count
            let more = offset < message.count
            var f = [UInt8](repeating: 0, count: reportSize)
            f[0] = UInt8(2 + chunk.count)
            f[1] = (seq & 0x7F) | (more ? 0x80 : 0)
            f[2] = session
            f.replaceSubrange(3..<(3 + chunk.count), with: chunk)
            let crc = crc16(f[0..<62])
            f[62] = UInt8(crc & 0xFF); f[63] = UInt8(crc >> 8)
            frames.append(f)
            seq &+= 1
        } while offset < message.count
        return frames
    }

    public struct Decoded: Equatable, Sendable {
        public var sequence: UInt8
        public var more: Bool
        public var session: UInt8
        public var bytes: [UInt8]
    }

    public enum DecodeError: Error, Equatable { case badLength, badCRC }

    public static func decode(_ r: [UInt8]) throws -> Decoded {
        guard r.count == reportSize, r[0] >= 2, Int(r[0]) <= 61 else { throw DecodeError.badLength }
        let crc = UInt16(r[62]) | UInt16(r[63]) << 8
        guard crc == crc16(r[0..<62]) else { throw DecodeError.badCRC }
        let l = Int(r[0])
        return Decoded(sequence: r[1] & 0x7F, more: r[1] & 0x80 != 0, session: r[2], bytes: Array(r[3...l]))
    }
}

public struct QLinkMessage: Equatable, Sendable {
    public var status: UInt8
    public var requestID: UInt8
    public var feature: UInt8
    public var command: UInt8
    public var payload: [UInt8]
    public var isNotification: Bool { requestID == 0 }

    public init(status: UInt8 = 0, requestID: UInt8, feature: UInt8, command: UInt8, payload: [UInt8] = []) {
        self.status = status; self.requestID = requestID; self.feature = feature; self.command = command; self.payload = payload
    }

    public var bytes: [UInt8] { [status, requestID, feature, command] + payload }

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 4 else { return nil }
        self.init(status: bytes[0], requestID: bytes[1], feature: bytes[2], command: bytes[3], payload: Array(bytes[4...]))
    }
}
