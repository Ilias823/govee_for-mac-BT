import Foundation

/// Contract between the app and its widget. The widget can't use Bluetooth, and without a developer
/// team the two can't share an app group, so the widget talks to the running app over a
/// loopback-only HTTP endpoint: `GET /state`, `POST /toggle/<id>`, `POST /brightness/<id>/<percent>`,
/// `POST /color/<id>/<r>/<g>/<b>`. Every request answers with the current device list as JSON.
enum WidgetBridge {
    static let port: UInt16 = 47816
    static let widgetKind = "BTHomeControlWidget"

    struct Device: Codable, Identifiable, Hashable {
        let id: UUID
        var name: String
        var isOn: Bool
        var isConnected: Bool
        var brightness: Int
        var red: UInt8
        var green: UInt8
        var blue: UInt8
    }
}
