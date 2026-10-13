import CoreBluetooth
import Observation
import WidgetKit

/// Owns the Bluetooth connection to every saved device and the scan used to add new ones.
@MainActor
@Observable
final class DeviceManager: NSObject {
    private(set) var saved: [SavedDevice] = []
    private(set) var connectedIDs: Set<UUID> = []
    private(set) var devices: [UUID: DiscoveredDevice] = [:]
    private(set) var state: CBManagerState = .unknown
    private(set) var isScanning = false

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var pendingServices: [UUID: Int] = [:]
    @ObservationIgnored private var writeCharacteristics: [UUID: CBCharacteristic] = [:]
    @ObservationIgnored private var keepAliveTask: Task<Void, Never>?
    @ObservationIgnored private var colorFlushTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var widgetReloadTask: Task<Void, Never>?

    private static let savedKey = "savedDevices"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.savedKey),
           let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data) {
            saved = decoded
        }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var statusText: String {
        switch state {
        case .poweredOn: isScanning ? "Scanning…" : "Ready"
        case .poweredOff: "Bluetooth is turned off"
        case .unauthorized: "Bluetooth permission denied — allow BT Home Control in System Settings › Privacy & Security › Bluetooth"
        case .unsupported: "This Mac doesn't support Bluetooth LE"
        default: "Starting Bluetooth…"
        }
    }

    // MARK: Saved devices

    func add(_ id: UUID) {
        guard let device = devices[id], !saved.contains(where: { $0.id == id }) else { return }
        saved.append(SavedDevice(id: id, name: device.goveeModel.map { "Govee \($0)" } ?? device.name ?? "Light",
                                 model: device.goveeModel, variant: .likely(forModel: device.goveeModel)))
        persist()
        if let peripheral = peripherals[id], peripheral.state == .disconnected {
            central.connect(peripheral)
        }
    }

    func remove(_ id: UUID) {
        saved.removeAll { $0.id == id }
        persist()
        if let peripheral = peripherals[id] {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.name = trimmed }
    }

    func setVariant(_ variant: GoveeProtocol.Variant, for id: UUID) {
        update(id) { $0.variant = variant }
    }

    func setPower(_ on: Bool, for id: UUID) {
        update(id) { $0.isOn = on }
        send(.power(on), to: id)
    }

    func setBrightness(_ percent: Int, for id: UUID) {
        update(id) { $0.brightness = percent }
        send(.brightness(percent), to: id)
    }

    /// Colour pickers emit a stream of values while dragging, so sends are coalesced.
    func setColor(red: UInt8, green: UInt8, blue: UInt8, for id: UUID) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].red = red
        saved[index].green = green
        saved[index].blue = blue
        guard colorFlushTasks[id] == nil else { return }
        colorFlushTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self else { return }
            self.colorFlushTasks[id] = nil
            guard let device = self.saved.first(where: { $0.id == id }) else { return }
            self.persist()
            self.send(.color(red: device.red, green: device.green, blue: device.blue), to: id)
        }
    }

    private func update(_ id: UUID, _ change: (inout SavedDevice) -> Void) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        change(&saved[index])
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.savedKey)
        }
        reloadWidgets()
    }

    // MARK: Widget

    var widgetDevices: [WidgetBridge.Device] {
        saved.map {
            WidgetBridge.Device(id: $0.id, name: $0.name, isOn: $0.isOn, isConnected: connectedIDs.contains($0.id),
                                brightness: $0.brightness, red: $0.red, green: $0.green, blue: $0.blue)
        }
    }

    func togglePower(for id: UUID) {
        guard let device = saved.first(where: { $0.id == id }) else { return }
        setPower(!device.isOn, for: id)
    }

    private func reloadWidgets() {
        widgetReloadTask?.cancel()
        widgetReloadTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.widgetKind)
        }
    }

    /// A pending connect has no timeout, so this also covers devices that come into range later.
    private func connectSaved() {
        for peripheral in central.retrievePeripherals(withIdentifiers: saved.map(\.id)) {
            peripherals[peripheral.identifier] = peripheral
            if peripheral.state == .disconnected {
                central.connect(peripheral)
            }
        }
    }

    private func send(_ command: GoveeProtocol.Command, to id: UUID) {
        guard let peripheral = peripherals[id], let characteristic = writeCharacteristics[id] else { return }
        let variant = saved.first { $0.id == id }?.variant ?? .classic
        let type: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(GoveeProtocol.frame(for: command, variant: variant), for: characteristic, type: type)
    }

    /// Govee devices drop the connection after a few seconds without traffic.
    private func updateKeepAlive() {
        if connectedIDs.isEmpty {
            keepAliveTask?.cancel()
            keepAliveTask = nil
        } else if keepAliveTask == nil {
            keepAliveTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, !Task.isCancelled else { return }
                    for id in self.connectedIDs {
                        self.send(.keepAlive, to: id)
                    }
                }
            }
        }
    }

    // MARK: Scanning

    func startScan() {
        wantsScan = true
        guard state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil)
        isScanning = true
    }

    func stopScan() {
        wantsScan = false
        central.stopScan()
        isScanning = false
    }

    /// Diagnostic: connects, reads the device's services and characteristics, then disconnects.
    func inspect(_ id: UUID) {
        guard let peripheral = peripherals[id], devices[id]?.inspection != .connecting,
              devices[id]?.inspection != .reading else { return }
        devices[id]?.inspection = .connecting
        devices[id]?.services = []
        central.connect(peripheral)
        // CoreBluetooth never gives up on a connection attempt by itself.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, let inspection = self.devices[id]?.inspection,
                  inspection == .connecting || inspection == .reading else { return }
            self.devices[id]?.inspection = .failed("Timed out — too far away, or connected to another app")
            if !self.saved.contains(where: { $0.id == id }) {
                self.central.cancelPeripheralConnection(peripheral)
            }
        }
    }

    func report(namedOnly: Bool) -> String {
        let listed = devices.values
            .filter { !namedOnly || $0.name != nil }
            .sorted { $0.rssi > $1.rssi }
        var lines = ["BT Home Control scan report — \(listed.count) devices"]
        for device in listed {
            lines.append("")
            lines.append("\(device.name ?? "(unnamed)")  RSSI \(device.rssi)  connectable: \(device.isConnectable)")
            if !device.advertisedServices.isEmpty {
                lines.append("  advertised: \(device.advertisedServices.joined(separator: ", "))")
            }
            if let data = device.manufacturerData {
                lines.append("  manufacturer data: \(data.map { String(format: "%02x", $0) }.joined())")
            }
            for service in device.services {
                lines.append("  service \(service.id)")
                for characteristic in service.characteristics {
                    lines.append("    \(characteristic.id)  [\(characteristic.properties.joined(separator: ", "))]")
                }
            }
            if case .failed(let message) = device.inspection {
                lines.append("  inspect failed: \(message)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension DeviceManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if state == .poweredOn {
            connectSaved()
            if wantsScan { startScan() }
        } else {
            isScanning = false
            connectedIDs = []
            writeCharacteristics = [:]
            updateKeepAlive()
            reloadWidgets()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        peripherals[id] = peripheral
        var device = devices[id] ?? DiscoveredDevice(id: id, rssi: RSSI.intValue)
        device.name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? device.name
        device.rssi = RSSI.intValue
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            device.advertisedServices = uuids.map(\.uuidString)
        }
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            device.manufacturerData = data
        }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool {
            device.isConnectable = connectable
        }
        devices[id] = device
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if devices[peripheral.identifier]?.inspection == .connecting {
            devices[peripheral.identifier]?.inspection = .reading
        }
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        devices[peripheral.identifier]?.inspection = .failed(error?.localizedDescription ?? "Could not connect")
        reconnectIfSaved(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        pendingServices[id] = nil
        writeCharacteristics[id] = nil
        connectedIDs.remove(id)
        updateKeepAlive()
        reloadWidgets()
        if let inspection = devices[id]?.inspection, inspection == .connecting || inspection == .reading {
            devices[id]?.inspection = .failed(error?.localizedDescription ?? "Disconnected")
        }
        reconnectIfSaved(peripheral)
    }

    private func reconnectIfSaved(_ peripheral: CBPeripheral) {
        if saved.contains(where: { $0.id == peripheral.identifier }) {
            central.connect(peripheral)
        }
    }
}

extension DeviceManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let id = peripheral.identifier
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            finishDiscovery(of: peripheral, failure: error?.localizedDescription ?? "No services found")
            return
        }
        pendingServices[id] = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let id = peripheral.identifier
        let characteristics = (service.characteristics ?? []).map {
            DiscoveredCharacteristic(id: $0.uuid.uuidString, properties: $0.properties.labels)
        }
        devices[id]?.services.append(DiscoveredService(id: service.uuid.uuidString, characteristics: characteristics))
        if let write = service.characteristics?.first(where: { $0.uuid == GoveeProtocol.writeCharacteristic }) {
            writeCharacteristics[id] = write
        }

        let remaining = (pendingServices[id] ?? 1) - 1
        pendingServices[id] = remaining
        if remaining <= 0 {
            finishDiscovery(of: peripheral, failure: nil)
        }
    }

    private func finishDiscovery(of peripheral: CBPeripheral, failure: String?) {
        let id = peripheral.identifier
        pendingServices[id] = nil
        if devices[id]?.inspection == .reading {
            devices[id]?.inspection = failure.map { .failed($0) } ?? .done
        }
        if failure == nil, writeCharacteristics[id] != nil, saved.contains(where: { $0.id == id }) {
            connectedIDs.insert(id)
            updateKeepAlive()
            reloadWidgets()
        } else {
            writeCharacteristics[id] = nil
            central.cancelPeripheralConnection(peripheral)
        }
    }
}

private extension CBCharacteristicProperties {
    var labels: [String] {
        var result: [String] = []
        if contains(.read) { result.append("read") }
        if contains(.write) { result.append("write") }
        if contains(.writeWithoutResponse) { result.append("writeNoResponse") }
        if contains(.notify) { result.append("notify") }
        if contains(.indicate) { result.append("indicate") }
        return result
    }
}
