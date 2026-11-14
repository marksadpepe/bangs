import Foundation

/// Статус чата Claude Code (см. SPEC.md → «Статусы чата»).
enum ChatStatus: String, Codable, Sendable {
    case working   // после UserPromptSubmit / SessionStart
    case done      // после Stop
    case waiting   // после Notification: запрос разрешения или ввода
    case waitSeen  // открыл ожидающий чат и вернулся, но не ответил
    case denied    // ответил «Нет» из панели
    case seen      // просмотрен

    var isWaiting: Bool { self == .waiting || self == .waitSeen || self == .denied }

    /// Порядок в списке: сначала то, что требует внимания.
    var rank: Int {
        switch self {
        case .done: 0
        case .waiting: 1
        case .waitSeen, .denied: 2
        case .working: 3
        case .seen: 4
        }
    }
}

enum RequestKind: String, Codable, Sendable {
    case permission  // хочет выполнить команду
    case question    // задаёт вопрос
}

/// То, чего ждёт чат: показывается на экране ожидающего чата.
struct PendingRequest: Codable, Equatable, Sendable {
    var kind: RequestKind
    var context: String?   // последнее сообщение Claude
    var command: String?
    var question: String?
    var options: [String] = []
    /// Инструмент, на который просят разрешение (Bash, Edit, WebFetch…).
    var toolName: String? = nil
    /// Claude Code предлагает вариант «больше не спрашивать».
    var allowAlways: Bool = false
}

/// Чат = одна сессия Claude Code (`session_id`).
struct Chat: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// Первое сообщение пользователя. Пустое — чат ещё не начат и в панели не показывается.
    var title: String
    /// Папка проекта — по ней чаты группируются в островки.
    var cwd: String
    var status: ChatStatus
    var statusSince: Date
    var tty: String? = nil
    var configDir: String? = nil
    var transcriptPath: String? = nil
    var request: PendingRequest? = nil
    var claudePid: Int32? = nil
    /// Сессия завершилась (SessionEnd или процесс claude пропал) — чат удаляется через 10 минут.
    var endedAt: Date? = nil

    var isVisible: Bool { !title.isEmpty }

    mutating func setStatus(_ new: ChatStatus, at date: Date = Date()) {
        guard status != new else { return }
        let old = status
        status = new
        // Внутри «ожидания» время не сбрасываем: «ждёт N мин» считается от первого запроса.
        if !(old.isWaiting && new.isWaiting) { statusSince = date }
    }
}

/// Островок в панели = проект, чаты сгруппированы по `cwd`.
struct Project: Identifiable {
    let cwd: String
    var chats: [Chat]

    var id: String { cwd }
    var name: String { (cwd as NSString).lastPathComponent }
    var displayPath: String { Self.abbreviate(cwd) }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

struct Account: Equatable {
    var name: String
    var email: String?
    var fullName: String? = nil

    /// Подсказка в шапке: «Полное имя · почта».
    var tooltip: String { [fullName ?? name, email].compactMap { $0 }.joined(separator: " · ") }
}
