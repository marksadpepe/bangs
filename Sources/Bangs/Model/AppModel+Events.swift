import Darwin
import Foundation

/// Переходы статусов по событиям хуков (SPEC.md → «Модель данных»).
extension AppModel {
    /// Типы Notification, которые означают «ждёт тебя». `idle_prompt` (напоминание о простое) — нет.
    static let waitingNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]
    /// Через сколько удалять завершённые сессии.
    static let endedChatLifetime: TimeInterval = 10 * 60

    func apply(_ e: HookEvent) {
        let existing = chats.firstIndex { $0.id == e.sessionId }
        var c = existing.map { chats[$0] } ?? Chat(
            id: e.sessionId, title: "", cwd: e.projectDir ?? e.cwd ?? NSHomeDirectory(),
            status: .seen, statusSince: e.date)

        if let tty = e.tty { c.tty = tty }
        if let dir = e.configDir {
            c.configDir = dir
            if dir != accountConfigDir {
                accountConfigDir = dir
                account = AccountReader.read(configDir: dir) ?? account
            }
        }
        if let path = e.transcriptPath { c.transcriptPath = path }
        if let pid = e.claudePid { c.claudePid = pid }
        if c.title.isEmpty, let t = e.string("session_title") { c.title = Transcript.title(from: t) }
        // Сессия возобновлена или была запущена до Bangs — название берём из транскрипта.
        if c.title.isEmpty, existing == nil || e.name == "SessionStart",
           let path = c.transcriptPath, let first = Transcript.firstUserPrompt(path: path) {
            c.title = Transcript.title(from: first)
        }
        // Первое событие посреди работы (PostToolUse и т.п.) — значит, Claude сейчас работает.
        if existing == nil, e.name.hasPrefix("PostToolUse") || e.name == "PreToolUse" {
            c.setStatus(.working, at: e.date)
        }

        switch e.name {
        case "SessionStart":
            c.endedAt = nil
            // В этой вкладке терминала запустили новую сессию — старые там больше не живут.
            if let tty = c.tty {
                for i in chats.indices where chats[i].id != c.id && chats[i].tty == tty && chats[i].endedAt == nil {
                    end(&chats[i], at: e.date)
                }
            }

        case "UserPromptSubmit":
            c.endedAt = nil
            if c.title.isEmpty, let prompt = e.string("prompt") { c.title = Transcript.title(from: prompt) }
            c.request = nil
            c.setStatus(.working, at: e.date)

        case "PreToolUse" where e.toolName == "AskUserQuestion":
            c.request = questionRequest(e, transcript: c.transcriptPath)
            c.setStatus(.waiting, at: e.date)

        case "PermissionRequest":
            c.request = e.toolName == "AskUserQuestion"
                ? questionRequest(e, transcript: c.transcriptPath)
                : permissionRequest(e, transcript: c.transcriptPath)
            c.setStatus(.waiting, at: e.date)

        case "Notification":
            guard let type = e.string("notification_type"), Self.waitingNotifications.contains(type) else { break }
            // Подробный запрос обычно уже пришёл из PermissionRequest — не затираем его.
            if !c.status.isWaiting || c.request == nil {
                c.request = PendingRequest(
                    kind: type == "permission_prompt" ? .permission : .question,
                    context: lastMessage(c.transcriptPath) ?? e.string("message"))
                c.setStatus(.waiting, at: e.date)
            }

        case "PostToolUse", "PostToolUseFailure":
            // Разрешение дали (или ответили на вопрос) в терминале — Claude снова работает.
            if c.status.isWaiting {
                c.request = nil
                c.setStatus(.working, at: e.date)
            }

        case "Stop", "StopFailure":
            c.request = nil
            c.setStatus(.done, at: e.date)

        case "SessionEnd":
            if e.string("reason") == "clear" {
                // /clear начинает новую сессию в той же вкладке — старый чат больше не нужен.
                if let i = existing { chats.remove(at: i) }
                return
            }
            end(&c, at: e.date)

        default:
            break
        }

        if let i = existing { chats[i] = c } else { chats.append(c) }
    }

    /// Раз в полминуты: сессии без живого процесса claude считаем завершёнными, старые завершённые удаляем.
    func housekeeping(now: Date = Date()) {
        var updated = chats
        for i in updated.indices where updated[i].endedAt == nil {
            if let pid = updated[i].claudePid, !Self.isAlive(pid) { end(&updated[i], at: now) }
        }
        updated.removeAll { chat in
            guard let ended = chat.endedAt else { return false }
            return now.timeIntervalSince(ended) > Self.endedChatLifetime
        }
        if updated != chats { chats = updated }
    }

    private func end(_ chat: inout Chat, at date: Date) {
        chat.endedAt = date
        chat.request = nil
        chat.setStatus(.seen, at: date)
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Запросы

    private func lastMessage(_ transcript: String?) -> String? {
        guard let path = transcript, let text = Transcript.lastAssistantText(path: path) else { return nil }
        return Transcript.excerpt(text)
    }

    private func permissionRequest(_ e: HookEvent, transcript: String?) -> PendingRequest {
        let input = e.toolInput
        let tool = e.toolName ?? "?"
        let command: String
        if let cmd = input["command"] as? String {
            command = cmd
        } else if let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) {
            command = Project.abbreviate(path)
        } else if let url = input["url"] as? String {
            command = url
        } else if let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8), json != "{}" {
            command = String(json.prefix(300))
        } else {
            command = tool
        }
        let suggestions = e.payload["permission_suggestions"] as? [Any] ?? []
        return PendingRequest(kind: .permission, context: lastMessage(transcript), command: command,
                              toolName: tool, allowAlways: !suggestions.isEmpty)
    }

    private func questionRequest(_ e: HookEvent, transcript: String?) -> PendingRequest {
        let questions = e.toolInput["questions"] as? [[String: Any]] ?? []
        let first = questions.first ?? [:]
        let options = (first["options"] as? [[String: Any]] ?? []).compactMap { option -> String? in
            guard let label = option["label"] as? String else { return nil }
            if let detail = option["description"] as? String, !detail.isEmpty { return label + " — " + detail }
            return label
        }
        return PendingRequest(kind: .question, context: lastMessage(transcript),
                              question: first["question"] as? String, options: options,
                              toolName: e.toolName)
    }
}
