import Foundation
import Observation
import ImageIO
import UIKit

struct AppSettings {
    let defaults: UserDefaults
    var host: String {
        get { defaults.string(forKey: "cameraHost") ?? "192.168.1.1" }
        nonmutating set { defaults.set(newValue, forKey: "cameraHost") }
    }
    var initiator: UUID {
        if let text = defaults.string(forKey: "initiator"), let id = UUID(uuidString: text) { return id }
        let id = UUID()
        defaults.set(id.uuidString, forKey: "initiator")
        return id
    }
}

@Observable @MainActor final class CameraViewModel {
    var host: String
    var ssid = ""
    var password = ""
    var remember = false
    let settings: AppSettings
    let link: ConnectionManager
    init(_ link: ConnectionManager, settings: AppSettings) {
        self.link = link
        self.settings = settings
        host = settings.host
    }
    func connect() {
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if WiFiManager.localAddress(address) { settings.host = address }
        link.connect(.wifi(address), ssid: ssid, password: password, remember: remember)
        password = ""
    }
}

@Observable @MainActor final class GalleryViewModel {
    var search = ""
    let link: ConnectionManager
    init(_ link: ConnectionManager) { self.link = link }
    var files: [MediaFile] {
        (link.session?.files ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    static func image(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1000,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: preview)
    }
}

@Observable @MainActor final class TransferViewModel {
    let link: ConnectionManager
    var notice = ""
    init(_ link: ConnectionManager) { self.link = link }
    func export(_ item: TransferTask) async {
        do { try await PhotoLibraryManager.save(link.transfers.storage.file(item)); notice = "Saved to Photos." }
        catch { notice = error.localizedDescription }
    }
    func retry(_ item: TransferTask) {
        guard let session = link.session, let file = session.files.first(where: { item.matches($0, on: session.device.id) }) else {
            notice = "Reconnect to the same camera and card to retry."
            return
        }
        link.download(file)
    }
}

@Observable @MainActor final class SettingsViewModel {
    var ssid = ""
    var message = ""
    func forget() {
        guard !ssid.isEmpty else { return }
        do {
            try CameraKeychain.remove(ssid)
            WiFiManager.forget(ssid: ssid)
            message = "Cleared this hotspot’s saved settings."
        } catch { message = error.localizedDescription }
    }
}
