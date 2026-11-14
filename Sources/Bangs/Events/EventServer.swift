import Foundation
import Network

/// Минимальный HTTP-сервер на 127.0.0.1: принимает `POST /event` от notch-hook.
///
/// Защита:
/// - сокет привязан только к 127.0.0.1 — из сети недоступен;
/// - `POST /event` требует заголовок `X-Bangs-Token` с секретом из файла, доступного только владельцу
///   (см. `AuthToken`) — веб-страницы и другие пользователи Mac не могут подделать события;
/// - некорректные запросы (кривой `Content-Length`, мусор вместо заголовков, слишком большие) → 400.
///
/// `GET /health` → 200 без токена — для проверки, что приложение слушает.
final class EventServer {
    static let defaultPort: UInt16 = 47821
    static let tokenHeader = "x-bangs-token"
    static let maxBodySize = 4 << 20
    private static let maxHeaderSize = 16 * 1024

    private let queue = DispatchQueue(label: "dev.bangs.server")
    private let token: String
    private let onEvent: (Data) -> Void
    private var listener: NWListener?

    init(token: String, onEvent: @escaping (Data) -> Void) {
        self.token = token
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

            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                self.route(request, on: connection)
            case .invalid:
                self.respond(connection, status: "400 Bad Request")
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer: buffer)
                }
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("POST", "/event"):
            guard Self.constantTimeEquals(request.headers[Self.tokenHeader] ?? "", token) else {
                respond(connection, status: "401 Unauthorized")
                return
            }
            respond(connection, status: "204 No Content")
            onEvent(request.body)
        case ("GET", "/health"):
            respond(connection, status: "200 OK", body: "ok")
        default:
            respond(connection, status: "404 Not Found")
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String = "") {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Сравнение без раннего выхода — время не зависит от того, сколько символов совпало.
    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count, !y.isEmpty else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

/// Разбор HTTP/1.1-запроса.
struct HTTPRequest {
    let method: String
    let path: String
    /// Имена заголовков — в нижнем регистре.
    let headers: [String: String]
    let body: Data

    enum ParseResult {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    static func parse(_ data: Data, maxHeaderSize: Int = 16 * 1024, maxBodySize: Int = EventServer.maxBodySize) -> ParseResult {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderSize ? .invalid : .incomplete
        }
        guard headerEnd.lowerBound - data.startIndex <= maxHeaderSize,
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ", omittingEmptySubsequences: true) ?? []
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return .invalid }
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            // Повторный Content-Length с другим значением — классический приём подмены тела.
            if let existing = headers[name], name == "content-length", existing != value { return .invalid }
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil { return .invalid }  // chunked не поддерживаем

        var length = 0
        if let raw = headers["content-length"] {
            // Только цифры: отрицательные, «+5», пробелы внутри и переполнение — ошибка, а не падение.
            guard !raw.isEmpty, raw.count <= 10, raw.allSatisfy(\.isASCII), raw.allSatisfy(\.isNumber),
                  let value = Int(raw), value <= maxBodySize else { return .invalid }
            length = value
        }

        let bodyStart = headerEnd.upperBound
        let available = data.endIndex - bodyStart
        guard available >= length else { return .incomplete }
        return .complete(HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]),
                                     headers: headers, body: Data(data[bodyStart..<(bodyStart + length)])))
    }
}
