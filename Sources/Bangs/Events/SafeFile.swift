import Darwin
import Foundation

/// Проверки путей, пришедших в событиях: читаем только обычные файлы (не каналы, не устройства,
/// не сокеты — на них чтение может зависнуть навсегда).
enum SafeFile {
    static let maxPathLength = 1024

    /// Обычный файл (симлинки разрешаются: симлинк на FIFO тоже отклоняется).
    static func isRegularFile(_ path: String, maxSize: Int64? = nil) -> Bool {
        guard isPlausiblePath(path) else { return false }
        var st = stat()
        guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return false }
        if let maxSize, st.st_size > maxSize { return false }
        return true
    }

    static func isDirectory(_ path: String) -> Bool {
        guard isPlausiblePath(path) else { return false }
        var st = stat()
        return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// `/dev/ttys003` и подобные.
    static func isValidTTY(_ tty: String) -> Bool {
        tty.range(of: #"^/dev/tty[a-z]*[0-9]+$"#, options: .regularExpression) != nil
    }

    /// Идентификатор сессии Claude Code (UUID) — только безопасные символы.
    static func isValidSessionId(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$"#, options: .regularExpression) != nil
    }

    /// Абсолютный путь разумной длины, без `..` и управляющих символов.
    static func isPlausiblePath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count <= maxPathLength
            && !path.split(separator: "/").contains("..")
            && !path.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }
}
