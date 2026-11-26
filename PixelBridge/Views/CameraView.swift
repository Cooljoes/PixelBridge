import SwiftUI
import CoreBluetooth

struct CameraView: View {
    @Bindable var model: CameraViewModel
    @State private var joinOptions = false
    private enum Field { case address, ssid, password }
    @FocusState private var focused: Field?
    var body: some View {
        let link = model.link
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "camera.aperture").font(.largeTitle).foregroundStyle(.cyan)
                    Text(link.session?.device.model ?? "PixelBridge").font(.title.bold())
                    Label(link.state.rawValue, systemImage: link.session == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                    if let session = link.session {
                        Text("\(session.device.firmware) · \(session.storages.count) storage · \(session.files.count) files").font(.caption)
                        if link.source == .demo { Text("Simulated camera · Loopback TCP").font(.caption) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(8).foregroundStyle(.white)
                .listRowBackground(Color(red: 0.065, green: 0.095, blue: 0.15))
                if !link.message.isEmpty { Text(link.message).font(.callout) }
            }
            if link.canStart {
                Section("Camera Wi-Fi") {
                    TextField("Camera IPv4 address", text: $model.host).keyboardType(.decimalPad)
                        .accessibilityLabel("Camera IPv4 address").focused($focused, equals: .address)
                    DisclosureGroup("Join a camera hotspot", isExpanded: $joinOptions) {
                        TextField("SSID from camera", text: $model.ssid)
                            .autocorrectionDisabled().textInputAutocapitalization(.never).focused($focused, equals: .ssid)
                        SecureField("Hotspot password", text: $model.password).focused($focused, equals: .password)
                        Toggle("Remember in Keychain", isOn: $model.remember)
                    }
                    Button("Connect over Wi-Fi") {
                        focused = nil
                        model.connect()
                    }
                }
                Section("Nearby cameras") {
                    Button("Scan with Bluetooth") { link.bluetooth.scan() }
                    if !link.bluetooth.detail.isEmpty { Text(link.bluetooth.detail).font(.footnote) }
                    ForEach(link.bluetooth.devices, id: \.identifier) { device in
                        Button(device.name ?? "Nearby camera") { link.bluetooth.connect(device) }
                    }
                    if ![.failed, .disconnected].contains(link.bluetooth.state) {
                        Button("Stop Bluetooth") { link.bluetooth.stop() }
                    }
                }
                Section {
                    Button { link.connect(.demo) } label: { Label("Open demo camera", systemImage: "camera.metering.center.weighted") }
                } footer: { Text("Browse and import a sample JPEG on this device.") }
            } else {
                Section { Button("Disconnect", role: .destructive) { link.disconnect() } }
            }
        }
        .navigationTitle("Camera")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }
}
