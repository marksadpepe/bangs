import AppKit
import Darwin

/// Переход в Terminal.app на вкладку чата (по tty). Если вкладки нет — новое окно с `claude --resume`.
@MainActor
enum TerminalJumper {
    private static let bundleId = "com.apple.Terminal"

    enum Outcome { case focused, resumed, alreadyRunningElsewhere, notAuthorized, failed }

    @discardableResult
    static func open(_ chat: Chat) -> Outcome {
        if let tty = chat.tty, SafeFile.isValidTTY(tty), isTerminalRunning {
            switch focusTab(tty: tty) {
            case true?: return .focused
            case false?: break
            case nil: if lastError == -1743 { return reportNotAuthorized() }
            }
        }

        // Процесс claude ещё жив (например, в другом терминале) — второй `--resume` той же сессии не запускаем.
        if let pid = chat.claudePid, chat.endedAt == nil, kill(pid, 0) == 0 || errno == EPERM {
            activateTerminal()
            return .alreadyRunningElsewhere
        }
        return resume(chat)
    }

    // MARK: - AppleScript

    private static var lastError: Int?

    private static var isTerminalRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    /// true — вкладка найдена и выбрана, false — не найдена, nil — ошибка AppleScript.
    private static func focusTab(tty: String) -> Bool? {
        let script = """
        tell application id "\(bundleId)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(appleScriptEscape(tty))" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
        return run(script)?.booleanValue
    }

    /// Команда для возобновления сессии в новом окне Terminal или nil, если данные чата подозрительные:
    /// id сессии — только [A-Za-z0-9._-], папка проекта и CLAUDE_CONFIG_DIR должны существовать.
    nonisolated static func resumeCommand(for chat: Chat) -> String? {
        guard SafeFile.isValidSessionId(chat.id), SafeFile.isDirectory(chat.cwd) else { return nil }
        var command = "cd \(shellQuote(chat.cwd)) && "
        let defaultConfig = NSHomeDirectory() + "/.claude"
        if let dir = chat.configDir, dir != defaultConfig {
            guard SafeFile.isDirectory(dir) else { return nil }
            command += "CLAUDE_CONFIG_DIR=\(shellQuote(dir)) "
        }
        return command + "claude --resume \(shellQuote(chat.id))"
    }

    private static func resume(_ chat: Chat) -> Outcome {
        guard let command = resumeCommand(for: chat) else {
            NSLog("Bangs: отказ возобновить сессию — подозрительные данные чата")
            activateTerminal()
            return .failed
        }
        let script = """
        tell application id "\(bundleId)"
            activate
            do script "\(appleScriptEscape(command))"
        end tell
        """
        if run(script) != nil { return .resumed }
        return lastError == -1743 ? reportNotAuthorized() : .failed
    }

    private static func activateTerminal() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
    }

    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        lastError = nil
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            lastError = error[NSAppleScript.errorNumber] as? Int
            NSLog("Bangs: AppleScript error: \(error)")
            return nil
        }
        return result
    }

    /// Нет разрешения на управление Terminal — открываем нужный раздел настроек.
    private static func reportNotAuthorized() -> Outcome {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
        return .notAuthorized
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
