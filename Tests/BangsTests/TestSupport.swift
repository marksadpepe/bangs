import Foundation
@testable import Bangs

/// Модель с настройками в памяти (без UserDefaults).
func makeModel(lang: Lang = .en, jumpOnClick: Bool = false) -> AppModel {
    let settings = AppSettings(defaults: nil)
    settings.lang = lang
    settings.jumpOnClick = jumpOnClick
    return AppModel(settings: settings, geometry: .preview)
}

/// Событие хука в конверте notch-hook.
func hookEvent(_ name: String, session: String = "s1", tty: String? = "/dev/ttys001",
               pid: Int32? = nil, at date: Date? = nil, cwd: String = "/tmp/proj",
               _ fields: [String: Any] = [:]) -> HookEvent {
    var event: [String: Any] = ["session_id": session, "hook_event_name": name, "cwd": cwd]
    event.merge(fields) { _, new in new }
    var envelope: [String: Any] = ["event": event, "project_dir": cwd]
    if let tty { envelope["tty"] = tty }
    if let pid { envelope["claude_pid"] = pid }
    if let date { envelope["ts"] = date.timeIntervalSince1970 }
    let data = try! JSONSerialization.data(withJSONObject: envelope)
    return HookEvent(data: data)!
}

func makeChat(_ id: String, _ status: ChatStatus, title: String? = nil, cwd: String = "/tmp/proj",
              since: Date = Date()) -> Chat {
    Chat(id: id, title: title ?? "Chat \(id)", cwd: cwd, status: status, statusSince: since)
}

/// Временная папка, удаляется после теста.
func withTempDir<T>(_ body: (URL) throws -> T) rethrows -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bangs-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}

func withTempDir<T>(_ body: (URL) async throws -> T) async rethrows -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bangs-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try await body(url)
}

func writeJSON(_ object: Any, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: object).write(to: url)
}

/// Корень репозитория (для запуска скриптов).
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

struct ProcessResult {
    let status: Int32
    let output: String
}

/// Запуск процесса с заданным окружением (без унаследованного — чтобы тест не зависел от машины).
func runProcess(_ executable: String, _ arguments: [String] = [], environment: [String: String],
                stdin: Data? = nil) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    let out = Pipe()
    process.standardOutput = out
    process.standardError = out
    let input = Pipe()
    process.standardInput = input
    try process.run()
    if let stdin { input.fileHandleForWriting.write(stdin) }
    try input.fileHandleForWriting.close()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
}

/// Потокобезопасный сборщик данных из колбэков.
final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []

    func append(_ data: Data) { lock.withLock { items.append(data) } }
    var all: [Data] { lock.withLock { items } }

    /// Ждёт, пока придёт хотя бы `count` элементов (до 3 с).
    func wait(for count: Int = 1) async throws -> [Data] {
        for _ in 0..<60 where all.count < count {
            try await Task.sleep(for: .milliseconds(50))
        }
        return all
    }
}

/// Свободный порт для тестового сервера.
func randomPort() -> UInt16 { UInt16.random(in: 49_200...60_000) }

/// PATH для скриптов: системные утилиты (в macOS 15+ там есть jq) и Homebrew — на CI-раннерах jq может быть оттуда.
let testPath = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

/// Токен тестового сервера.
let testToken = String(repeating: "ab", count: 32)

/// Сырой HTTP-запрос через nc (URLSession не даёт отправить кривые заголовки). Возвращает ответ сервера.
func rawRequest(port: UInt16, _ raw: String) throws -> String {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("raw-\(UUID().uuidString)")
    try Data(raw.utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    return try runProcess("/bin/sh", ["-c", "/usr/bin/nc -w 2 127.0.0.1 \(port) < '\(file.path)'"],
                          environment: ["PATH": testPath]).output
}
