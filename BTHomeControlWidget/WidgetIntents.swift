import AppIntents
import Foundation

enum WidgetClient {
    static func state() async -> [WidgetBridge.Device]? {
        await request("state", method: "GET")
    }

    @discardableResult
    static func send(_ path: String) async -> [WidgetBridge.Device]? {
        await request(path, method: "POST")
    }

    private static func request(_ path: String, method: String) async -> [WidgetBridge.Device]? {
        guard let url = URL(string: "http://127.0.0.1:\(WidgetBridge.port)/\(path)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = method
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? JSONDecoder().decode([WidgetBridge.Device].self, from: data)
    }
}

struct TogglePowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle light"
    static let isDiscoverable = false

    @Parameter(title: "Device") var deviceID: String

    init() {}
    init(device: WidgetBridge.Device) { deviceID = device.id.uuidString }

    func perform() async throws -> some IntentResult {
        await WidgetClient.send("toggle/\(deviceID)")
        return .result()
    }
}

struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set brightness"
    static let isDiscoverable = false

    @Parameter(title: "Device") var deviceID: String
    @Parameter(title: "Brightness") var percent: Int

    init() {}
    init(device: WidgetBridge.Device, percent: Int) {
        deviceID = device.id.uuidString
        self.percent = percent
    }

    func perform() async throws -> some IntentResult {
        await WidgetClient.send("brightness/\(deviceID)/\(percent)")
        return .result()
    }
}

struct SetColorIntent: AppIntent {
    static let title: LocalizedStringResource = "Set colour"
    static let isDiscoverable = false

    @Parameter(title: "Device") var deviceID: String
    @Parameter(title: "Red") var red: Int
    @Parameter(title: "Green") var green: Int
    @Parameter(title: "Blue") var blue: Int

    init() {}
    init(device: WidgetBridge.Device, red: Int, green: Int, blue: Int) {
        deviceID = device.id.uuidString
        self.red = red
        self.green = green
        self.blue = blue
    }

    func perform() async throws -> some IntentResult {
        await WidgetClient.send("color/\(deviceID)/\(red)/\(green)/\(blue)")
        return .result()
    }
}
