import Foundation
import Photos

struct StorageManager {
    let originals: URL
    let staging: URL
    init(originals: URL, staging: URL) throws {
        self.originals = originals
        self.staging = staging
        for var directory in [originals, staging] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var flags = URLResourceValues()
            flags.isExcludedFromBackup = true
            try directory.setResourceValues(flags)
        }
    }
    static func local() throws -> Self {
        try Self(originals: URL.documentsDirectory.appending(path: "Imports"), staging: URL.applicationSupportDirectory.appending(path: "Transfers"))
    }
    func partial(_ task: TransferTask) -> URL { staging.appending(path: task.id.uuidString + ".part") }
    func file(_ task: TransferTask) -> URL { originals.appending(path: task.localName) }
    func size(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
    func writer(_ task: TransferTask) throws -> FileHandle {
        let url = partial(task)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CameraError.invalid("Unable to create the partial file.") }
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        return handle
    }
    func promote(_ task: TransferTask) throws {
        guard size(partial(task)) == task.expected else { throw CameraError.invalid("Incomplete file on disk.") }
        try FileManager.default.moveItem(at: partial(task), to: file(task))
    }
}

enum PhotoLibraryManager {
    static func save(_ url: URL) async throws {
        let video = ["mov", "mp4", "avi"].contains(url.pathExtension.lowercased())
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else { throw CameraError.invalid("Allow Add Photos access in Settings to export this file.") }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: video ? .video : .photo, fileURL: url, options: nil)
        }
    }
}
