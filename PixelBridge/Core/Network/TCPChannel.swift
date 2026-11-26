import Foundation
import Network

@MainActor final class TCPChannel {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "PixelBridge.socket")
    var onLoss: (() -> Void)?

    init(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: Task { @MainActor in self?.onLoss?() }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    convenience init(host: String, port: NWEndpoint.Port, wifiOnly: Bool) {
        let parameters = NWParameters.tcp
        if wifiOnly { parameters.requiredInterfaceType = .wifi }
        self.init(NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters))
    }

    private func deadline() -> DispatchWorkItem {
        let work = DispatchWorkItem { [connection] in connection.cancel() }
        queue.asyncAfter(deadline: .now() + 12, execute: work)
        return work
    }

    func send(_ packet: PTPPacket) async throws {
        let timer = deadline()
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (next: CheckedContinuation<Void, Error>) in
            connection.send(content: packet.encoded, completion: .contentProcessed { error in
                if let error { next.resume(throwing: error) } else { next.resume() }
            })
        }
    }

    func read(_ length: Int, idleAllowed: Bool = false) async throws -> Data {
        var buffer = Data()
        while buffer.count < length {
            try Task.checkCancellation()
            let count = min(65536, length - buffer.count)
            let timer = idleAllowed && buffer.isEmpty ? nil : deadline()
            let bytes: Data
            do {
                bytes = try await withCheckedThrowingContinuation { next in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: count) { data, _, _, error in
                        if let data, !data.isEmpty { next.resume(returning: data) }
                        else { next.resume(throwing: error ?? CameraError.interrupted as Error) }
                    }
                }
            } catch { timer?.cancel(); throw error }
            timer?.cancel()
            buffer.append(bytes)
        }
        return buffer
    }

    func header(idleAllowed: Bool = false) async throws -> (type: UInt32, count: Int) {
        var reader = PacketReader(try await read(8, idleAllowed: idleAllowed))
        let length = try reader.read(UInt32.self)
        guard length >= 8 else { throw CameraError.invalid("Invalid PTP/IP frame length.") }
        return (try reader.read(UInt32.self), Int(length) - 8)
    }

    func packet(idleAllowed: Bool = false, limit: Int = 65536) async throws -> PTPPacket {
        let header = try await header(idleAllowed: idleAllowed)
        guard header.count <= limit else { throw CameraError.invalid("Oversized control frame.") }
        return PTPPacket(type: header.type, body: try await read(header.count))
    }
    func close() { onLoss = nil; connection.cancel() }
}
