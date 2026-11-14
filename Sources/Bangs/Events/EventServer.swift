import Foundation
import Network

/// Минимальный HTTP-сервер на 127.0.0.1: принимает `POST /event` от notch-hook.
/// `GET /health` → 200 — для проверки, что приложение слушает.
final class EventServer {
    static let defaultPort: UInt16 = 47821
    private static let maxRequestSize = 4 << 20

    private let queue = DispatchQueue(label: "dev.bangs.server")
    private let onEvent: (Data) -> Void
    private var listener: NWListener?

    init(onEvent: @escaping (Data) -> Void) {
        self.onEvent = onEvent
    }

    func start(port: UInt16 = EventServer.defaultPort) throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        // Сокет привязан именно к 127.0.0.1, а не ко всем интерфейсам (*:port):
        // из сети к нему нельзя даже подключиться.
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("Bangs: сервер событий остановлен: \(error). Работаем через папку inbox.")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest(buffer) {
                switch (request.method, request.path) {
                case ("POST", "/event"):
                    self.respond(connection, status: "204 No Content")
                    self.onEvent(request.body)
                case ("GET", "/health"):
                    self.respond(connection, status: "200 OK", body: "ok")
                default:
                    self.respond(connection, status: "404 Not Found")
                }
                return
            }
            if isComplete || error != nil || buffer.count > Self.maxRequestSize {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String = "") {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Разбор HTTP/1.1-запроса; nil — запрос ещё не пришёл целиком.
private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(_ data: Data) {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }

        var length = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return nil }

        method = String(requestLine[0])
        path = String(requestLine[1])
        body = data[bodyStart..<(bodyStart + length)]
    }
}
