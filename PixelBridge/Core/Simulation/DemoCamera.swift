import Foundation
import Network

/// A camera responder bound exclusively to this device's loopback address.
/// Both entry points use the same initiator, sockets, packet reader and disk writer.
@MainActor final class DemoCamera {
    nonisolated static let id = UUID(uuidString: "65454250-0000-4100-8000-000000000001")!
    static let storage: UInt32 = 0x10001
    private var listener: NWListener?
    private var channels = [TCPChannel]()
    let responderID: UUID
    let jpeg: Data
    let delay: Duration
    let corruptDownload: Bool

    init(jpeg: Data, delay: Duration = .milliseconds(80), corruptDownload: Bool = false, responderID: UUID = DemoCamera.id) {
        self.responderID = responderID
        self.jpeg = jpeg
        self.delay = delay
        self.corruptDownload = corruptDownload
    }
    static func bundled() throws -> DemoCamera {
        guard let url = Bundle.main.url(forResource: "TestChart", withExtension: "jpg") else {
            throw CameraError.invalid("Sample JPEG is missing.")
        }
        return try DemoCamera(jpeg: Data(contentsOf: url))
    }

    func start() async throws -> NWEndpoint.Port {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.listener != nil else { connection.cancel(); return }
                let channel = TCPChannel(connection)
                self.channels.append(channel)
                do { try await self.serve(channel) } catch { }
                channel.close()
                self.channels.removeAll { $0 === channel }
            }
        }
        let (events, result) = AsyncThrowingStream<NWEndpoint.Port, Error>.makeStream()
        server.stateUpdateHandler = { [weak server] state in
            switch state {
            case .ready: if let port = server?.port { result.yield(port); result.finish() }
            case .failed(let error): result.finish(throwing: error)
            case .cancelled: result.finish(throwing: CancellationError())
            default: break
            }
        }
        server.start(queue: DispatchQueue(label: "PixelBridge.demo"))
        for try await port in events { return port }
        throw CameraError.interrupted
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for channel in channels { channel.close() }
        channels.removeAll()
    }

    private func serve(_ channel: TCPChannel) async throws {
        let first = try await channel.packet()
        if first.type == 3 {
            var link = PacketReader(first.body)
            guard try link.read(UInt32.self) == 7 else { throw CameraError.interrupted }
            try await channel.send(PTPPacket(type: 4))
            try await channel.send(PTPPacket(type: 13))
            guard try await channel.packet().type == 14 else { throw CameraError.interrupted }
            _ = try await channel.packet(idleAllowed: true)
            return
        }
        guard first.type == 1 else { throw CameraError.interrupted }
        var ack = Data()
        ack.put(UInt32(7))
        var guid = responderID.uuid
        withUnsafeBytes(of: &guid) { ack.append(contentsOf: $0) }
        for unit in "Field Lab".utf16 { ack.put(unit) }
        ack.put(UInt16(0))
        ack.put(UInt32(0x10000))
        try await channel.send(PTPPacket(type: 2, body: ack))
        var opened = false
        while true {
            let packet = try await channel.packet(idleAllowed: true)
            guard packet.type == 6 else { throw CameraError.interrupted }
            var request = PacketReader(packet.body)
            guard try request.read(UInt32.self) == 1 else { throw CameraError.invalid("Unexpected data phase.") }
            let operation = try request.read(UInt16.self)
            let transaction = try request.read(UInt32.self)
            var data: Data?
            var code: UInt16 = 0x2001
            switch operation {
            case 0x1002:
                guard transaction == 0, try request.read(UInt32.self) == 1 else { throw CameraError.interrupted }
                opened = true
            case _ where !opened: code = 0x2003
            case 0x1001: data = deviceInfo()
            case 0x1004: data = list([Self.storage])
            case 0x1007: data = list([UInt32(1)])
            case 0x1008: data = objectInfo()
            case 0x1009, 0x100a: data = jpeg
            default: code = 0x2005
            }
            if let data {
                var start = Data()
                start.put(transaction)
                start.put(UInt64(data.count))
                try await channel.send(PTPPacket(type: 9, body: start))
                var offset = 0
                repeat {
                    let end = min(offset + 8192, data.count)
                    var segment = Data()
                    segment.put(transaction)
                    segment.append(data[offset..<end])
                    if operation == 0x1009 {
                        try await Task.sleep(for: delay)
                        if corruptDownload && offset > 0 { channel.close(); return }
                    }
                    try await channel.send(PTPPacket(type: end == data.count ? 12 : 10, body: segment))
                    offset = end
                } while offset < data.count
            }
            var response = Data()
            response.put(code)
            response.put(transaction)
            try await channel.send(PTPPacket(type: 7, body: response))
        }
    }

    private func list<T: FixedWidthInteger>(_ values: [T]) -> Data {
        var data = Data()
        data.put(UInt32(values.count))
        for value in values { data.put(value) }
        return data
    }
    private func string(_ text: String) -> Data {
        var data = Data([UInt8(text.utf16.count + 1)])
        for value in text.utf16 { data.put(value) }
        data.put(UInt16(0))
        return data
    }
    private func deviceInfo() -> Data {
        var data = Data()
        data.put(UInt16(100))
        data.put(UInt32(0))
        data.put(UInt16(100))
        data.append(0)
        data.put(UInt16(0))
        data.append(list([UInt16(0x1001), 0x1002, 0x1004, 0x1007, 0x1008, 0x1009, 0x100a]))
        for _ in 0..<4 { data.put(UInt32(0)) }
        for field in ["PixelBridge", "Demo camera", "Fixture 1", ""] { data.append(string(field)) }
        return data
    }
    private func objectInfo() -> Data {
        var data = Data()
        data.put(Self.storage)
        data.put(UInt16(0x3801))
        data.put(UInt16(0))
        data.put(UInt32(jpeg.count))
        data.append(Data(repeating: 0, count: 40))
        for field in ["TestChart.jpg", "20260101T120000", "", ""] { data.append(string(field)) }
        return data
    }
}
