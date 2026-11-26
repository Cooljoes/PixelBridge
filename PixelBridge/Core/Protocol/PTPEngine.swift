import Foundation
import Network

@MainActor protocol CameraTransport: AnyObject {
    var onLoss: (() -> Void)? { get set }
    func open(initiator: UUID) async throws -> CameraSession
    func download(_ file: MediaFile, write: (Data) throws -> Void) async throws
    func thumbnail(_ file: MediaFile) async throws -> Data
    func close()
}

@MainActor final class PTPEngine: CameraTransport {
    private let command: TCPChannel
    private let makeEvent: () -> TCPChannel
    private var event: TCPChannel?
    private var eventReader: Task<Void, Never>?
    private var sequence: UInt32 = 0
    private var working = false
    private var closed = false
    var onLoss: (() -> Void)? { didSet { command.onLoss = onLoss; event?.onLoss = onLoss } }

    init(host: String, port: NWEndpoint.Port, wifiOnly: Bool) {
        command = TCPChannel(host: host, port: port, wifiOnly: wifiOnly)
        makeEvent = { TCPChannel(host: host, port: port, wifiOnly: wifiOnly) }
    }

    func open(initiator: UUID) async throws -> CameraSession {
        try await command.send(.initiate(id: initiator))
        let ack = try await command.packet()
        var cursor = PacketReader(ack.body)
        guard ack.type == 2, ack.body.count >= 26 else { throw CameraError.invalid("Camera rejected command-channel initialization.") }
        let number = try cursor.read(UInt32.self)
        let guidBytes = try cursor.bytes(16)
        let guid = guidBytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        let name = try cursor.bytes(cursor.remaining - 4)
        guard name.count.isMultiple(of: 2), name.suffix(2) == Data([0, 0]),
              String(data: name.dropLast(2), encoding: .utf16LittleEndian) != nil,
              try cursor.read(UInt32.self) >> 16 == 1 else {
            throw CameraError.invalid("Unsupported responder identity or PTP/IP version.")
        }
        guard !closed else { throw CancellationError() }
        let events = makeEvent()
        event = events
        events.onLoss = onLoss
        var token = Data()
        token.put(number)
        try await events.send(PTPPacket(type: 3, body: token))
        let eventAck = try await events.packet()
        guard eventAck.type == 4, eventAck.body.isEmpty else { throw CameraError.invalid("Camera rejected the event channel.") }
        eventReader = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let packet = try await events.packet(idleAllowed: true)
                    switch packet.type {
                    case 13: try await events.send(PTPPacket(type: 14))
                    case 8, 14: continue
                    default: throw CameraError.invalid("Unexpected event-channel packet.")
                    }
                }
            } catch { if !Task.isCancelled { self?.onLoss?() } }
        }
        _ = try await dataset(0x1002, [1], hasData: false)
        var info = PacketReader(try await dataset(0x1001))
        _ = try info.bytes(8)
        _ = try info.string()
        _ = try info.read(UInt16.self)
        let operations = Set(try info.array(UInt16.self))
        for _ in 0..<4 { _ = try info.array(UInt16.self) }
        _ = try info.string()
        let model = try info.string()
        let firmware = try info.string()
        let device = CameraDevice(id: guid, model: model, firmware: firmware, operations: operations)
        var storageData = PacketReader(try await dataset(0x1004))
        let storageIDs = try storageData.array(UInt32.self)
        var files = [MediaFile]()
        var inspected = 0
        var truncated = false
        for storage in storageIDs {
            var list = PacketReader(try await dataset(0x1007, [storage, 0, 0]))
            let handles = try list.array(UInt32.self)
            let remaining = 200 - inspected
            truncated = truncated || handles.count > remaining
            for handle in handles.prefix(remaining) {
                inspected += 1
                var value = PacketReader(try await dataset(0x1008, [handle]))
                let card = try value.read(UInt32.self)
                let format = try value.read(UInt16.self)
                _ = try value.read(UInt16.self)
                let size = try value.read(UInt32.self)
                _ = try value.bytes(40)
                let name = try value.string()
                let captured = try value.string()
                if format != 0x3001 && !name.isEmpty {
                    files.append(MediaFile(id: handle, storage: card, format: format, size: size, name: name, captured: captured))
                }
            }
        }
        return CameraSession(device: device, storages: storageIDs.map(CameraStorage.init), files: files, listingTruncated: truncated)
    }

    func thumbnail(_ file: MediaFile) async throws -> Data { try await dataset(0x100a, [file.id]) }

    func download(_ file: MediaFile, write: (Data) throws -> Void) async throws {
        guard file.size != UInt32.max else { throw CameraError.invalid("This object requires extended size metadata.") }
        var received: UInt64 = 0
        try await transact(0x1009, [file.id], hasData: true, limit: UInt64(file.size)) { chunk in
            try write(chunk)
            received += UInt64(chunk.count)
        }
        guard received == file.size else { throw CameraError.invalid("The downloaded size differs from ObjectInfo.") }
    }

    private func dataset(_ code: UInt16, _ args: [UInt32] = [], hasData: Bool = true) async throws -> Data {
        var data = Data()
        try await transact(code, args, hasData: hasData, limit: 8 * 1024 * 1024) { data.append($0) }
        return data
    }

    private func transact(_ code: UInt16, _ args: [UInt32], hasData: Bool, limit: UInt64, write: (Data) throws -> Void) async throws {
        guard !working else { throw CameraError.busy }
        guard !closed else { throw CameraError.interrupted }
        working = true
        defer { working = false }
        let id = sequence
        sequence &+= 1
        try await command.send(.operation(code, id, args))
        var declared: UInt64?
        var received: UInt64 = 0
        var ended = false
        while true {
            let header = try await command.header()
            switch header.type {
            case 7:
                guard (6...26).contains(header.count), (header.count - 6).isMultiple(of: 4) else { throw CameraError.invalid("Malformed operation response.") }
                var reply = PacketReader(try await command.read(header.count))
                let result = try reply.read(UInt16.self)
                guard try reply.read(UInt32.self) == id else { throw CameraError.invalid("Response belongs to another transaction.") }
                guard result == 0x2001 else { throw CameraError.rejected(result) }
                guard !hasData || ended else { throw CameraError.invalid("Missing data phase.") }
                return
            case 9:
                guard hasData, declared == nil, header.count == 12 else { throw CameraError.invalid("Unexpected StartData.") }
                var start = PacketReader(try await command.read(12))
                guard try start.read(UInt32.self) == id else { throw CameraError.invalid("Unexpected data transaction.") }
                let length = try start.read(UInt64.self)
                guard length == .max || length <= limit else { throw CameraError.invalid("Object exceeds the expected size.") }
                declared = length
            case 10, 12:
                guard let declared, !ended, header.count >= 4 else { throw CameraError.invalid("Unexpected data frame.") }
                var transaction = PacketReader(try await command.read(4))
                guard try transaction.read(UInt32.self) == id else { throw CameraError.invalid("Unexpected data transaction.") }
                var remaining = header.count - 4
                received += UInt64(remaining)
                guard received <= min(declared, limit) else { throw CameraError.invalid("Excess object data.") }
                while remaining > 0 {
                    let chunk = try await command.read(min(remaining, 65536))
                    try write(chunk)
                    remaining -= chunk.count
                }
                if header.type == 12 {
                    guard declared == .max || declared == received else { throw CameraError.invalid("Incomplete object data.") }
                    ended = true
                }
            default: throw CameraError.invalid("Unexpected command-channel packet.")
            }
        }
    }

    func close() {
        closed = true
        eventReader?.cancel()
        command.close()
        event?.close()
    }
}
