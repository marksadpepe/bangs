import Foundation
import Testing
@testable import Bangs

@Suite("Транскрипт")
struct TranscriptTests {
    private static let lines: [[String: Any]] = [
        ["type": "user", "isMeta": true, "message": ["role": "user", "content": "meta caveat"]],
        ["type": "user", "message": ["role": "user", "content": "<command-name>/exit</command-name>"]],
        ["type": "user", "message": ["role": "user", "content": "Caveat: the messages below…"]],
        ["type": "user", "message": ["role": "user", "content": [["type": "text", "text": "  Fix the login bug  "]]]],
        ["type": "assistant", "message": ["content": [["type": "text", "text": "First answer"]]]],
        ["type": "user", "message": ["content": [["type": "tool_result", "content": "output"]]]],
        ["type": "assistant", "message": ["content": [
            ["type": "text", "text": "I need to run **the tests**"],
            ["type": "text", "text": "with `pnpm`."],
        ]]],
        ["type": "assistant", "message": ["content": [["type": "tool_use", "name": "Bash"]]]],
        ["type": "summary", "summary": "ignored"],
    ]

    private func writeTranscript(in dir: URL) throws -> String {
        let url = dir.appendingPathComponent("t.jsonl")
        let text = try Self.lines
            .map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
            .joined(separator: "\n") + "\nnot json\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test func firstUserPromptSkipsServiceMessages() throws {
        try withTempDir { dir in
            let path = try writeTranscript(in: dir)
            #expect(Transcript.firstUserPrompt(path: path) == "Fix the login bug")
        }
    }

    @Test func lastAssistantTextSkipsToolUse() throws {
        try withTempDir { dir in
            let path = try writeTranscript(in: dir)
            #expect(Transcript.lastAssistantText(path: path) == "I need to run **the tests**\nwith `pnpm`.")
        }
    }

    @Test func missingFileGivesNil() {
        #expect(Transcript.firstUserPrompt(path: "/nonexistent/t.jsonl") == nil)
        #expect(Transcript.lastAssistantText(path: "/nonexistent/t.jsonl") == nil)
    }

    @Test func permissionRequestUsesTranscriptForContext() throws {
        try withTempDir { dir in
            let path = try writeTranscript(in: dir)
            let m = makeModel()
            m.apply(hookEvent("SessionStart", ["source": "resume", "transcript_path": path]))
            #expect(m.chat("s1")?.title == "Fix the login bug")

            m.apply(hookEvent("PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "pnpm test"]]))
            #expect(m.chat("s1")?.request?.context == "I need to run the tests with pnpm.")
        }
    }

    @Test func titleCollapsesWhitespaceAndTruncates() {
        #expect(Transcript.title(from: "a\n\n b\tc") == "a b c")
        #expect(Transcript.title(from: "abcdef", limit: 4) == "abc…")
        #expect(Transcript.title(from: "abcd", limit: 4) == "abcd")
    }

    @Test func excerptKeepsTheEnd() {
        #expect(Transcript.excerpt("Line one\n\n**Bold** `code`") == "Line one Bold code")
        let long = String(repeating: "x", count: 500) + " question?"
        let e = Transcript.excerpt(long, limit: 20)
        #expect(e.count == 20)
        #expect(e.hasPrefix("…"))
        #expect(e.hasSuffix("question?"))
    }
}
