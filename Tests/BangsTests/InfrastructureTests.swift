import Foundation
import Testing
@testable import Bangs

@Suite("HTTP-сервер событий", .serialized)
struct EventServerTests {
    private func request(_ port: UInt16, _ method: String, _ path: String, body: Data? = nil,
                         token: String? = testToken, headers: [String: String] = [:]) async throws -> (Int, String) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = method
        req.httpBody = body
        if let token { req.setValue(token, forHTTPHeaderField: "X-Bangs-Token") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    private func startServer(_ collector: Collector) async throws -> (EventServer, UInt16) {
        let server = EventServer(token: testToken) { collector.append($0) }
        let port = randomPort()
        try server.start(port: port)
        try await Task.sleep(for: .milliseconds(150))
        return (server, port)
    }

    private let validEvent = Data(#"{"event":{"session_id":"x","hook_event_name":"Stop"}}"#.utf8)

    // MARK: - Защита

    /// Регрессия: события принимались от кого угодно, в т.ч. «как с веб-страницы».
    @Test func rejectsEventsWithoutValidToken() async throws {
        let collector = Collector()
        let (server, port) = try await startServer(collector)
        defer { server.stop() }

        let (none, _) = try await request(port, "POST", "/event", body: validEvent, token: nil)
        #expect(none == 401)
        let (wrong, _) = try await request(port, "POST", "/event", body: validEvent,
                                           token: String(repeating: "cd", count: 32))
        #expect(wrong == 401)
        let (browserLike, _) = try await request(port, "POST", "/event", body: validEvent, token: nil,
                                                 headers: ["Origin": "https://evil.example", "Content-Type": "text/plain"])
        #expect(browserLike == 401)
        let (empty, _) = try await request(port, "POST", "/event", body: validEvent, token: "")
        #expect(empty == 401)

        try await Task.sleep(for: .milliseconds(200))
        #expect(collector.all.isEmpty, "ни одно событие без токена не дошло")

        let (ok, _) = try await request(port, "POST", "/event", body: validEvent)
        #expect(ok == 204)
        #expect(try await collector.wait().count == 1)
    }

    /// Регрессия: `Content-Length: -5` ронял приложение (Range requires lowerBound <= upperBound).
    @Test(arguments: ["-5", "abc", "+5", "5 5", "99999999999", "\(EventServer.maxBodySize + 1)"])
    func malformedContentLengthIsRejectedWithoutCrash(_ length: String) async throws {
        let collector = Collector()
        let (server, port) = try await startServer(collector)
        defer { server.stop() }

        let response = try rawRequest(port: port,
            "POST /event HTTP/1.1\r\nHost: x\r\nX-Bangs-Token: \(testToken)\r\nContent-Length: \(length)\r\n\r\nabc")
        #expect(response.hasPrefix("HTTP/1.1 400"), "\(response)")
        // Сервер жив и продолжает принимать события.
        let (ok, _) = try await request(port, "POST", "/event", body: validEvent)
        #expect(ok == 204)
    }

    @Test(arguments: [
        "garbage\r\n\r\n",
        "POST /event\r\n\r\n",
        "POST /event HTTP/1.1\r\nno-colon-header\r\n\r\n",
        "POST /event HTTP/1.1\r\nContent-Length: 3\r\nContent-Length: 1\r\n\r\nabc",
        "POST /event HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n",
    ])
    func malformedRequestsAreRejected(_ raw: String) async throws {
        let collector = Collector()
        let (server, port) = try await startServer(collector)
        defer { server.stop() }
        #expect(try rawRequest(port: port, raw).hasPrefix("HTTP/1.1 400"))
        #expect(collector.all.isEmpty)
    }

    @Test func oversizedHeaderIsRejected() async throws {
        let collector = Collector()
        let (server, port) = try await startServer(collector)
        defer { server.stop() }
        let raw = "GET /health HTTP/1.1\r\nX-Junk: " + String(repeating: "a", count: 20_000) + "\r\n\r\n"
        #expect(try rawRequest(port: port, raw).hasPrefix("HTTP/1.1 400"))
    }

    @Test func tokenComparison() {
        #expect(EventServer.constantTimeEquals(testToken, testToken))
        #expect(!EventServer.constantTimeEquals(testToken, String(testToken.dropLast())))
        #expect(!EventServer.constantTimeEquals("", ""))
        #expect(!EventServer.constantTimeEquals(testToken, String(testToken.dropLast()) + "c"))
    }

    @Test func acceptsPostedEvent() async throws {
        let collector = Collector()
        let (server, port) = try await startServer(collector)
        defer { server.stop() }

        let body = Data(#"{"event":{"session_id":"x","hook_event_name":"Stop"}}"#.utf8)
        let (status, _) = try await request(port, "POST", "/event", body: body)
        #expect(status == 204)
        let received = try await collector.wait()
        #expect(received.first == body)
    }

    @Test func receivesLargeBodyInChunks() async throws {
        let collector = Collector()
        let (server, port) = try await startServer(collector)
        defer { server.stop() }

        let big = String(repeating: "y", count: 300_000)
        let body = Data(#"{"event":{"session_id":"x","hook_event_name":"Stop","last_assistant_message":"\#(big)"}}"#.utf8)
        let (status, _) = try await request(port, "POST", "/event", body: body)
        #expect(status == 204)
        let received = try await collector.wait()
        #expect(received.first?.count == body.count)
        #expect(HookEvent(data: try #require(received.first))?.string("last_assistant_message")?.count == 300_000)
    }

    @Test func healthAndUnknownPaths() async throws {
        let collector = Collector()
        let (server, port) = try await startServer(collector)
        defer { server.stop() }

        let (health, text) = try await request(port, "GET", "/health")
        #expect(health == 200)
        #expect(text == "ok")
        let (missing, _) = try await request(port, "GET", "/nope")
        #expect(missing == 404)
        #expect(collector.all.isEmpty)
    }
}

@Suite("Папка inbox")
struct InboxWatcherTests {
    @Test func drainsJSONFilesInOrderAndRemovesThem() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            try Data("first".utf8).write(to: dir.appendingPathComponent("1700000001-1.json"))
            try Data("second".utf8).write(to: dir.appendingPathComponent("1700000002-1.json"))
            try Data("partial".utf8).write(to: dir.appendingPathComponent("1700000003-1.json.tmp"))
            let old = dir.appendingPathComponent("1600000000-1.json")
            try Data("stale".utf8).write(to: old)
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * 3600)], ofItemAtPath: old.path)

            var received: [String] = []
            let watcher = InboxWatcher(directory: dir) { received.append(String(decoding: $0, as: UTF8.self)) }
            watcher.start()

            #expect(received == ["first", "second"], "старые события пропускаются")
            let left = try fm.contentsOfDirectory(atPath: dir.path)
            #expect(left == ["1700000003-1.json.tmp"], "недописанный файл не трогаем")
        }
    }
}

@Suite("Аккаунт")
struct AccountReaderTests {
    @Test func readsCustomConfigDir() throws {
        try withTempDir { dir in
            try writeJSON(["oauthAccount": ["displayName": "Ann", "fullName": "Ann Lee", "emailAddress": "ann@x.dev"]],
                          to: dir.appendingPathComponent(".claude.json"))
            let account = try #require(AccountReader.read(configDir: dir.path))
            #expect(account.name == "Ann")
            #expect(account.email == "ann@x.dev")
            #expect(account.tooltip == "Ann Lee · ann@x.dev")
        }
    }

    @Test func fallsBackToFullNameThenEmail() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent(".claude.json")
            try writeJSON(["oauthAccount": ["fullName": "Bob Stone", "emailAddress": "bob@x.dev"]], to: file)
            #expect(AccountReader.read(configDir: dir.path)?.name == "Bob Stone")
            #expect(AccountReader.read(configDir: dir.path)?.tooltip == "Bob Stone · bob@x.dev")

            try writeJSON(["oauthAccount": ["emailAddress": "c@x.dev"]], to: file)
            #expect(AccountReader.read(configDir: dir.path)?.name == "c@x.dev")
        }
    }

    @Test func missingDataGivesNil() throws {
        try withTempDir { dir in
            #expect(AccountReader.read(configDir: dir.path) == nil)
            try writeJSON(["theme": "dark"], to: dir.appendingPathComponent(".claude.json"))
            #expect(AccountReader.read(configDir: dir.path) == nil)
        }
    }
}

@Suite("Настройки")
struct AppSettingsTests {
    @Test func persistsAndResets() throws {
        let suite = "bangs-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let s = AppSettings(defaults: defaults)
        s.theme = .light
        s.lang = .en
        s.doneColor = "#34C759"
        s.waitColor = "#BF5AF2"
        s.jumpOnClick = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.theme == .light)
        #expect(reloaded.lang == .en)
        #expect(reloaded.doneColor == "#34C759")
        #expect(reloaded.waitColor == "#BF5AF2")
        #expect(reloaded.jumpOnClick == false)

        reloaded.resetColors()
        #expect(reloaded.doneColor == AppSettings.defaultDone)
        #expect(reloaded.waitColor == AppSettings.defaultWait)
    }

    @Test func defaults() {
        let s = AppSettings(defaults: nil)
        #expect(s.theme == .dark)
        #expect(s.doneColor == "#FF8A3D")
        #expect(s.waitColor == "#5AA2FF")
        #expect(s.jumpOnClick)
    }
}

@Suite("Геометрия чёлки")
struct NotchGeometryTests {
    @Test func counterGetsRoomOutsideTheNotch() {
        let g = NotchGeometry.preview
        #expect(g.closedBodyWidth(active: false) == g.notchWidth)
        #expect(g.closedBodyWidth(active: true) == g.notchWidth + 80)
        #expect(g.closedEar(active: false) == 0)
        #expect(g.closedEar(active: true) == NotchGeometry.ear)
        #expect(g.headerHeight == 32)
    }

    @Test func externalDisplayPillAlwaysHasEarsAndNoExtension() {
        let g = NotchGeometry(screenFrame: .init(x: 0, y: 0, width: 1920, height: 1080), hasNotch: false,
                              notchWidth: NotchGeometry.pillWidth, notchHeight: 24)
        #expect(g.closedBodyWidth(active: true) == NotchGeometry.pillWidth)
        #expect(g.closedEar(active: false) == NotchGeometry.ear)
        #expect(g.headerHeight == 32)
    }
}

@Suite("Сохранение состояния")
struct StateStoreTests {
    @Test func oldWaitSeenStatusLoadsAsWaiting() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("state.json")
            let chats = [makeChat("a", .waitSeen), makeChat("b", .done)]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            try encoder.encode(chats).write(to: url)

            let loaded = StateStore(url: url).load()
            #expect(loaded.map(\.status) == [.waiting, .done])
        }
    }

    @Test func missingOrBrokenFileLoadsEmpty() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("state.json")
            #expect(StateStore(url: url).load().isEmpty)
            try Data("garbage".utf8).write(to: url)
            #expect(StateStore(url: url).load().isEmpty)
        }
    }
}

@Suite("Привязка сервера", .serialized)
struct EventServerBindingTests {
    /// Регрессия: сервер слушал *:port (все интерфейсы). Должен слушать только 127.0.0.1.
    @Test func listensOnLoopbackOnly() async throws {
        let server = EventServer(token: testToken) { _ in }
        let port = randomPort()
        try server.start(port: port)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(200))

        let result = try runProcess("/usr/sbin/lsof", ["-nP", "-a", "-p", String(getpid()), "-iTCP:\(port)", "-sTCP:LISTEN"],
                                    environment: ["PATH": testPath])
        #expect(result.output.contains("127.0.0.1:\(port)"), "\(result.output)")
        #expect(!result.output.contains("*:\(port)"), "\(result.output)")
    }
}

@Suite("Токен")
struct AuthTokenTests {
    @Test func createsPrivateStableToken() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("support/token")
            let first = try AuthToken.loadOrCreate(at: url)
            #expect(AuthToken.isValid(first))
            #expect(try AuthToken.loadOrCreate(at: url) == first, "токен постоянный между запусками")

            let fm = FileManager.default
            let filePerms = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
            let dirPerms = try fm.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
            #expect(filePerms == 0o600)
            #expect(dirPerms == 0o700)
        }
    }

    @Test func replacesBrokenToken() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("token")
            try Data("short".utf8).write(to: url)
            let token = try AuthToken.loadOrCreate(at: url)
            #expect(AuthToken.isValid(token))
            #expect(try String(contentsOf: url, encoding: .utf8) == token)
        }
    }

    @Test func tokensAreRandom() throws {
        try withTempDir { dir in
            let a = try AuthToken.loadOrCreate(at: dir.appendingPathComponent("a"))
            let b = try AuthToken.loadOrCreate(at: dir.appendingPathComponent("b"))
            #expect(a != b)
        }
    }
}

@Suite("Безопасные пути и файлы")
struct SafeFileTests {
    /// Регрессия: путь к именованному каналу (FIFO) в событии навсегда вешал чтение на главном потоке.
    @Test func fifoIsRejectedWithoutBlocking() throws {
        try withTempDir { dir in
            let projects = dir.appendingPathComponent("projects/p")
            try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
            let fifo = projects.appendingPathComponent("t.jsonl").path
            #expect(mkfifo(fifo, 0o600) == 0)

            let start = Date()
            #expect(Transcript.firstUserPrompt(path: fifo) == nil)
            #expect(Transcript.lastAssistantText(path: fifo) == nil)
            #expect(Date().timeIntervalSince(start) < 1)
            #expect(!SafeFile.isRegularFile(fifo))

            // Симлинк на FIFO тоже не проходит.
            let link = projects.appendingPathComponent("link.jsonl").path
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: fifo)
            #expect(!SafeFile.isRegularFile(link))

            // .claude.json-канал для аккаунта.
            let cfg = dir.appendingPathComponent("cfg")
            try FileManager.default.createDirectory(at: cfg, withIntermediateDirectories: true)
            #expect(mkfifo(cfg.appendingPathComponent(".claude.json").path, 0o600) == 0)
            #expect(AccountReader.read(configDir: cfg.path) == nil)
            #expect(Date().timeIntervalSince(start) < 1)
        }
    }

    /// Регрессия: из события можно было указать любой файл как транскрипт и показать его начало в панели.
    @Test func onlyTranscriptsUnderProjectsAreRead() throws {
        try withTempDir { dir in
            let line = #"{"type":"user","message":{"role":"user","content":"secret line"}}"#
            let outside = dir.appendingPathComponent("notes.jsonl")
            let wrongExt = dir.appendingPathComponent("projects/p/notes.txt")
            let good = dir.appendingPathComponent("projects/p/s.jsonl")
            for url in [outside, wrongExt, good] {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(line.utf8).write(to: url)
            }
            #expect(Transcript.firstUserPrompt(path: outside.path) == nil)
            #expect(Transcript.firstUserPrompt(path: wrongExt.path) == nil)
            #expect(Transcript.firstUserPrompt(path: good.path) == "secret line")
            #expect(Transcript.firstUserPrompt(path: dir.path + "/projects/p/../../notes.jsonl") == nil)
            #expect(Transcript.firstUserPrompt(path: "relative/projects/s.jsonl") == nil)
        }
    }

    @Test func validators() {
        #expect(SafeFile.isValidTTY("/dev/ttys003"))
        #expect(SafeFile.isValidTTY("/dev/tty1"))
        #expect(!SafeFile.isValidTTY("/dev/ttys003\" & quit"))
        #expect(!SafeFile.isValidTTY("/etc/passwd"))
        #expect(SafeFile.isValidSessionId("8e886c40-465c-4e4c-a227-8b2536bb97b0"))
        #expect(!SafeFile.isValidSessionId("-rf"))
        #expect(!SafeFile.isValidSessionId("a b"))
        #expect(!SafeFile.isValidSessionId("x'; rm -rf ~; '"))
        #expect(!SafeFile.isValidSessionId(String(repeating: "a", count: 129)))
        #expect(!SafeFile.isPlausiblePath("/tmp/a\nb"))
        #expect(!SafeFile.isPlausiblePath("/" + String(repeating: "a", count: 2000)))
    }
}

@Suite("Возобновление сессии в Terminal")
struct ResumeCommandTests {
    @Test func buildsQuotedCommandForRealDirectory() throws {
        try withTempDir { dir in
            let project = dir.appendingPathComponent("it's a project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            var chat = makeChat("8e886c40-465c-4e4c-a227-8b2536bb97b0", .done, cwd: project.path)
            #expect(TerminalJumper.resumeCommand(for: chat)
                    == "cd '\(dir.path)/it'\\''s a project' && claude --resume '8e886c40-465c-4e4c-a227-8b2536bb97b0'")

            chat.configDir = dir.path
            #expect(TerminalJumper.resumeCommand(for: chat)?.contains("CLAUDE_CONFIG_DIR='\(dir.path)' claude") == true)
        }
    }

    /// Регрессия: «Открыть в терминале» запускало `claude --resume` с любыми данными из события.
    @Test func refusesSuspiciousChats() throws {
        try withTempDir { dir in
            #expect(TerminalJumper.resumeCommand(for: makeChat("ok-id", .done, cwd: dir.path + "/missing")) == nil)
            #expect(TerminalJumper.resumeCommand(for: makeChat("x'; touch /tmp/pwned; '", .done, cwd: dir.path)) == nil)
            #expect(TerminalJumper.resumeCommand(for: makeChat("--dangerously-skip-permissions", .done, cwd: dir.path)) == nil)
            var chat = makeChat("ok-id", .done, cwd: dir.path)
            chat.configDir = dir.path + "/no-such-config"
            #expect(TerminalJumper.resumeCommand(for: chat) == nil)
        }
    }

    @Test func shellQuoteSurvivesHostileInput() throws {
        let hostile = #"a'b"c$(touch /tmp/x)`id`\n;|&"#
        let result = try runProcess("/bin/sh", ["-c", "printf '%s' \(TerminalJumper.shellQuote(hostile))"],
                                    environment: ["PATH": testPath])
        #expect(result.output == hostile)
    }
}
