import Foundation

/// Событие хука Claude Code вместе с полями, которые добавил notch-hook.
struct HookEvent {
    let name: String
    let sessionId: String
    let date: Date
    let tty: String?
    let configDir: String?
    let projectDir: String?
    let claudePid: Int32?
    let payload: [String: Any]

    /// Принимает конверт notch-hook или «голый» JSON хука (удобно для ручной проверки через curl).
    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let envelope = object["event"] is [String: Any] ? object : [:]
        let event = (object["event"] as? [String: Any]) ?? object
        guard let name = event["hook_event_name"] as? String,
              let sessionId = event["session_id"] as? String, !sessionId.isEmpty else { return nil }

        func nonEmpty(_ key: String) -> String? {
            guard let s = envelope[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        self.name = name
        self.sessionId = sessionId
        self.payload = event
        self.tty = nonEmpty("tty")
        self.configDir = nonEmpty("config_dir")
        self.projectDir = nonEmpty("project_dir")
        self.claudePid = (envelope["claude_pid"] as? NSNumber).map { Int32(truncating: $0) }
        if let ts = envelope["ts"] as? NSNumber, ts.doubleValue > 0 {
            self.date = Date(timeIntervalSince1970: ts.doubleValue)
        } else {
            self.date = Date()
        }
    }

    func string(_ key: String) -> String? {
        guard let s = payload[key] as? String, !s.isEmpty else { return nil }
        return s
    }

    var cwd: String? { string("cwd") }
    var transcriptPath: String? { string("transcript_path") }
    var toolName: String? { string("tool_name") }
    var toolInput: [String: Any] { payload["tool_input"] as? [String: Any] ?? [:] }
}
