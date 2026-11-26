import Testing
import SwiftData
import Foundation
@testable import PixelBridge

@MainActor private final class ManualPath: WiFiPathObserving {
    var available: Bool? = true
    var changed: ((Bool) -> Void)?
    func update(_ value: Bool) { available = value; changed?(value) }
}

struct ConnectionTests {
    @MainActor private func eventually(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let end = clock.now + .seconds(12)
        while !condition() {
            guard clock.now < end else { throw CameraError.invalid("Timed out waiting for connection state.") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test @MainActor func routeLossReopensAndRestartsOriginal() async throws {
        let bytes = Data(repeating: 37, count: 87913)
        let responder = DemoCamera(jpeg: bytes, delay: .milliseconds(40))
        defer { responder.stop() }
        let port = try await responder.start()
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try StorageManager(originals: root.appending(path: "originals"), staging: root.appending(path: "partial"))
        let container = try ModelContainer(for: TransferTask.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let transfers = try TransferManager(storage: store, context: container.mainContext)
        let path = ManualPath()
        var connections = 0
        let link = ConnectionManager(transfers: transfers, path: path, initiator: UUID()) { _, _, _ in
            connections += 1
            return PTPEngine(host: "127.0.0.1", port: port, wifiOnly: false)
        }
        defer { link.disconnect() }
        link.connect(.wifi("192.168.1.1"))
        link.connect(.wifi("192.168.1.2"))
        try await eventually { link.state == .ready }
        let file = try #require(link.session?.files.first)
        link.download(file)
        try await eventually { (transfers.active?.received ?? 0) > 0 }
        path.update(false)
        #expect(link.state == .suspended)
        let task = try #require(transfers.history().entries.first)
        #expect(task.received > 0 && task.received < Int64(bytes.count))
        #expect(store.size(store.file(task)) == nil)
        path.update(true)
        try await eventually { task.status == "saved" }
        #expect(connections == 2)
        #expect(try Data(contentsOf: store.file(task)) == bytes)
        #expect(try transfers.history().entries.count == 1)
    }
}

extension ConnectionTests {
    @Test @MainActor func changedCameraCannotReceivePendingTransfer() async throws {
        let source = Data(repeating: 42, count: 99_000)
        let first = DemoCamera(jpeg: source)
        let other = DemoCamera(jpeg: source, responderID: UUID())
        defer { first.stop(); other.stop() }
        let originalPort = try await first.start()
        let otherPort = try await other.start()
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try StorageManager(originals: root.appending(path: "imports"), staging: root.appending(path: "parts"))
        let container = try ModelContainer(for: TransferTask.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let transfers = try TransferManager(storage: store, context: container.mainContext)
        let path = ManualPath()
        var port = originalPort
        let link = ConnectionManager(transfers: transfers, path: path, initiator: UUID()) { _, _, _ in
            PTPEngine(host: "127.0.0.1", port: port, wifiOnly: false)
        }
        defer { link.disconnect() }
        link.connect(.wifi("192.168.1.1"))
        try await eventually { link.state == .ready }
        let item = try #require(link.session?.files.first)
        link.download(item)
        try await eventually { (transfers.active?.received ?? 0) > 0 }
        path.update(false)
        port = otherPort
        path.update(true)
        try await eventually { link.state == .failed }
        let journal = try #require(transfers.history().entries.first)
        #expect(journal.status == "suspended")
        #expect(store.size(store.file(journal)) == nil)
        #expect(link.session == nil)
    }
}
