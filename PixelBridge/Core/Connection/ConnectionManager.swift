import Foundation
import Network
import Observation

@Observable @MainActor final class ConnectionManager {
    enum Source: Equatable { case demo, wifi(String) }
    private(set) var linkState: ConnectionState = .disconnected
    let bluetooth = BLEManager()
    var state: ConnectionState {
        linkState == .disconnected ? bluetooth.state : linkState
    }
    private(set) var session: CameraSession?
    private(set) var source: Source?
    var message = ""
    private(set) var previewFileID: UInt32?
    var thumbnail: Data?
    private(set) var readingThumbnail = false
    let transfers: TransferManager
    let path: any WiFiPathObserving
    private let makeEngine: @MainActor (String, NWEndpoint.Port, Bool) -> any CameraTransport
    private var engine: (any CameraTransport)?
    private var demo: DemoCamera?
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var retryTimer: Task<Void, Never>?
    private var attempts = 0
    private var expectedCamera: UUID?
    private var retryFile: MediaFile?
    private let initiator: UUID

    init(transfers: TransferManager, path: any WiFiPathObserving, initiator: UUID,
         makeEngine: @escaping @MainActor (String, NWEndpoint.Port, Bool) -> any CameraTransport = { PTPEngine(host: $0, port: $1, wifiOnly: $2) }) {
        self.makeEngine = makeEngine
        self.transfers = transfers
        self.path = path
        self.initiator = initiator
        path.changed = { [weak self] available in self?.pathChanged(available) }
    }
    var canStart: Bool { [.disconnected, .failed, .suspended].contains(linkState) }
    func connect(_ source: Source, ssid: String = "", password: String = "", remember: Bool = false) {
        guard canStart else { return }
        if case .wifi(let host) = source, !WiFiManager.localAddress(host) {
            message = "Enter the private IPv4 address shown by your camera."
            return
        }
        resetSession()
        if bluetooth.state != .bleConnected { bluetooth.stop() }
        self.source = source
        message = ""
        let ticket = generation
        linkState = ssid.isEmpty ? .ptpConnecting : .wifiConnecting
        worker = Task {
            do {
                if !ssid.isEmpty {
                    let secret = try password.isEmpty ? CameraKeychain.read(ssid) ?? "" : password
                    try await WiFiManager.join(ssid: ssid, password: secret)
                    try check(ticket)
                    if remember { try CameraKeychain.save(secret, ssid: ssid) }
                    linkState = .wifiConnected
                }
                try await establish(source, ticket)
            } catch { failed(error, ticket: ticket, recovering: false) }
        }
    }
    private func establish(_ source: Source, _ ticket: UUID) async throws {
        let host: String
        let port: NWEndpoint.Port
        let wifi: Bool
        switch source {
        case .demo:
            let camera = try DemoCamera.bundled()
            demo = camera
            port = try await camera.start()
            host = "127.0.0.1"
            wifi = false
        case .wifi(let address):
            host = address
            port = 15740
            wifi = true
        }
        try check(ticket)
        linkState = .ptpConnecting
        let client = makeEngine(host, port, wifi)
        engine = client
        client.onLoss = { [weak self] in
            guard let self, self.generation == ticket, [.ready, .transferring].contains(self.linkState) else { return }
            self.suspend("The camera closed its TCP connection.")
        }
        let opened = try await client.open(initiator: initiator)
        try check(ticket)
        if let expectedCamera, expectedCamera != opened.device.id {
            disconnect()
            linkState = .failed
            message = "A different camera answered. Choose Connect to start a new session."
            return
        }
        expectedCamera = opened.device.id
        session = opened
        linkState = .ready
        attempts = 0
        message = ""
        if let pending = retryFile {
            retryFile = nil
            if !pending.captured.isEmpty, opened.files.contains(pending) { download(pending) }
            else { message = "The interrupted object could not be matched. Choose the file again." }
        }
    }
    func download(_ file: MediaFile) {
        guard linkState == .ready, !readingThumbnail, let session, session.files.contains(file), let engine else { return }
        let ticket = generation
        retryFile = file
        linkState = .transferring
        worker = Task {
            do {
                try transfers.begin(file, device: session.device)
                try await engine.download(file) { data in
                    try check(ticket)
                    try transfers.append(data)
                }
                try check(ticket)
                try transfers.finish()
                retryFile = nil
                linkState = .ready
                message = "Saved " + file.name
            } catch {
                guard generation == ticket else { return }
                if error is NWError || (error as? CameraError).map({ if case .interrupted = $0 { return true }; return false }) == true {
                    suspend(error.localizedDescription)
                    return
                }
                // A write or framing error may leave unread bytes on the command channel.
                retryFile = nil
                failed(error, ticket: ticket, recovering: false)
            }
        }
    }
    func preview(_ file: MediaFile) {
        guard linkState == .ready, !readingThumbnail, let engine else { return }
        let ticket = generation
        thumbnail = nil
        previewFileID = file.id
        readingThumbnail = true
        worker = Task {
            defer { if generation == ticket { readingThumbnail = false } }
            do {
                let data = try await engine.thumbnail(file)
                try check(ticket)
                thumbnail = data
            } catch CameraError.rejected(let code) {
                if generation == ticket { message = CameraError.rejected(code).localizedDescription }
            } catch { failed(error, ticket: ticket, recovering: false) }
        }
    }
    func disconnect() {
        bluetooth.stop()
        resetSession()
    }
    private func resetSession() {
        invalidate(reason: "Disconnected by user.")
        expectedCamera = nil
        source = nil
        retryFile = nil
        attempts = 0
        linkState = .disconnected
    }
    private func check(_ ticket: UUID) throws {
        guard generation == ticket, !Task.isCancelled else { throw CancellationError() }
    }
    private func invalidate(reason: String) {
        generation = UUID()
        worker?.cancel()
        retryTimer?.cancel()
        engine?.close()
        engine = nil
        demo?.stop()
        demo = nil
        readingThumbnail = false
        thumbnail = nil
        session = nil
        message = reason
        do { try transfers.pause(reason) } catch { message += " " + error.localizedDescription }
    }
    private func failed(_ error: Error, ticket: UUID, recovering: Bool) {
        guard generation == ticket else { return }
        invalidate(reason: error.localizedDescription)
        linkState = recovering ? .suspended : .failed
        if recovering { scheduleReconnect() }
    }
    private func pathChanged(_ available: Bool) {
        guard case .wifi = source else { return }
        if available {
            if linkState == .suspended { scheduleReconnect() }
        } else if [.ready, .transferring, .reconnecting].contains(linkState) {
            suspend("Camera Wi-Fi disconnected.")
        }
    }
    private func suspend(_ reason: String) {
        invalidate(reason: reason)
        linkState = .suspended
        scheduleReconnect()
    }
    private func scheduleReconnect() {
        guard case .wifi = source, path.available == true, attempts < 3 else { return }
        retryTimer?.cancel()
        let ticket = generation
        retryTimer = Task {
            do {
                try await Task.sleep(for: .seconds(1 << attempts))
                try check(ticket)
                guard let source else { return }
                attempts += 1
                linkState = .reconnecting
                try await establish(source, ticket)
            } catch { if !Task.isCancelled { failed(error, ticket: ticket, recovering: true) } }
        }
    }
}
