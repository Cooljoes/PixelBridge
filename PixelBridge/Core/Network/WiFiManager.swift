import Foundation
import NetworkExtension
import Network
import Security

enum WiFiManager {
    static func join(ssid: String, password: String) async throws {
        guard !ssid.isEmpty else { throw CameraError.invalid("Enter the SSID shown on your camera.") }
        let config = password.isEmpty ? NEHotspotConfiguration(ssid: ssid) : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        config.joinOnce = true
        do { try await NEHotspotConfigurationManager.shared.apply(config) }
        catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue { return }
    }
    static func forget(ssid: String) { NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid) }

    static func localAddress(_ host: String) -> Bool {
        guard let address = IPv4Address(host) else { return false }
        let b = Array(address.rawValue)
        return b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) ||
            (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254)
    }
}

/// The optional remembered hotspot password is device-only and available only while unlocked.
enum CameraKeychain {
    private static func key(_ ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.github.cooljoes.PixelBridge.wifi", kSecAttrAccount as String: ssid]
    }
    static func read(_ ssid: String) throws -> String? {
        var query = key(ssid)
        query[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw CameraError.invalid("Unable to read the camera password from Keychain.") }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ password: String, ssid: String) throws {
        let item = key(ssid)
        let fields: [String: Any] = [kSecValueData as String: Data(password.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(item as CFDictionary, fields as CFDictionary)
        let status = result == errSecItemNotFound ? SecItemAdd(item.merging(fields) { _, new in new } as CFDictionary, nil) : result
        guard status == errSecSuccess else { throw CameraError.invalid("Unable to save the camera password.") }
    }
    static func remove(_ ssid: String) throws {
        let status = SecItemDelete(key(ssid) as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else { throw CameraError.invalid("Unable to clear the camera password.") }
    }
}

@MainActor protocol WiFiPathObserving: AnyObject {
    var available: Bool? { get }
    var changed: ((Bool) -> Void)? { get set }
}

@MainActor final class NetworkMonitor: WiFiPathObserving {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private(set) var available: Bool?
    var changed: ((Bool) -> Void)?
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.available != available else { return }
                self.available = available
                self.changed?(available)
            }
        }
        monitor.start(queue: DispatchQueue(label: "PixelBridge.wifi"))
    }
    deinit { monitor.cancel() }
}
