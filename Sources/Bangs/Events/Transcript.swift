import Foundation

/// Чтение транскрипта Claude Code (JSONL): первое сообщение пользователя и последний ответ Claude.
enum Transcript {
    private static let chunk = 512 * 1024

    /// Первое настоящее сообщение пользователя (без служебных вставок и результатов инструментов).
    static func firstUserPrompt(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: chunk) else { return nil }
        for line in lines(data) {
            if let text = userText(line) { return text }
        }
        return nil
    }

    /// Текст последнего ответа Claude.
    static func lastAssistantText(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(chunk) ? size - UInt64(chunk) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        for line in lines(data).reversed() {
            if let text = assistantText(line) { return text }
        }
        return nil
    }

    // MARK: - Разбор строк

    private static func lines(_ data: Data) -> [[String: Any]] {
        data.split(separator: UInt8(ascii: "\n")).compactMap {
            try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
        }
    }

    private static func userText(_ entry: [String: Any]) -> String? {
        guard entry["type"] as? String == "user", entry["isMeta"] as? Bool != true,
              let message = entry["message"] as? [String: Any] else { return nil }
        var text: String?
        if let s = message["content"] as? String {
            text = s
        } else if let parts = message["content"] as? [[String: Any]] {
            if parts.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
            text = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.first
        }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
              !t.hasPrefix("<"), !t.hasPrefix("Caveat:") else { return nil }
        return t
    }

    private static func assistantText(_ entry: [String: Any]) -> String? {
        guard entry["type"] as? String == "assistant",
              let message = entry["message"] as? [String: Any],
              let parts = message["content"] as? [[String: Any]] else { return nil }
        let text = parts
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Оформление

    /// Название чата: одна строка, не длиннее `limit` символов.
    static func title(from text: String, limit: Int = 40) -> String {
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.count > limit ? String(oneLine.prefix(limit - 1)) + "…" : oneLine
    }

    /// Последнее сообщение для экрана чата: убираем markdown-шум и обрезаем.
    static func excerpt(_ text: String, limit: Int = 320) -> String {
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return cleaned.count > limit ? "…" + String(cleaned.suffix(limit - 1)) : cleaned
    }
}
