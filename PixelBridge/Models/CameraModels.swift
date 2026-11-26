import Foundation
import SwiftData

enum ConnectionState: String {
    case disconnected = "Disconnected", discovering = "Discovering"
    case bleConnecting = "BLE connecting", bleConnected = "BLE connected"
    case wifiConnecting = "Joining Wi-Fi", wifiConnected = "Wi-Fi connected"
    case ptpConnecting = "Opening PTP/IP", ready = "Ready", transferring = "Transferring"
    case suspended = "Suspended", reconnecting = "Reconnecting", failed = "Failed"
}

struct CameraDevice: Equatable {
    let id: UUID
    let model: String
    let firmware: String
    let operations: Set<UInt16>
}

struct CameraStorage: Identifiable, Hashable { let id: UInt32 }

struct MediaFile: Identifiable, Hashable {
    let id: UInt32
    let storage: UInt32
    let format: UInt16
    let size: UInt32
    let name: String
    let captured: String
}

struct CameraSession {
    let device: CameraDevice
    let storages: [CameraStorage]
    let files: [MediaFile]
    let listingTruncated: Bool
}

enum TransferState: String { case queued, downloading, suspended, saved, failed }

@Model final class TransferTask {
    @Attribute(.unique) var id: UUID
    var cameraID: UUID
    var storageID: Int64
    var objectHandle: Int64
    var filename: String
    var captured: String
    var expected: Int64
    var received: Int64
    var status: String
    var created: Date
    var detail: String
    var localName: String

    init(camera: UUID, file: MediaFile) {
        let taskID = UUID()
        id = taskID
        cameraID = camera
        storageID = Int64(file.storage)
        objectHandle = Int64(file.id)
        filename = file.name
        captured = file.captured
        expected = Int64(file.size)
        received = 0
        status = TransferState.queued.rawValue
        created = .now
        detail = ""
        let leaf = String(file.name.map { $0.isLetter || $0.isNumber || "._-".contains($0) ? $0 : "_" }.prefix(90))
        localName = taskID.uuidString + "-" + (leaf.isEmpty ? "original" : leaf)
    }

    func matches(_ file: MediaFile, on camera: UUID) -> Bool {
        cameraID == camera && storageID == Int64(file.storage) && objectHandle == Int64(file.id) &&
        filename == file.name && captured == file.captured && expected == Int64(file.size)
    }
}

struct TransferHistory {
    let entries: [TransferTask]
    var savedCount: Int { entries.filter { $0.status == TransferState.saved.rawValue }.count }
}

enum CameraError: LocalizedError {
    case invalid(String), rejected(UInt16), interrupted, busy
    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .rejected(let code): return String(format: "Camera returned PTP response 0x%04X.", code)
        case .interrupted: return "The camera connection closed. Partial files are kept for retry."
        case .busy: return "Another camera operation is in progress."
        }
    }
}
