import CoreBluetooth

/// Govee's reverse-engineered BLE control protocol: 20-byte frames, zero-padded, ending in an XOR checksum.
enum GoveeProtocol {
    static var writeCharacteristic: CBUUID { CBUUID(string: "00010203-0405-0607-0809-0A0B0C0D2B11") }

    /// Models disagree on the colour payload and the brightness scale.
    enum Variant: String, CaseIterable, Identifiable, Codable {
        case classic = "Classic"
        case rgb = "RGB"
        case segmented = "RGBIC"
        var id: Self { self }

        /// Best guess from the model number until each model is confirmed on real hardware.
        static func likely(forModel model: String?) -> Variant {
            model?.hasPrefix("H613") == true ? .rgb : .segmented
        }
    }

    enum Command {
        case power(Bool)
        /// 1–100
        case brightness(Int)
        case color(red: UInt8, green: UInt8, blue: UInt8)
        case keepAlive
    }

    static func frame(for command: Command, variant: Variant) -> Data {
        switch command {
        case .power(let on):
            return frame([0x33, 0x01, on ? 0x01 : 0x00])
        case .brightness(let percent):
            let clamped = min(max(percent, 1), 100)
            // Only the oldest models take a 0–254 scale; the rest take a percentage.
            let value = variant == .classic ? clamped * 254 / 100 : clamped
            return frame([0x33, 0x04, UInt8(value)])
        case .color(let red, let green, let blue):
            switch variant {
            case .classic:
                return frame([0x33, 0x05, 0x02, red, green, blue])
            case .rgb:
                return frame([0x33, 0x05, 0x0D, red, green, blue])
            case .segmented:
                return frame([0x33, 0x05, 0x15, 0x01, red, green, blue, 0, 0, 0, 0, 0, 0xFF, 0x7F])
            }
        case .keepAlive:
            return frame([0xAA, 0x01])
        }
    }

    private static func frame(_ payload: [UInt8]) -> Data {
        var bytes = payload + [UInt8](repeating: 0, count: 19 - payload.count)
        bytes.append(bytes.reduce(0, ^))
        return Data(bytes)
    }
}
