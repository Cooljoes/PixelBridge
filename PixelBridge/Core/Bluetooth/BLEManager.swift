import CoreBluetooth
import Observation

@Observable @MainActor final class BLEManager: NSObject, @preconcurrency CBCentralManagerDelegate {
    private(set) var devices: [CBPeripheral] = []
    private(set) var state: ConnectionState = .disconnected
    private(set) var detail = ""
    private var central: CBCentralManager?
    private var selected: CBPeripheral?
    private var timer: Task<Void, Never>?

    func scan() {
        stop()
        devices.removeAll()
        state = .discovering
        detail = "Looking for camera advertisements…"
        if let central { centralManagerDidUpdateState(central) }
        else { central = CBCentralManager(delegate: self, queue: .main) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if [.unknown, .resetting].contains(central.state) { return }
            stop()
            state = .failed
            detail = central.state == .unauthorized ? "Bluetooth access was denied." : "Bluetooth is unavailable."
            return
        }
        guard state == .discovering else { return }
        central.scanForPeripherals(withServices: nil)
        timeout(seconds: 12)
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "").lowercased()
        guard name.contains("nikon") || name.hasPrefix("z ") || name.hasPrefix("ncz") else { return }
        if !devices.contains(where: { $0.identifier == peripheral.identifier }) { devices.append(peripheral) }
    }
    func connect(_ device: CBPeripheral) {
        stop()
        selected = device
        state = .bleConnecting
        detail = "Waiting for the camera…"
        central?.connect(device)
        timeout(seconds: 15)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard selected === peripheral else { return }
        timer?.cancel()
        state = .bleConnected
        detail = "Bluetooth link open. Use the camera menu to enable Wi-Fi."
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { lost(peripheral) }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { lost(peripheral) }
    private func lost(_ peripheral: CBPeripheral) {
        guard selected === peripheral else { return }
        stop()
        detail = "Bluetooth link closed."
    }
    private func timeout(seconds: Int) {
        timer?.cancel()
        timer = Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            stop()
            detail = "Bluetooth operation ended. Select a discovered camera or scan again."
        }
    }
    func stop() {
        timer?.cancel()
        central?.stopScan()
        if let selected { central?.cancelPeripheralConnection(selected) }
        selected = nil
        state = .disconnected
        detail = ""
    }
}
