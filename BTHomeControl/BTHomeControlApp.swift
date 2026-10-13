import SwiftUI

@main
struct BTHomeControlApp: App {
    @State private var manager: DeviceManager
    private let widgetServer: WidgetServer

    init() {
        let manager = DeviceManager()
        _manager = State(initialValue: manager)
        widgetServer = WidgetServer(manager: manager)
        widgetServer.start()
    }

    var body: some Scene {
        Window("BT Home Control", id: "main") {
            DevicesView(manager: manager)
                .frame(minWidth: 380, minHeight: 420)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("BT Home Control", systemImage: "lightbulb.fill") {
            DevicesView(manager: manager, compact: true)
                .frame(width: 360, height: 460)
        }
        .menuBarExtraStyle(.window)
    }
}
