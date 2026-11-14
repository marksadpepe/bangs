import Foundation
import Security

/// Секрет, которым notch-hook подтверждает, что событие пришло от него.
/// Лежит в `~/Library/Application Support/Bangs/token` с правами 600 (папка — 700):
/// прочитать его могут только процессы вашего пользователя, но не веб-страницы и не другие пользователи Mac.
enum AuthToken {
    static var defaultURL: URL { StateStore.directory.appendingPathComponent("token") }

    /// Читает существующий токен или создаёт новый. Токен постоянный: хуки, запущенные до перезапуска
    /// приложения, продолжают работать.
    static func loadOrCreate(at url: URL = defaultURL) throws -> String {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           isValid(existing) {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return token
    }

    static func isValid(_ token: String) -> Bool {
        token.count == 64 && token.allSatisfy { $0.isHexDigit && $0.isASCII }
    }
}
