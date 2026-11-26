import Foundation
import SwiftData
import Observation

@Observable @MainActor final class TransferManager {
    let storage: StorageManager
    private let context: ModelContext
    private(set) var active: TransferTask?
    private var output: FileHandle?
    private var lastCheckpoint: Int64 = 0
    private var started = Date()
    var bytesPerSecond: Double { active.map { Double($0.received) / max(0.01, Date().timeIntervalSince(started)) } ?? 0 }
    var eta: TimeInterval? {
        guard let active, bytesPerSecond > 0 else { return nil }
        return Double(active.expected - active.received) / bytesPerSecond
    }

    init(storage: StorageManager, context: ModelContext) throws {
        self.storage = storage
        self.context = context
        for item in try history().entries {
            if storage.size(storage.file(item)) == item.expected {
                item.status = TransferState.saved.rawValue
                item.received = item.expected
            } else if item.status == TransferState.saved.rawValue {
                item.status = TransferState.failed.rawValue
                item.detail = "The local original is missing or its size changed."
            } else {
                item.received = storage.size(storage.partial(item)) ?? 0
                item.status = TransferState.suspended.rawValue
            }
        }
        try context.save()
    }
    func history() throws -> TransferHistory {
        try TransferHistory(entries: context.fetch(FetchDescriptor<TransferTask>()).sorted { $0.created > $1.created })
    }
    func begin(_ file: MediaFile, device: CameraDevice) throws {
        guard active == nil else { throw CameraError.busy }
        let match = try history().entries.first { $0.matches(file, on: device.id) && $0.status != TransferState.saved.rawValue }
        let task = match ?? TransferTask(camera: device.id, file: file)
        if match == nil { context.insert(task) }
        output = try storage.writer(task)
        active = task
        task.received = 0
        task.detail = ""
        task.status = TransferState.downloading.rawValue
        started = .now
        lastCheckpoint = 0
        try context.save()
    }
    func append(_ data: Data) throws {
        guard let active, let output else { throw CameraError.interrupted }
        try output.write(contentsOf: data)
        active.received += Int64(data.count)
        if active.received - lastCheckpoint >= 1_048_576 {
            try output.synchronize()
            try context.save()
            lastCheckpoint = active.received
        }
    }
    func finish() throws {
        guard let active, let output else { throw CameraError.interrupted }
        try output.synchronize()
        try output.close()
        self.output = nil
        try storage.promote(active)
        active.status = TransferState.saved.rawValue
        try context.save()
        self.active = nil
    }
    func pause(_ reason: String) throws {
        guard let active else { return }
        defer { output = nil; self.active = nil }
        // Data already written survives a disconnect. On launch, reconcile using actual file size.
        try output?.close()
        active.received = storage.size(storage.partial(active)) ?? 0
        active.status = TransferState.suspended.rawValue
        active.detail = reason
        try context.save()
    }
}
