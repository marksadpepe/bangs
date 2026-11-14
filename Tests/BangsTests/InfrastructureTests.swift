import Foundation
import Testing
@testable import Bangs

@Suite("HTTP-сервер событий", .serialized)
struct EventServerTests {
    private func request(_ port: UInt16, _ method: String, _ path: String, body: Data? = nil) async throws -> (Int, String) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    private func startServer(_ collector: Collector) async throws -> (EventServer, UInt16) {
        let server = EventServer { collector.append($0) }
        let port = randomPort()
        try server.start(port: port)
        try await Task.sleep(for: .milliseconds(150))
        return (server, port)
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
