import Foundation
import Testing
@testable import Bangs

@Suite("Разбор событий хуков")
struct HookEventTests {
    @Test func parsesEnvelopeFields() throws {
        let json = """
        {"tty":"/dev/ttys004","config_dir":"/Users/me/.claude","project_dir":"/work/app",
         "claude_pid":4242,"ts":1700000000,
         "event":{"session_id":"abc","hook_event_name":"Stop","cwd":"/work/app/sub",
                  "transcript_path":"/Users/me/.claude/projects/app/abc.jsonl","last_assistant_message":"done"}}
        """
        let e = try #require(HookEvent(data: Data(json.utf8)))
        #expect(e.name == "Stop")
        #expect(e.sessionId == "abc")
        #expect(e.tty == "/dev/ttys004")
        #expect(e.configDir == "/Users/me/.claude")
        #expect(e.projectDir == "/work/app")
        #expect(e.claudePid == 4242)
        #expect(e.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(e.cwd == "/work/app/sub")
        #expect(e.transcriptPath == "/Users/me/.claude/projects/app/abc.jsonl")
        #expect(e.string("last_assistant_message") == "done")
    }

    @Test func acceptsBareHookJSON() throws {
        let json = #"{"session_id":"x","hook_event_name":"UserPromptSubmit","prompt":"hi"}"#
        let e = try #require(HookEvent(data: Data(json.utf8)))
        #expect(e.name == "UserPromptSubmit")
        #expect(e.tty == nil)
        #expect(e.claudePid == nil)
        #expect(abs(e.date.timeIntervalSinceNow) < 5)
    }

    @Test func emptyEnvelopeStringsAreNil() throws {
        let json = #"{"tty":"","config_dir":"","project_dir":"","claude_pid":null,"event":{"session_id":"x","hook_event_name":"Stop"}}"#
        let e = try #require(HookEvent(data: Data(json.utf8)))
        #expect(e.tty == nil)
        #expect(e.configDir == nil)
        #expect(e.projectDir == nil)
        #expect(e.claudePid == nil)
    }

    @Test(arguments: [
        #"{"event":{"hook_event_name":"Stop"}}"#,
        #"{"event":{"session_id":"","hook_event_name":"Stop"}}"#,
        #"{"session_id":"x"}"#,
        "not json",
        "[]",
    ])
    func rejectsInvalidInput(_ json: String) {
        #expect(HookEvent(data: Data(json.utf8)) == nil)
    }

    /// Подозрительные поля конверта отбрасываются, а событие с плохим id сессии — целиком.
    @Test func dropsSuspiciousFields() throws {
        let json = """
        {"tty":"/dev/ttys001\\" & do shell script \\"id","config_dir":"relative/dir","project_dir":"/tmp/../etc",
         "claude_pid":1,
         "event":{"session_id":"ok-1","hook_event_name":"Stop","cwd":"/tmp/a\\nb","transcript_path":"/x/../y.jsonl"}}
        """
        let e = try #require(HookEvent(data: Data(json.utf8)))
        #expect(e.tty == nil)
        #expect(e.configDir == nil)
        #expect(e.projectDir == nil)
        #expect(e.claudePid == nil, "PID 1 (launchd) не принимаем")
        #expect(e.cwd == nil)
        #expect(e.transcriptPath == nil)
    }

    @Test(arguments: ["../../etc", "a b", "x'; rm -rf ~", "-flag", String(repeating: "a", count: 200)])
    func rejectsBadSessionIds(_ id: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["session_id": id, "hook_event_name": "Stop"])
        #expect(HookEvent(data: data) == nil)
    }

    @Test func toolFields() throws {
        let e = hookEvent("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "ls"]])
        #expect(e.toolName == "Bash")
        #expect(e.toolInput["command"] as? String == "ls")
    }
}
