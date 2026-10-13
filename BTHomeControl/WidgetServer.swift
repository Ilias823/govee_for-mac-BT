import Foundation
import Network

/// Serves `WidgetBridge` requests from the widget extension. Bound to the loopback interface only.
@MainActor
final class WidgetServer {
    private let manager: DeviceManager
    private var listener: NWListener?

    init(manager: DeviceManager) {
        self.manager = manager
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                     port: NWEndpoint.Port(rawValue: WidgetBridge.port)!)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }
                self.handle(request)
                let body = (try? JSONEncoder().encode(self.manager.widgetDevices)) ?? Data("[]".utf8)
                let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    /// Applies a command from the request line, e.g. `POST /toggle/<id> HTTP/1.1`. Unknown requests are ignored.
    private func handle(_ request: String) {
        let requestLine = request.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
        guard requestLine.count >= 2, requestLine[0] == "POST" else { return }
        let path = requestLine[1].split(separator: "/").map(String.init)
        guard path.count >= 2, let id = UUID(uuidString: path[1]) else { return }
        let values = path.dropFirst(2).compactMap { Int($0) }

        switch (path[0], values.count) {
        case ("toggle", 0):
            manager.togglePower(for: id)
        case ("brightness", 1) where (1...100).contains(values[0]):
            manager.setBrightness(values[0], for: id)
        case ("color", 3) where values.allSatisfy((0...255).contains):
            manager.setColor(red: UInt8(values[0]), green: UInt8(values[1]), blue: UInt8(values[2]), for: id)
        default:
            break
        }
    }
}
