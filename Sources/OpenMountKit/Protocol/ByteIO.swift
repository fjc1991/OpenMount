import Foundation

/// Little-endian payload writer.
public struct ByteWriter {
    public private(set) var bytes: [UInt8] = []
    public init() {}
    public mutating func u8(_ v: UInt8) { bytes.append(v) }
    public mutating func bool(_ v: Bool) { bytes.append(v ? 1 : 0) }
    public mutating func u16(_ v: UInt16) { bytes += [UInt8(v & 0xFF), UInt8(v >> 8)] }
    public mutating func u32(_ v: UInt32) { for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
    public mutating func raw(_ b: [UInt8]) { bytes += b }
}

/// Little-endian payload reader.
public struct ByteReader {
    public let bytes: [UInt8]
    public private(set) var offset = 0
    public init(_ b: [UInt8]) { bytes = b }
    public var remaining: Int { bytes.count - offset }
    public enum ReadError: Error { case short(needed: Int, have: Int) }
    mutating func need(_ n: Int) throws { if remaining < n { throw ReadError.short(needed: n, have: remaining) } }
    public mutating func u8() throws -> UInt8 { try need(1); defer { offset += 1 }; return bytes[offset] }
    public mutating func bool() throws -> Bool { try u8() != 0 }
    public mutating func u16() throws -> UInt16 { try need(2); defer { offset += 2 }; return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
    public mutating func u32() throws -> UInt32 {
        try need(4); defer { offset += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }
    public mutating func raw(_ n: Int) throws -> [UInt8] { try need(n); defer { offset += n }; return Array(bytes[offset..<offset + n]) }
}
