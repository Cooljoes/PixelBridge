import Foundation

extension Data {
    mutating func put<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

struct PacketReader {
    let data: Data
    private(set) var offset = 0
    init(_ data: Data) { self.data = data }
    var remaining: Int { data.count - offset }
    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw CameraError.invalid("Truncated PTP dataset.") }
        let start = data.startIndex + offset
        offset += count
        return data.subdata(in: start..<(start + count))
    }
    mutating func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let field = try bytes(MemoryLayout<T>.size)
        return field.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(as: T.self)) }
    }
    mutating func array<T: FixedWidthInteger>(_ type: T.Type) throws -> [T] {
        let count = Int(try read(UInt32.self))
        guard count <= remaining / MemoryLayout<T>.size, count <= 500_000 else { throw CameraError.invalid("Invalid PTP array length.") }
        return try (0..<count).map { _ in try read(type) }
    }
    mutating func string() throws -> String {
        let count = Int(try read(UInt8.self))
        guard count > 0 else { return "" }
        let raw = try bytes(count * 2)
        guard raw.suffix(2) == Data([0,0]), let value = String(data: raw.dropLast(2), encoding: .utf16LittleEndian) else {
            throw CameraError.invalid("Malformed PTP string.")
        }
        return value
    }
}

// The frame and operation encoders adapt AeroShutter Mobile's MIT packet helpers.
// See Resources/Notices/AeroShutter-MIT.txt. CIPA DataPhaseInfo=1 covers reads and no-data requests.
struct PTPPacket {
    let type: UInt32
    var body = Data()
    var encoded: Data {
        var data = Data()
        data.put(UInt32(body.count + 8))
        data.put(type)
        data.append(body)
        return data
    }
    static func operation(_ code: UInt16, _ transaction: UInt32, _ parameters: [UInt32]) -> Self {
        var body = Data()
        body.put(UInt32(1))
        body.put(code)
        body.put(transaction)
        for value in parameters { body.put(value) }
        return Self(type: 6, body: body)
    }
    static func initiate(id: UUID) -> Self {
        var uuid = id.uuid
        var body = withUnsafeBytes(of: &uuid) { Data($0) }
        for unit in "PixelBridge".utf16 { body.put(unit) }
        body.put(UInt16(0))
        body.put(UInt32(0x10000))
        return Self(type: 1, body: body)
    }
}

enum NikonCommands {
    // Research identifiers only. A DeviceInfo opcode alone does not establish model support.
    static let getLargeThumb: UInt16 = 0x90c4
    static let getPartialObjectEx: UInt16 = 0x9431
}
