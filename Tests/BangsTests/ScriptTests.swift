import Foundation
import Testing
@testable import Bangs

/// Скрипты запускаются во временном HOME — реальные ~/.claude и ~/Library не трогаются.
@Suite("notch-hook", .serialized)
struct HookScriptTests {
    private let hook = repoRoot.appendingPathComponent("hooks/notch-hook").path

    private func env(home: URL, port: UInt16, extra: [String: String] = [:]) -> [String: String] {
        ["PATH": testPath, "HOME": home.path, "BANGS_PORT": String(port)]
            .merging(extra) { _, new in new }
    }

    @Test func deliversEnvelopeToServerAndSlimsToolResponse() async throws {
        try await withTempDir { home in
            let collector = Collector()
            let server = EventServer { collector.append($0) }
            let port = randomPort()
            try server.start(port: port)
            defer { server.stop() }
            try await Task.sleep(for: .milliseconds(150))

            let input = #"{"session_id":"s9","hook_event_name":"PostToolUse","cwd":"/x","tool_name":"Bash","tool_response":{"stdout":"HUGE"}}"#
            let result = try runProcess("/bin/bash", [hook],
                                        environment: env(home: home, port: port, extra: [
                                            "CLAUDE_PROJECT_DIR": "/work/proj", "CLAUDE_CONFIG_DIR": "/work/cfg",
                                        ]),
                                        stdin: Data(input.utf8))
            #expect(result.status == 0)

            let data = try #require(try await collector.wait().first)
            let e = try #require(HookEvent(data: data))
            #expect(e.name == "PostToolUse")
            #expect(e.sessionId == "s9")
            #expect(e.projectDir == "/work/proj")
            #expect(e.configDir == "/work/cfg")
            #expect(e.toolName == "Bash")
            #expect(e.payload["tool_response"] == nil, "тяжёлый tool_response вырезается")
            #expect(e.claudePid != nil)
            #expect(abs(e.date.timeIntervalSinceNow) < 10)
        }
    }

    @Test func fallsBackToInboxWhenAppIsNotRunning() throws {
        try withTempDir { home in
            let input = #"{"session_id":"s1","hook_event_name":"Stop"}"#
            // Порт 1 закрыт — curl сразу получит отказ.
            let result = try runProcess("/bin/bash", [hook],
                                        environment: env(home: home, port: 1, extra: ["CLAUDE_PROJECT_DIR": #"/tmp/a "quoted" \dir"#]),
                                        stdin: Data(input.utf8))
            #expect(result.status == 0)

            let inbox = home.appendingPathComponent("Library/Application Support/Bangs/inbox")
            let files = try FileManager.default.contentsOfDirectory(atPath: inbox.path)
            #expect(files.count == 1)
            #expect(files.first?.hasSuffix(".json") == true)

            let data = try Data(contentsOf: inbox.appendingPathComponent(try #require(files.first)))
            let e = try #require(HookEvent(data: data), "конверт — валидный JSON даже с кавычками в пути")
            #expect(e.name == "Stop")
            #expect(e.projectDir == #"/tmp/a "quoted" \dir"#)
            #expect(e.configDir == home.path + "/.claude", "без CLAUDE_CONFIG_DIR — ~/.claude")
        }
    }

    @Test func emptyInputExitsQuietly() throws {
        try withTempDir { home in
            let result = try runProcess("/bin/bash", [hook], environment: env(home: home, port: 1), stdin: Data())
            #expect(result.status == 0)
            #expect(result.output.isEmpty)
            let inbox = home.appendingPathComponent("Library/Application Support/Bangs/inbox")
            #expect(!FileManager.default.fileExists(atPath: inbox.path))
        }
    }
}

@Suite("install-hooks.sh", .serialized)
struct InstallHooksTests {
    private let script = repoRoot.appendingPathComponent("scripts/install-hooks.sh").path
    private let events = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PreToolUse", "PostToolUse",
                          "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd"]

    private func install(_ home: URL, _ args: [String]) throws -> ProcessResult {
        try runProcess("/bin/bash", [script] + args,
                       environment: ["PATH": testPath, "HOME": home.path])
    }

    private func settings(_ dir: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Обработчики Bangs для события (по команде notch-hook).
    private func ourHandlers(_ hooks: [String: Any], _ event: String, home: URL) -> [[String: Any]] {
        let groups = hooks[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .filter { $0["command"] as? String == home.path + "/.local/bin/notch-hook" }
    }

    @Test func installsIdempotentlyAndUninstallsCleanly() throws {
        try withTempDir { home in
            let cfg = home.appendingPathComponent("cfg")
            try writeJSON([
                "theme": "dark",
                "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo mine"]]]]],
            ], to: cfg.appendingPathComponent("settings.json"))

            #expect(try install(home, [cfg.path]).status == 0)
            #expect(try install(home, [cfg.path]).status == 0)

            #expect(FileManager.default.isExecutableFile(atPath: home.path + "/.local/bin/notch-hook"))
            let installed = try settings(cfg)
            #expect(installed["theme"] as? String == "dark")
            let hooks = try #require(installed["hooks"] as? [String: Any])
            for event in events {
                let handlers = ourHandlers(hooks, event, home: home)
                #expect(handlers.count == 1, "\(event): ровно один обработчик после двух установок")
                let isAsync = handlers.first?["async"] as? Bool ?? false
                #expect(isAsync == (event != "SessionEnd"), "\(event): async")
            }
            let pre = try #require((hooks["PreToolUse"] as? [[String: Any]])?.first)
            #expect(pre["matcher"] as? String == "AskUserQuestion")
            #expect((hooks["Stop"] as? [[String: Any]])?.count == 2, "чужой хук сохранён")

            let backups = try FileManager.default.contentsOfDirectory(atPath: cfg.path).filter { $0.hasPrefix("settings.json.bak-") }
            #expect(!backups.isEmpty)

            #expect(try install(home, ["--uninstall", cfg.path]).status == 0)
            let cleaned = try settings(cfg)
            let left = try #require(cleaned["hooks"] as? [String: Any])
            #expect(Array(left.keys) == ["Stop"])
            let stop = try #require((left["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
            #expect(stop.first?["command"] as? String == "echo mine")
        }
    }

    @Test func createsSettingsWhenMissing() throws {
        try withTempDir { home in
            let cfg = home.appendingPathComponent("fresh")
            #expect(try install(home, [cfg.path]).status == 0)
            let hooks = try #require(try settings(cfg)["hooks"] as? [String: Any])
            #expect(Set(hooks.keys) == Set(events))

            #expect(try install(home, ["--uninstall", cfg.path]).status == 0)
            #expect(try settings(cfg)["hooks"] == nil, "пустой блок hooks удаляется")
        }
    }
}
