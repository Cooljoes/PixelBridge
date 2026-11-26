import Foundation
import CryptoKit
import Testing
import SwiftData
@testable import PixelBridge

struct ProtocolTests {
    @Test func operationWireVector() {
        let packet = PTPPacket.operation(0x1007, 42, [0xffffffff, 0, 0])
        #expect(packet.encoded == Data([
            30,0,0,0, 6,0,0,0, 1,0,0,0, 7,16, 42,0,0,0, 255,255,255,255, 0,0,0,0, 0,0,0,0
        ]))
    }
    @Test func truncatedDatasets() {
        var array = PacketReader(Data([255,255,255,255]))
        #expect(throws: CameraError.self) { try array.array(UInt32.self) }
        var string = PacketReader(Data([2,65,0,66,0]))
        #expect(throws: CameraError.self) { try string.string() }
    }
    @Test func cameraAddresses() {
        #expect(WiFiManager.localAddress("172.31.255.1"))
        #expect(WiFiManager.localAddress("169.254.1.2"))
        for invalid in ["172.32.0.1", "8.8.8.8", "camera.example", "127.0.0.1"] { #expect(!WiFiManager.localAddress(invalid)) }
    }

    @Test @MainActor func dualChannelJPEGMatchesOriginal() async throws {
        let fixture = try #require(Bundle.main.url(forResource: "TestChart", withExtension: "jpg"))
        let source = try Data(contentsOf: fixture)
        let demo = DemoCamera(jpeg: source, delay: .zero)
        defer { demo.stop() }
        let port = try await demo.start()
        let engine = PTPEngine(host: "127.0.0.1", port: port, wifiOnly: false)
        defer { engine.close() }
        let session = try await engine.open(initiator: UUID())
        #expect(session.device.id == DemoCamera.id)
        #expect(session.device.model == "Demo camera")
        #expect(session.storages.map(\.id) == [DemoCamera.storage])
        let file = try #require(session.files.first)
        #expect(file.name == "TestChart.jpg")
        #expect(try await engine.thumbnail(file) == source)
        var saved = Data()
        try await engine.download(file) { saved.append($0) }
        #expect(SHA256.hash(data: saved) == SHA256.hash(data: source))
    }

    @Test @MainActor func brokenSocketPreservesPartialAndRetries() async throws {
        let bytes = Data((0..<32113).map { UInt8(truncatingIfNeeded: $0) })
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try StorageManager(originals: root.appending(path: "imports"), staging: root.appending(path: "parts"))
        // SQLite may retain open WAL handles until process exit. Let the simulator
        // reclaim its temporary database separately from the disposable media.
        let database = URL.temporaryDirectory.appending(path: UUID().uuidString + ".store")
        let config = ModelConfiguration(url: database)
        let container = try ModelContainer(for: TransferTask.self, configurations: config)
        let manager = try TransferManager(storage: storage, context: container.mainContext)
        for fail in [true, false] {
            let responder = DemoCamera(jpeg: bytes, delay: .zero, corruptDownload: fail)
            defer { responder.stop() }
            let client = PTPEngine(host: "127.0.0.1", port: try await responder.start(), wifiOnly: false)
            defer { client.close() }
            let session = try await client.open(initiator: UUID())
            let file = try #require(session.files.first)
            try manager.begin(file, device: session.device)
            if fail {
                await #expect(throws: (any Error).self) { try await client.download(file, write: manager.append) }
                try manager.pause("Cable-free fixture disconnected")
                let otherContext = ModelContext(container)
                let restored = try TransferManager(storage: storage, context: otherContext)
                let item = try #require(restored.history().entries.first)
                #expect(item.status == "suspended")
                #expect(item.received == 8192)
                #expect(storage.size(storage.file(item)) == nil)
            } else {
                try await client.download(file, write: manager.append)
                try manager.finish()
                let history = try manager.history()
                #expect(history.entries.count == 1)
                #expect(history.savedCount == 1)
                let item = try #require(history.entries.first)
                #expect(try Data(contentsOf: storage.file(item)) == bytes)
                #expect(storage.size(storage.partial(item)) == nil)
            }
        }
    }
}

extension ProtocolTests {
    @Test func independentHardwareProfiles() throws {
        let profiles = try CapabilityProfile.load()
        #expect(Set(profiles.map(\.model)) == ["Nikon Z9","Nikon Z8","Nikon Z6 III","Nikon Z5 II","Nikon Zf","Nikon Z50 II","Nikon ZR"])
        #expect(profiles.count == 7)
        #expect(profiles.allSatisfy { $0.firmware == nil && $0.raw == "Untested" && $0.uploadWhileOff == "Untested" })
    }
}
