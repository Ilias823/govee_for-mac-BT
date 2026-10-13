import SwiftUI
import WidgetKit

struct DevicesEntry: TimelineEntry {
    let date: Date
    /// `nil` when the app isn't running to answer.
    let devices: [WidgetBridge.Device]?

    static let preview = DevicesEntry(date: .now, devices: [
        WidgetBridge.Device(id: UUID(), name: "Desk strip", isOn: true, isConnected: true,
                            brightness: 80, red: 255, green: 140, blue: 20),
        WidgetBridge.Device(id: UUID(), name: "Shelf strip", isOn: false, isConnected: true,
                            brightness: 50, red: 0, green: 0, blue: 255),
    ])
}

struct DevicesProvider: TimelineProvider {
    func placeholder(in context: Context) -> DevicesEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DevicesEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
        } else {
            Task { completion(DevicesEntry(date: .now, devices: await WidgetClient.state())) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DevicesEntry>) -> Void) {
        Task {
            let entry = DevicesEntry(date: .now, devices: await WidgetClient.state())
            // The app reloads the widget whenever something changes; this is only a fallback.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct DevicesWidgetView: View {
    let entry: DevicesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let devices = entry.devices {
                if devices.isEmpty {
                    message("No devices", detail: "Add a light in BT Home Control.")
                } else if family == .systemSmall {
                    VStack(spacing: 8) {
                        ForEach(devices.prefix(2)) { DeviceTile(device: $0) }
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(devices.prefix(2)) { DeviceRow(device: $0) }
                    }
                }
            } else {
                message("App not running", detail: "Click to open BT Home Control.")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "lightbulb.slash").font(.title2).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

private extension WidgetBridge.Device {
    var color: Color { Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
    var isLit: Bool { isOn && isConnected }
    var status: String { !isConnected ? "Offline" : isOn ? "On · \(brightness)%" : "Off" }
}

/// Icon, name and status. Shared by both layouts.
private struct DeviceLabel: View {
    let device: WidgetBridge.Device

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.isLit ? "lightbulb.fill" : "lightbulb")
                .font(.title3)
                .foregroundStyle(device.isLit ? device.color : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(device.status).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Small widget: the whole tile toggles the light.
private struct DeviceTile: View {
    let device: WidgetBridge.Device

    var body: some View {
        Button(intent: TogglePowerIntent(device: device)) {
            DeviceLabel(device: device)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(device.isLit ? AnyShapeStyle(device.color.opacity(0.25)) : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(device.isConnected ? 1 : 0.5)
    }
}

/// Medium widget: power switch plus brightness and colour presets.
private struct DeviceRow: View {
    let device: WidgetBridge.Device

    private let brightnessPresets = [25, 50, 100]
    private let colorPresets: [(Color, Int, Int, Int)] = [
        (.red, 255, 0, 0), (.orange, 255, 140, 20), (.blue, 0, 0, 255), (.purple, 160, 0, 255), (.white, 255, 255, 255),
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                DeviceLabel(device: device)
                Toggle("Power", isOn: device.isOn, intent: TogglePowerIntent(device: device))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            HStack(spacing: 6) {
                ForEach(brightnessPresets, id: \.self) { percent in
                    Button("\(percent)%", intent: SetBrightnessIntent(device: device, percent: percent))
                        .font(.caption2)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                ForEach(colorPresets.indices, id: \.self) { index in
                    let preset = colorPresets[index]
                    Button(intent: SetColorIntent(device: device, red: preset.1, green: preset.2, blue: preset.3)) {
                        Circle().fill(preset.0).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .opacity(device.isConnected ? 1 : 0.5)
    }
}

struct BTHomeControlWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.widgetKind, provider: DevicesProvider()) { entry in
            DevicesWidgetView(entry: entry)
        }
        .configurationDisplayName("BT Home Control")
        .description("Switch your lights and pick brightness and colour presets.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BTHomeControlWidgetBundle: WidgetBundle {
    var body: some Widget {
        BTHomeControlWidget()
    }
}
