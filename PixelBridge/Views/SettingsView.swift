import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsViewModel
    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Originals", value: "Files → PixelBridge → Imports")
                Text("Photos export asks for add-only access when you save an original.").font(.footnote)
            }
            Section("Remembered hotspot") {
                TextField("Camera SSID", text: $model.ssid).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Forget this hotspot", role: .destructive) { model.forget() }.disabled(model.ssid.isEmpty)
                if !model.message.isEmpty { Text(model.message) }
            }
            Section("About") {
                Text("PixelBridge · 像素桥")
                Text("Connect Beyond the Lens.").foregroundStyle(.secondary)
                NavigationLink("Camera compatibility") { CapabilityProfilesView() }
                NavigationLink("Open-source notices") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "AeroShutter-MIT", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "See the bundled AeroShutter-MIT.txt notice.")
                            .textSelection(.enabled).padding()
                    }.navigationTitle("AeroShutter Mobile")
                }
            }
        }.navigationTitle("Settings")
    }
}

private struct CapabilityProfilesView: View {
    private let profiles = Result { try CapabilityProfile.load() }
    var body: some View {
        List {
            switch profiles {
            case .failure(let error): Text(error.localizedDescription)
            case .success(let entries):
                ForEach(entries) { profile in
                    DisclosureGroup(profile.model) {
                        LabeledContent("Firmware tested", value: profile.firmware ?? "—")
                        LabeledContent("BLE pairing", value: profile.blePairing)
                        LabeledContent("Wi-Fi", value: profile.wifi)
                        LabeledContent("PTP/IP", value: profile.ptpip)
                        LabeledContent("JPEG", value: profile.jpeg)
                        LabeledContent("NEF original", value: profile.raw)
                        LabeledContent("Video", value: profile.video)
                        LabeledContent("Upload While Off", value: profile.uploadWhileOff)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Upload While Off")
                            .accessibilityValue(profile.uploadWhileOff)
                            .accessibilityIdentifier("profile.uploadWhileOff")
                        LabeledContent("Offset resume", value: profile.offsetResume)
                    }
                }
            }
        }.navigationTitle("Camera compatibility")
    }
}
