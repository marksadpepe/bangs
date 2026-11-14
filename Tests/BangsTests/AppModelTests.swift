import Foundation
import Testing
@testable import Bangs

@Suite("Модель панели")
struct AppModelTests {
    // MARK: - Индикатор чёлки

    @Test func quietWhenNothingNeedsAttention() {
        let m = makeModel()
        m.chats = [makeChat("a", .working), makeChat("b", .seen), makeChat("c", .waitSeen), makeChat("d", .denied)]
        #expect(m.indicator == .quiet)
        #expect(!m.indicator.isActive)
    }

    @Test func doneTakesPrecedenceOverWaiting() {
        let m = makeModel()
        m.chats = [makeChat("a", .done), makeChat("b", .waiting), makeChat("c", .done)]
        #expect(m.indicator == .done(2))
    }

    @Test func waitingCountsOnlyNewWaits() {
        let m = makeModel()
        m.chats = [makeChat("a", .waiting), makeChat("b", .waitSeen), makeChat("c", .waiting)]
        #expect(m.indicator == .waiting(2))
    }

    @Test func hiddenChatsDoNotLightTheNotch() {
        let m = makeModel()
        m.chats = [makeChat("a", .done, title: "")]
        #expect(m.indicator == .quiet)
        #expect(m.doneCount == 0)
    }

    // MARK: - Порядок и группировка

    @Test func ordersByAttentionThenRecency() {
        let now = Date()
        let m = makeModel()
        m.chats = [
            makeChat("seen", .seen, since: now),
            makeChat("work", .working, since: now),
            makeChat("waitOld", .waiting, since: now.addingTimeInterval(-600)),
            makeChat("doneOld", .done, since: now.addingTimeInterval(-300)),
            makeChat("waitNew", .waiting, since: now.addingTimeInterval(-60)),
            makeChat("waitSeen", .waitSeen, since: now),
            makeChat("doneNew", .done, since: now.addingTimeInterval(-30)),
        ]
        #expect(m.orderedChats.map(\.id) == ["doneNew", "doneOld", "waitNew", "waitOld", "waitSeen", "work", "seen"])
    }

    @Test func groupsIntoProjectsInOrderOfFirstAppearance() {
        let m = makeModel(lang: .ru)
        m.chats = MockData.chats(lang: .ru, now: m.now)
        let projects = m.projects
        #expect(projects.map(\.name) == ["api-server", "landing", "dotfiles"])
        #expect(projects[0].chats.map(\.id) == ["a1", "a2"])
        #expect(projects[1].chats.map(\.id) == ["b1", "b2"])
        #expect(projects[2].chats.map(\.id) == ["c2", "c1"])
        #expect(projects[2].displayPath == "~/dotfiles")
    }

    @Test func orderIsFrozenWhilePanelIsOpen() {
        let m = makeModel()
        m.chats = [makeChat("a", .done), makeChat("b", .working)]
        m.prepareOpen()
        #expect(m.orderedChats.map(\.id) == ["a", "b"])

        m.setStatus("a", .seen)  // без заморозки «a» уехал бы вниз
        m.chats.append(makeChat("c", .done))
        #expect(m.orderedChats.map(\.id) == ["a", "b", "c"])

        m.didClose()
        #expect(m.orderedChats.map(\.id) == ["c", "b", "a"])
    }

    // MARK: - Действия

    @Test func tapDoneMarksSeen() {
        let m = makeModel()
        m.chats = [makeChat("a", .done)]
        m.tap(m.chats[0])
        #expect(m.chat("a")?.status == .seen)
        #expect(m.screen == .list)
    }

    @Test func tapWaitingOpensDetail() {
        for status in [ChatStatus.waiting, .waitSeen, .denied] {
            let m = makeModel()
            m.chats = [makeChat("a", status)]
            m.tap(m.chats[0])
            #expect(m.screen == .detail("a"))
            #expect(m.chat("a")?.status == status)
        }
    }

    @Test func tapRevealsTerminalOnlyWhenEnabled() {
        var revealed: [String] = []
        let on = makeModel(jumpOnClick: true)
        on.onRevealTerminal = { revealed.append($0.id) }
        on.chats = [makeChat("done", .done), makeChat("work", .working), makeChat("wait", .waiting)]
        for c in on.chats { on.tap(c) }
        #expect(revealed == ["done", "work"])

        revealed = []
        let off = makeModel(jumpOnClick: false)
        off.onRevealTerminal = { revealed.append($0.id) }
        off.chats = [makeChat("done", .done)]
        off.tap(off.chats[0])
        #expect(revealed.isEmpty)
    }

    /// Регрессия: клик по одному из нескольких готовых чатов закрывал панель.
    @Test func tappingDoneChatsKeepsPanelOpen() {
        var closeRequests = 0, closingJumps = 0
        let m = makeModel(jumpOnClick: true)
        m.onRequestClose = { closeRequests += 1 }
        m.onOpenTerminal = { _ in closingJumps += 1 }
        m.onRevealTerminal = { _ in }
        m.chats = [makeChat("a", .done), makeChat("b", .done), makeChat("c", .done)]
        m.prepareOpen()
        let orderAtOpen = m.orderedChats.map(\.id)

        m.tap(m.chats[0])
        #expect(m.indicator == .done(2))
        m.tap(m.chats[1])
        m.tap(m.chats[2])

        #expect(closeRequests == 0)
        #expect(closingJumps == 0)
        #expect(m.chats.allSatisfy { $0.status == .seen })
        #expect(m.screen == .list)
        #expect(m.orderedChats.map(\.id) == orderAtOpen, "строки не прыгают")
    }

    @Test func leavingDetailMarksWaitSeenAndKeepsWaitingTime() throws {
        let since = Date().addingTimeInterval(-300)
        let m = makeModel()
        m.chats = [makeChat("a", .waiting, since: since)]
        m.tap(m.chats[0])
        m.leaveDetail()
        let c = try #require(m.chat("a"))
        #expect(c.status == .waitSeen)
        #expect(c.statusSince == since)
        #expect(m.screen == .list)
    }

    @Test func leavingDetailKeepsDenied() {
        let m = makeModel()
        m.chats = [makeChat("a", .denied)]
        m.tap(m.chats[0])
        m.leaveDetail()
        #expect(m.chat("a")?.status == .denied)
    }

    @Test func closingPanelFromDetailMarksWaitSeen() {
        let m = makeModel()
        m.chats = [makeChat("a", .waiting)]
        m.prepareOpen()
        m.tap(m.chats[0])
        m.didClose()
        #expect(m.chat("a")?.status == .waitSeen)
    }

    @Test func openInTerminalMarksWaitSeenAndCallsBack() {
        var opened: String?
        let m = makeModel()
        m.onOpenTerminal = { opened = $0.id }
        m.chats = [makeChat("a", .waiting)]
        m.openInTerminal("a")
        #expect(m.chat("a")?.status == .waitSeen)
        #expect(opened == "a")
    }

    @Test func markAllSeenOnlyTouchesDone() {
        let m = makeModel()
        m.chats = [makeChat("a", .done), makeChat("b", .waiting), makeChat("c", .done), makeChat("d", .working)]
        m.markAllSeen()
        #expect(m.chats.map(\.status) == [.seen, .waiting, .seen, .working])
    }

    @Test func toggleSettings() {
        let m = makeModel()
        m.toggleSettings()
        #expect(m.screen == .settings)
        m.toggleSettings()
        #expect(m.screen == .list)
    }

    @Test func prepareOpenResetsScreen() {
        let m = makeModel()
        m.screen = .settings
        m.prepareOpen()
        #expect(m.screen == .list)
    }

    // MARK: - Тексты

    @Test func metaTexts() {
        let m = makeModel(lang: .en)
        let now = m.now
        func meta(_ status: ChatStatus, _ minutes: Double) -> String {
            m.meta(for: makeChat("x", status, since: now.addingTimeInterval(-minutes * 60)))
        }
        #expect(meta(.done, 4) == "4 min ago")
        #expect(meta(.done, 0.2) == "just now")
        #expect(meta(.done, 125) == "2 h ago")
        #expect(meta(.working, 6) == "working · 6 min")
        #expect(meta(.working, 0) == "working · just now")
        #expect(meta(.waiting, 3) == "waiting 3 min")
        #expect(meta(.waitSeen, 3) == "seen · still waiting")
        #expect(meta(.denied, 3) == "denied · reply in terminal")
        #expect(meta(.seen, 3) == "seen")
    }

    @Test func russianMetaTexts() {
        let m = makeModel(lang: .ru)
        let chat = makeChat("x", .done, since: m.now.addingTimeInterval(-60))
        #expect(m.meta(for: chat) == "1 мин назад")
        #expect(m.meta(for: makeChat("y", .waiting, since: m.now.addingTimeInterval(-180))) == "ждёт 3 мин")
    }

    @Test func projectSummary() {
        let m = makeModel(lang: .en)
        let busy = Project(cwd: "/p", chats: [
            makeChat("a", .done), makeChat("b", .waiting), makeChat("c", .waitSeen), makeChat("d", .working),
        ])
        #expect(m.summary(for: busy) == "1 done · 2 waiting · 1 running")
        #expect(m.summary(for: Project(cwd: "/p", chats: [makeChat("a", .seen)])) == "quiet")
    }

    @Test func durationSwitchesToHours() {
        #expect(Strings.en.duration(59) == "59 min")
        #expect(Strings.en.duration(60) == "1 h")
        #expect(Strings.ru.duration(150) == "2 ч")
    }

    @Test func projectPathAbbreviation() {
        let home = NSHomeDirectory()
        #expect(Project.abbreviate(home) == "~")
        #expect(Project.abbreviate(home + "/work/app") == "~/work/app")
        #expect(Project.abbreviate("/opt/thing") == "/opt/thing")
        #expect(Project.abbreviate(home + "x/other") == home + "x/other")
        #expect(Project(cwd: "/a/b/landing", chats: []).name == "landing")
    }
}

@Suite("Статусы")
struct ChatStatusTests {
    @Test func waitingFamily() {
        #expect(ChatStatus.waiting.isWaiting)
        #expect(ChatStatus.waitSeen.isWaiting)
        #expect(ChatStatus.denied.isWaiting)
        #expect(!ChatStatus.done.isWaiting)
        #expect(!ChatStatus.working.isWaiting)
        #expect(!ChatStatus.seen.isWaiting)
    }

    @Test func statusTimeResetsOutsideWaitingFamily() {
        let t0 = Date(timeIntervalSince1970: 1000), t1 = Date(timeIntervalSince1970: 2000)
        var c = makeChat("a", .waiting, since: t0)
        c.setStatus(.waitSeen, at: t1)
        #expect(c.statusSince == t0)
        c.setStatus(.working, at: t1)
        #expect(c.statusSince == t1)
        c.setStatus(.working, at: Date(timeIntervalSince1970: 3000))
        #expect(c.statusSince == t1, "тот же статус — время не меняется")
    }

    @Test func chatRoundTripsThroughJSON() throws {
        var c = makeChat("a", .waiting, since: Date(timeIntervalSince1970: 1_700_000_000))
        c.tty = "/dev/ttys001"
        c.claudePid = 42
        c.request = PendingRequest(kind: .permission, command: "ls", toolName: "Bash", allowAlways: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let back = try decoder.decode(Chat.self, from: encoder.encode(c))
        #expect(back == c)
    }
}
