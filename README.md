# BT Home Control

A small macOS menu bar app that controls Govee Bluetooth lights directly from a Mac, including older
Bluetooth-only models that Apple's Home app doesn't recognise. It lives in the menu bar and has a desktop widget.

## Features

- Finds nearby Govee lights over Bluetooth LE and remembers the ones you add
- Power, brightness and colour per light, with automatic reconnect
- Desktop widget (small and medium) with power, brightness presets and colour presets
- Optional "Open at login"

## Supported devices

| Model | Status |
| --- | --- |
| H613E | Confirmed: power, brightness, colour |
| Other Govee BLE lights | Untested. Right-click a device card and try another "Colour format" if colours don't respond |

## Building

Requires macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
./install.sh
```

`install.sh` builds a release copy, installs it into `/Applications` and launches it. The app has no Dock
icon; look for the lightbulb in the menu bar.

The project is set up for ad-hoc signing ("Sign to Run Locally"), so no Apple developer account is needed.

## How it works

- `BTHomeControl/Bluetooth` — CoreBluetooth connection handling and the Govee BLE protocol
  (20-byte frames ending in an XOR checksum).
- `BTHomeControl/Views` — the SwiftUI interface.
- `BTHomeControlWidget` — the WidgetKit extension.
- `Shared/WidgetBridge.swift` — the contract between the two. Widgets can't use Bluetooth, so the widget
  sends commands to the running app over a loopback-only HTTP endpoint. The app must be running for the
  widget to work.

## Notes

- Close the Govee phone app before connecting; a light accepts one Bluetooth connection at a time.
- The app shows the last state it sent, not the light's real state.
- Not affiliated with Govee.

## License

[MIT](LICENSE)
