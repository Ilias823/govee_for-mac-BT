import ServiceManagement
import SwiftUI

/// The main screen: one card per saved device. `compact` is the menu bar popover variant.
struct DevicesView: View {
    let manager: DeviceManager
    var compact = false
    @State private var isAdding = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.saved.isEmpty {
                ContentUnavailableView {
                    Label("No devices yet", systemImage: "lightbulb")
                } description: {
                    Text(compact ? "Open BT Home Control to add a device." : "Add a nearby Bluetooth light to get started.")
                } actions: {
                    if !compact { Button("Add device") { isAdding = true } }
                }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(manager.saved) { device in
                            DeviceCard(device: device, manager: manager)
                        }
                    }
                    .padding(12)
                }
            }
            if compact {
                Divider()
                HStack {
                    Button("Open BT Home Control") {
                        openWindow(id: "main")
                        NSApplication.shared.activate()
                    }
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
                .padding(12)
            }
        }
        .sheet(isPresented: $isAdding) {
            AddDeviceView(manager: manager)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("My devices").font(.headline)
                if manager.state != .poweredOn {
                    Text(manager.statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !compact {
                Button {
                    isAdding = true
                } label: {
                    Label("Add device", systemImage: "plus")
                }
                Menu {
                    Toggle("Open at login", isOn: Binding { opensAtLogin } set: { setOpensAtLogin($0) })
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(12)
    }
}

extension DevicesView {
    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct DeviceCard: View {
    let device: SavedDevice
    let manager: DeviceManager
    @State private var brightness: Double
    @State private var isRenaming = false
    @State private var newName = ""

    private let swatches: [(Color, UInt8, UInt8, UInt8)] = [
        (.red, 255, 0, 0), (.orange, 255, 140, 20), (.green, 0, 255, 0),
        (.blue, 0, 0, 255), (.purple, 160, 0, 255), (.white, 255, 255, 255),
    ]

    init(device: SavedDevice, manager: DeviceManager) {
        self.device = device
        self.manager = manager
        _brightness = State(initialValue: Double(device.brightness))
    }

    private var isConnected: Bool { manager.connectedIDs.contains(device.id) }

    private var color: Binding<Color> {
        Binding {
            Color(.sRGB, red: Double(device.red) / 255, green: Double(device.green) / 255, blue: Double(device.blue) / 255)
        } set: { newValue in
            guard let rgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            manager.setColor(red: UInt8(rgb.redComponent * 255), green: UInt8(rgb.greenComponent * 255),
                             blue: UInt8(rgb.blueComponent * 255), for: device.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: device.isOn && isConnected ? "lightbulb.fill" : "lightbulb")
                    .font(.title2)
                    .foregroundStyle(device.isOn && isConnected ? color.wrappedValue : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name).fontWeight(.semibold)
                    Text(isConnected ? "Connected" : "Searching…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Power", isOn: Binding { device.isOn } set: { manager.setPower($0, for: device.id) })
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Slider(value: $brightness, in: 1...100) {
                Text("Brightness")
            } minimumValueLabel: {
                Image(systemName: "sun.min")
            } maximumValueLabel: {
                Image(systemName: "sun.max")
            } onEditingChanged: { editing in
                if !editing { manager.setBrightness(Int(brightness), for: device.id) }
            }
            .labelsHidden()
            HStack(spacing: 8) {
                ForEach(swatches.indices, id: \.self) { index in
                    let swatch = swatches[index]
                    Button {
                        manager.setColor(red: swatch.1, green: swatch.2, blue: swatch.3, for: device.id)
                    } label: {
                        Circle().fill(swatch.0).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.0.description)
                }
                Spacer()
                ColorPicker("Custom colour", selection: color, supportsOpacity: false)
                    .labelsHidden()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .disabled(!isConnected)
        .onChange(of: device.brightness) { _, newValue in brightness = Double(newValue) }
        .contextMenu {
            Button("Rename…") {
                newName = device.name
                isRenaming = true
            }
            Picker("Colour format", selection: Binding { device.variant } set: { manager.setVariant($0, for: device.id) }) {
                ForEach(GoveeProtocol.Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Button("Remove", role: .destructive) { manager.remove(device.id) }
        }
        .alert("Rename device", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") { manager.rename(device.id, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
