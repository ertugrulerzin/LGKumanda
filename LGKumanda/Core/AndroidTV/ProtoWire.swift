import Foundation

/// Minimal protobuf wire format for the Android TV remote protocol (polo pairing and remote messages).
/// Only varint (0) and length-delimited (2) fields are used by the protocol.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ field: Int, _ value: UInt64) {
        Self.appendVarint(UInt64(field << 3), to: &data)
        Self.appendVarint(value, to: &data)
    }
    mutating func varint(_ field: Int, _ value: Int) { varint(field, UInt64(bitPattern: Int64(value))) }
    mutating func bool(_ field: Int, _ value: Bool) { varint(field, value ? 1 : 0) }
    mutating func bytes(_ field: Int, _ value: Data) {
        Self.appendVarint(UInt64(field << 3 | 2), to: &data)
        Self.appendVarint(UInt64(value.count), to: &data)
        data.append(value)
    }
    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }
    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var inner = ProtoWriter()
        build(&inner)
        bytes(field, inner.data)
    }

    static func appendVarint(_ value: UInt64, to data: inout Data) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }
    /// Length-prefixed frame as sent on the wire.
    static func frame(_ payload: Data) -> Data {
        var out = Data()
        appendVarint(UInt64(payload.count), to: &out)
        out.append(payload)
        return out
    }
}

/// Decoded protobuf message: field number to values (varints as UInt64, length-delimited as Data).
struct ProtoMessage {
    private(set) var varints: [Int: [UInt64]] = [:]
    private(set) var blobs: [Int: [Data]] = [:]

    init?(_ data: Data) {
        var i = data.startIndex
        while i < data.endIndex {
            guard let key = Self.readVarint(data, &i) else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let v = Self.readVarint(data, &i) else { return nil }
                varints[field, default: []].append(v)
            case 2:
                guard let len = Self.readVarint(data, &i), len <= UInt64(data.endIndex - i) else { return nil }
                let end = i + Int(len)
                blobs[field, default: []].append(data.subdata(in: i..<end))
                i = end
            case 1: guard data.endIndex - i >= 8 else { return nil }; i += 8
            case 5: guard data.endIndex - i >= 4 else { return nil }; i += 4
            default: return nil
            }
        }
    }
    func has(_ field: Int) -> Bool { varints[field] != nil || blobs[field] != nil }
    func int(_ field: Int) -> Int? { varints[field]?.last.map { Int(truncatingIfNeeded: $0) } }
    func bool(_ field: Int) -> Bool? { varints[field]?.last.map { $0 != 0 } }
    func data(_ field: Int) -> Data? { blobs[field]?.last }
    func string(_ field: Int) -> String? { data(field).map { String(decoding: $0, as: UTF8.self) } }
    func message(_ field: Int) -> ProtoMessage? { data(field).flatMap(ProtoMessage.init) }

    static func readVarint(_ data: Data, _ i: inout Data.Index) -> UInt64? {
        var result: UInt64 = 0, shift: UInt64 = 0
        while i < data.endIndex, shift < 64 {
            let byte = data[i]; i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}

/// Splits a byte stream into length-prefixed frames; partial input is kept until the frame is complete.
struct ProtoFramer {
    private var buffer = Data()
    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while true {
            var i = buffer.startIndex
            guard let len = ProtoMessage.readVarint(buffer, &i), buffer.endIndex - i >= Int(len) else { break }
            frames.append(buffer.subdata(in: i..<(i + Int(len))))
            buffer = buffer.subdata(in: (i + Int(len))..<buffer.endIndex)
        }
        return frames
    }
}
