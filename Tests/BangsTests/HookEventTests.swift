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
                  "transcript_path":"/t.jsonl","last_assistant_message":"done"}}
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
        #expect(e.transcriptPath == "/t.jsonl")
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

    @Test func toolFields() throws {
        let e = hookEvent("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "ls"]])
        #expect(e.toolName == "Bash")
        #expect(e.toolInput["command"] as? String == "ls")
    }
}
