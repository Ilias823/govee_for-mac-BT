import SwiftUI

@main
struct BTHomeControlApp: App {
    @State private var manager: DeviceManager
    private let widgetServer: WidgetServer

    init() {
        // New menu bar items go to the far left, where a crowded bar hides them behind the notch.
        // Seed a position (points from the right edge) among the visible items; the user can still ⌘-drag it.
        let positionKey = "NSStatusItem Preferred Position Item-0"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(300, forKey: positionKey)
        }
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
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra("BT Home Control", systemImage: "lightbulb.fill") {
            DevicesView(manager: manager, compact: true)
                .frame(width: 360, height: 460)
        }
        .menuBarExtraStyle(.window)
    }
}
