import SwiftUI

/// Scans for nearby devices. Supported lights can be added; "Show all" exposes the diagnostic scanner.
struct AddDeviceView: View {
    let manager: DeviceManager
    @State private var showAll = false
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    private var listed: [DiscoveredDevice] {
        manager.devices.values
            .filter { showAll ? $0.name != nil : $0.looksLikeGovee }
            .sorted {
                if $0.looksLikeGovee != $1.looksLikeGovee { return $0.looksLikeGovee }
                if $0.looksLikeGovee, $0.hasWeakSignal != $1.hasWeakSignal { return !$0.hasWeakSignal }
                return ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add device").font(.headline)
                    Text(manager.statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if listed.isEmpty {
                ContentUnavailableView("Looking for devices", systemImage: "dot.radiowaves.left.and.right",
                                       description: Text("Keep the light powered and close its phone app."))
            } else {
                List(listed) { device in
                    row(for: device)
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Toggle("Show all Bluetooth devices", isOn: $showAll)
                    .toggleStyle(.checkbox)
                Spacer()
                if showAll {
                    Button(copied ? "Copied" : "Copy report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(manager.report(namedOnly: true), forType: .string)
                        copied = true
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 440, height: 480)
        .onAppear { manager.startScan() }
        .onDisappear { manager.stopScan() }
    }

    @ViewBuilder private func row(for device: DiscoveredDevice) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: device.looksLikeGovee ? "lightbulb.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(device.looksLikeGovee ? .yellow : .secondary)
                Text(device.name ?? "(unnamed)")
                Spacer()
                Text(device.hasWeakSignal ? "weak signal · \(device.rssi) dBm" : "\(device.rssi) dBm")
                    .font(.caption).foregroundStyle(.secondary)
                if manager.saved.contains(where: { $0.id == device.id }) {
                    Text("Added").font(.caption).foregroundStyle(.secondary)
                } else if device.looksLikeGovee {
                    Button("Add") { manager.add(device.id) }
                        .controlSize(.small)
                } else if device.inspection == .connecting || device.inspection == .reading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Inspect") { manager.inspect(device.id) }
                        .controlSize(.small)
                        .disabled(!device.isConnectable)
                }
            }
            if case .failed(let message) = device.inspection {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            ForEach(device.services) { service in
                Text(service.id).font(.caption.monospaced())
                ForEach(service.characteristics) { characteristic in
                    Text("  \(characteristic.id)  \(characteristic.properties.joined(separator: ", "))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
