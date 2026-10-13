import Foundation

/// A device the user has added. `id` is the CoreBluetooth peripheral identifier, which is stable per Mac.
struct SavedDevice: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var model: String?
    var variant: GoveeProtocol.Variant
    // Last values sent from this app; the device itself is not queried.
    var isOn = true
    var brightness = 100
    var red: UInt8 = 255
    var green: UInt8 = 255
    var blue: UInt8 = 255
}

struct DiscoveredCharacteristic: Identifiable, Hashable {
    let id: String
    let properties: [String]
}

struct DiscoveredService: Identifiable, Hashable {
    let id: String
    var characteristics: [DiscoveredCharacteristic]
}

struct DiscoveredDevice: Identifiable {
    enum Inspection: Equatable {
        case idle, connecting, reading, done
        case failed(String)
    }

    let id: UUID
    var name: String?
    var rssi: Int
    var advertisedServices: [String] = []
    var manufacturerData: Data?
    var isConnectable = false
    var inspection: Inspection = .idle
    var services: [DiscoveredService] = []

    /// Name prefixes Govee firmware is known to advertise under.
    var looksLikeGovee: Bool {
        guard let name else { return false }
        return ["Govee_", "ihoment_", "GBK_", "Minger_"].contains { name.hasPrefix($0) }
    }

    /// Model number embedded in the advertised name, e.g. "H613E" from "GBK_H613E_534B".
    var goveeModel: String? {
        guard looksLikeGovee, let parts = name?.split(separator: "_"), parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    var hasWeakSignal: Bool { rssi < -85 }
}
