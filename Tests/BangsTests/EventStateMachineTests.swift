import Foundation
import Testing
@testable import Bangs

@Suite("Переходы статусов по событиям")
struct EventStateMachineTests {
    @Test func promptCreatesWorkingChatWithTitle() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", tty: "/dev/ttys007", pid: 77, ["prompt": "  Fix the\nlogin   bug  "]))
        let c = try #require(m.chat("s1"))
        #expect(c.title == "Fix the login bug")
        #expect(c.status == .working)
        #expect(c.tty == "/dev/ttys007")
        #expect(c.claudePid == 77)
        #expect(c.cwd == "/tmp/proj")
    }

    @Test func longPromptTitleIsTruncated() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": String(repeating: "a", count: 100)]))
        let title = try #require(m.chat("s1")).title
        #expect(title.count == 40)
        #expect(title.hasSuffix("…"))
    }

    @Test func titleIsNotOverwrittenByLaterPrompts() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "First"]))
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Second"]))
        #expect(try #require(m.chat("s1")).title == "First")
    }

    @Test func freshSessionIsHiddenUntilFirstPrompt() {
        let m = makeModel()
        m.apply(hookEvent("SessionStart", ["source": "startup"]))
        #expect(m.chats.count == 1)
        #expect(m.visibleChats.isEmpty)
        #expect(m.projects.isEmpty)
    }

    @Test func stopMarksDone() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("Stop", ["last_assistant_message": "All done"]))
        #expect(try #require(m.chat("s1")).status == .done)
        #expect(m.indicator == .done(1))
    }

    @Test func stopFailureAlsoMarksDone() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("StopFailure"))
        #expect(try #require(m.chat("s1")).status == .done)
    }

    @Test func bashPermissionRequest() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("PermissionRequest", [
            "tool_name": "Bash",
            "tool_input": ["command": "pnpm install && pnpm test", "description": "Install"],
            "permission_suggestions": [["type": "addRules"]],
        ]))
        let c = try #require(m.chat("s1"))
        #expect(c.status == .waiting)
        let r = try #require(c.request)
        #expect(r.kind == .permission)
        #expect(r.command == "pnpm install && pnpm test")
        #expect(r.toolName == "Bash")
        #expect(r.allowAlways)
        #expect(m.indicator == .waiting(1))
    }

    @Test func editPermissionShowsAbbreviatedPath() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("PermissionRequest", [
            "tool_name": "Edit",
            "tool_input": ["file_path": NSHomeDirectory() + "/work/app.swift", "old_string": "a", "new_string": "b"],
        ]))
        let r = try #require(m.chat("s1")?.request)
        #expect(r.command == "~/work/app.swift")
        #expect(r.toolName == "Edit")
        #expect(r.allowAlways == false)
    }

    @Test func webFetchPermissionShowsURL() throws {
        let m = makeModel()
        m.apply(hookEvent("PermissionRequest", ["tool_name": "WebFetch", "tool_input": ["url": "https://example.com", "prompt": "x"]]))
        #expect(try #require(m.chat("s1")?.request).command == "https://example.com")
    }

    @Test func askUserQuestionBecomesQuestion() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("PreToolUse", [
            "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [[
                "question": "Which manager?",
                "options": [["label": "zinit", "description": "fast"], ["label": "antidote"]],
            ]]],
        ]))
        let c = try #require(m.chat("s1"))
        #expect(c.status == .waiting)
        let r = try #require(c.request)
        #expect(r.kind == .question)
        #expect(r.question == "Which manager?")
        #expect(r.options == ["zinit — fast", "antidote"])
    }

    @Test func otherPreToolUseIsIgnored() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("Stop"))
        m.apply(hookEvent("PreToolUse", ["tool_name": "Bash", "tool_input": ["command": "ls"]]))
        #expect(try #require(m.chat("s1")).status == .done)
    }

    @Test func idleNotificationDoesNotMeanWaiting() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("Stop"))
        m.apply(hookEvent("Notification", ["notification_type": "idle_prompt", "message": "Claude is waiting"]))
        #expect(try #require(m.chat("s1")).status == .done)
    }

    @Test(arguments: ["permission_prompt", "elicitation_dialog", "agent_needs_input"])
    func waitingNotifications(_ type: String) throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("Notification", ["notification_type": type, "message": "Needs input"]))
        let c = try #require(m.chat("s1"))
        #expect(c.status == .waiting)
        #expect(c.request?.context == "Needs input")
        #expect(c.request?.kind == (type == "permission_prompt" ? .permission : .question))
    }

    @Test func notificationDoesNotOverwriteDetailedRequest() throws {
        let m = makeModel()
        m.apply(hookEvent("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "rm -rf build"]]))
        m.apply(hookEvent("Notification", ["notification_type": "permission_prompt", "message": "Claude needs permission"]))
        #expect(try #require(m.chat("s1")?.request).command == "rm -rf build")
    }

    @Test func postToolUseResumesWaitingChat() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "ls"]]))
        m.apply(hookEvent("PostToolUse", ["tool_name": "Bash"]))
        let c = try #require(m.chat("s1"))
        #expect(c.status == .working)
        #expect(c.request == nil)
    }

    @Test func postToolUseFailureResumesWaitingChat() throws {
        let m = makeModel()
        m.apply(hookEvent("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "ls"]]))
        m.apply(hookEvent("PostToolUseFailure", ["tool_name": "Bash"]))
        #expect(try #require(m.chat("s1")).status == .working)
    }

    @Test func postToolUseDoesNotTouchDoneChat() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("Stop"))
        m.apply(hookEvent("PostToolUse", ["tool_name": "Bash"]))
        #expect(try #require(m.chat("s1")).status == .done)
    }

    @Test func newPromptAlwaysReturnsToWorking() throws {
        for start in [ChatStatus.done, .waiting, .waitSeen, .denied, .seen] {
            let m = makeModel()
            m.chats = [makeChat("s1", start)]
            m.apply(hookEvent("UserPromptSubmit", ["prompt": "Again"]))
            #expect(m.chat("s1")?.status == .working, "из \(start)")
        }
    }

    @Test func sessionEndMarksEndedAndSeen() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("Stop"))
        m.apply(hookEvent("SessionEnd", ["reason": "prompt_input_exit"]))
        let c = try #require(m.chat("s1"))
        #expect(c.endedAt != nil)
        #expect(c.status == .seen)
        #expect(m.indicator == .quiet)
    }

    @Test func clearRemovesChatImmediately() {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", ["prompt": "Task"]))
        m.apply(hookEvent("SessionEnd", ["reason": "clear"]))
        #expect(m.chats.isEmpty)
    }

    @Test func newSessionInSameTabEndsPreviousOne() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", session: "old", tty: "/dev/ttys002", ["prompt": "Old"]))
        m.apply(hookEvent("UserPromptSubmit", session: "other", tty: "/dev/ttys003", ["prompt": "Other tab"]))
        m.apply(hookEvent("SessionStart", session: "new", tty: "/dev/ttys002", ["source": "startup"]))
        #expect(try #require(m.chat("old")).endedAt != nil)
        #expect(try #require(m.chat("other")).endedAt == nil)
    }

    @Test func sessionDiscoveredMidWorkIsWorking() throws {
        let m = makeModel()
        m.apply(hookEvent("PostToolUse", session: "late", ["tool_name": "Read"]))
        #expect(try #require(m.chat("late")).status == .working)
    }

    @Test func projectDirGroupsChatsEvenWhenCwdChanges() throws {
        let m = makeModel()
        m.apply(hookEvent("UserPromptSubmit", cwd: "/work/app", ["prompt": "Task"]))
        m.apply(hookEvent("Stop", cwd: "/work/app/subdir"))
        #expect(try #require(m.chat("s1")).cwd == "/work/app")
    }

    @Test func eventTimestampIsUsedForStatusTime() throws {
        let m = makeModel()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        m.apply(hookEvent("UserPromptSubmit", at: t, ["prompt": "Task"]))
        #expect(try #require(m.chat("s1")).statusSince == t)
    }

    @Test func sessionTitleFieldIsUsed() throws {
        let m = makeModel()
        m.apply(hookEvent("SessionStart", ["source": "resume", "session_title": "Named session"]))
        #expect(try #require(m.chat("s1")).title == "Named session")
    }

    @Test func configDirChangeReloadsAccount() throws {
        try withTempDir { dir in
            try writeJSON(["oauthAccount": ["displayName": "Work", "emailAddress": "w@x.dev"]],
                          to: dir.appendingPathComponent(".claude.json"))
            let m = makeModel()
            let json = #"{"config_dir":"\#(dir.path)","event":{"session_id":"s1","hook_event_name":"UserPromptSubmit","prompt":"x"}}"#
            m.apply(try #require(HookEvent(data: Data(json.utf8))))
            #expect(m.account?.name == "Work")
            #expect(m.chat("s1")?.configDir == dir.path)
        }
    }

    // MARK: - Лимиты

    /// Регрессия: флуд событиями раздувал список чатов без ограничений.
    @Test func chatCountIsCapped() {
        let m = makeModel()
        for i in 0..<150 {
            m.apply(hookEvent("UserPromptSubmit", session: "s\(i)", ["prompt": "Task \(i)"]))
        }
        #expect(m.chats.count == AppModel.maxChats)
        #expect(m.chat("s149") != nil, "новый чат не вытесняется")
    }

    @Test func endedAndSeenChatsAreEvictedFirst() {
        let m = makeModel()
        var ended = makeChat("ended", .seen, since: Date())
        ended.endedAt = Date()
        let seen = makeChat("seen", .seen, since: Date().addingTimeInterval(-10))
        let waiting = makeChat("waiting", .waiting, since: Date().addingTimeInterval(-9999))
        m.chats = [waiting, seen, ended] + (0..<(AppModel.maxChats - 3)).map { makeChat("w\($0)", .working) }
        m.apply(hookEvent("UserPromptSubmit", session: "new1", ["prompt": "x"]))
        m.apply(hookEvent("UserPromptSubmit", session: "new2", ["prompt": "x"]))
        #expect(m.chat("ended") == nil)
        #expect(m.chat("seen") == nil)
        #expect(m.chat("waiting") != nil, "ожидающий ответа чат не выбрасываем раньше просмотренных")
    }

    @Test func longStringsAreClipped() throws {
        let m = makeModel()
        m.apply(hookEvent("PermissionRequest", [
            "tool_name": String(repeating: "T", count: 500),
            "tool_input": ["command": String(repeating: "c", count: 10_000)],
        ]))
        let r = try #require(m.chat("s1")?.request)
        #expect(r.command?.count == 2000)
        #expect(r.toolName?.count == 100)

        m.apply(hookEvent("PreToolUse", session: "q", ["tool_name": "AskUserQuestion", "tool_input": ["questions": [[
            "question": String(repeating: "q", count: 5000),
            "options": (0..<50).map { ["label": String(repeating: "o", count: 1000), "description": "\($0)"] },
        ]]]]))
        let q = try #require(m.chat("q")?.request)
        #expect(q.question?.count == 1000)
        #expect(q.options.count == 10)
        #expect(q.options.allSatisfy { $0.count <= 300 })
    }

    @Test func unsafeTranscriptPathIsNotRead() throws {
        try withTempDir { dir in
            let secret = dir.appendingPathComponent("secret.jsonl")
            try Data(#"{"type":"user","message":{"content":"TOP SECRET"}}"#.utf8).write(to: secret)
            let m = makeModel()
            m.apply(hookEvent("SessionStart", ["source": "resume", "transcript_path": secret.path]))
            #expect(m.chat("s1")?.title == "", "чужой файл не стал названием чата")
        }
    }

    // MARK: - Уборка

    @Test func housekeepingEndsChatsWithDeadProcess() throws {
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()

        let m = makeModel()
        var dead = makeChat("dead", .working)
        dead.claudePid = finished.processIdentifier
        var alive = makeChat("alive", .working)
        alive.claudePid = getpid()
        m.chats = [dead, alive]

        m.housekeeping()
        #expect(m.chat("dead")?.endedAt != nil)
        #expect(m.chat("dead")?.status == .seen)
        #expect(m.chat("alive")?.endedAt == nil)
        #expect(m.chat("alive")?.status == .working)
    }

    @Test func housekeepingRemovesChatsEndedLongAgo() {
        let now = Date()
        let m = makeModel()
        var old = makeChat("old", .seen)
        old.endedAt = now.addingTimeInterval(-11 * 60)
        var recent = makeChat("recent", .seen)
        recent.endedAt = now.addingTimeInterval(-5 * 60)
        m.chats = [old, recent, makeChat("live", .working)]

        m.housekeeping(now: now)
        #expect(m.chats.map(\.id) == ["recent", "live"])
    }
}
