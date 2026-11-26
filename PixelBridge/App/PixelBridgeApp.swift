import SwiftUI
import SwiftData

@main @MainActor struct PixelBridgeApp: App {
    private let setup: Result<(ModelContainer, ConnectionManager), Error>
    init() {
        setup = Result {
            let testing = ProcessInfo.processInfo.arguments.contains("-UITesting")
            let container = try ModelContainer(for: TransferTask.self, configurations: ModelConfiguration(isStoredInMemoryOnly: testing))
            let storage: StorageManager
            if testing {
                let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                storage = try StorageManager(originals: root.appending(path: "imports"), staging: root.appending(path: "parts"))
            } else { storage = try .local() }
            let transfers = try TransferManager(storage: storage, context: container.mainContext)
            return (container, ConnectionManager(transfers: transfers, path: NetworkMonitor(), initiator: AppSettings(defaults: .standard).initiator))
        }
    }
    var body: some Scene {
        WindowGroup {
            switch setup {
            case let .success((container, link)):
                WorkspaceView(link: link).modelContainer(container)
            case .failure(let error):
                ContentUnavailableView("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(error.localizedDescription))
            }
        }
    }
}

struct WorkspaceView: View {
    @State var camera: CameraViewModel
    @State var gallery: GalleryViewModel
    @State var transfers: TransferViewModel
    @State var settings = SettingsViewModel()
    init(link: ConnectionManager) {
        _camera = State(initialValue: CameraViewModel(link, settings: AppSettings(defaults: .standard)))
        _gallery = State(initialValue: GalleryViewModel(link))
        _transfers = State(initialValue: TransferViewModel(link))
    }
    var body: some View {
        TabView {
            NavigationStack { CameraView(model: camera) }
                .tabItem { Label("Camera", systemImage: "camera") }
            NavigationStack { GalleryView(model: gallery) }
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }
            NavigationStack { TransferView(model: transfers) }
                .tabItem { Label("Transfers", systemImage: "arrow.down.circle") }
            NavigationStack { SettingsView(model: settings) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.blue)
    }
}
