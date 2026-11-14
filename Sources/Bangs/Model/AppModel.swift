import Foundation
import Observation
import SwiftUI

enum PanelScreen: Equatable {
    case list
    case detail(String)
    case settings
}

enum NotchIndicator: Equatable {
    case quiet
    case done(Int)     // есть непросмотренные завершённые чаты
    case waiting(Int)  // есть чаты, которые ждут ответа (и нет «готово»)

    var isActive: Bool { self != .quiet }
}

/// Всё состояние приложения: чаты, панель, настройки.
@Observable
final class AppModel {
    let settings: AppSettings
    var chats: [Chat] = [] {
        didSet { onChatsChanged?() }
    }
    var account: Account?
    var geometry: NotchGeometry
    var screen: PanelScreen = .list
    /// Панель раскрыта (меняется внутри withAnimation — управляет анимацией).
    var isOpen = false
    /// Окно панели на экране, включая время анимации закрытия.
    var panelVisible = false
    /// «Сейчас» для относительного времени; обновляется, пока панель открыта.
    var now = Date()

    @ObservationIgnored var panelFrame: CGRect = .zero
    @ObservationIgnored var onRequestClose: (() -> Void)?
    @ObservationIgnored var onOpenTerminal: ((Chat) -> Void)?
    @ObservationIgnored var onChatsChanged: (() -> Void)?
    /// Каталог конфигурации, из которого прочитан текущий аккаунт.
    @ObservationIgnored var accountConfigDir: String?
    /// Порядок строк, зафиксированный при открытии панели, чтобы строки не прыгали под курсором.
    @ObservationIgnored private var frozenOrder: [String: Int]?

    init(settings: AppSettings, geometry: NotchGeometry) {
        self.settings = settings
        self.geometry = geometry
    }

    // MARK: - Оформление

    var palette: Palette { settings.theme == .dark ? .dark : .light }
    var strings: Strings { settings.lang == .ru ? .ru : .en }
    var doneColor: Color { Color(hex: settings.doneColor) }
    var waitColor: Color { Color(hex: settings.waitColor) }
    var maxListHeight: CGFloat { max(240, geometry.screenFrame.height * 0.6) }

    // MARK: - Производные данные

    /// Чаты, которые показываются в панели (у которых уже есть первое сообщение).
    var visibleChats: [Chat] { chats.filter(\.isVisible) }

    var doneCount: Int { visibleChats.filter { $0.status == .done }.count }

    var indicator: NotchIndicator {
        let done = doneCount
        if done > 0 { return .done(done) }
        let waiting = visibleChats.filter { $0.status == .waiting }.count
        if waiting > 0 { return .waiting(waiting) }
        return .quiet
    }

    var orderedChats: [Chat] {
        let frozen = frozenOrder
        return visibleChats.sorted { a, b in
            if let frozen {
                let ia = frozen[a.id] ?? Int.max, ib = frozen[b.id] ?? Int.max
                if ia != ib { return ia < ib }
            }
            if a.status.rank != b.status.rank { return a.status.rank < b.status.rank }
            return a.statusSince > b.statusSince
        }
    }

    /// Островки в порядке первого появления в отсортированном списке чатов.
    var projects: [Project] {
        var order: [String] = []
        var groups: [String: [Chat]] = [:]
        for chat in orderedChats {
            if groups[chat.cwd] == nil { order.append(chat.cwd) }
            groups[chat.cwd, default: []].append(chat)
        }
        return order.map { Project(cwd: $0, chats: groups[$0] ?? []) }
    }

    func chat(_ id: String) -> Chat? { chats.first { $0.id == id } }

    // MARK: - Тексты

    func minutes(since date: Date) -> Int { max(0, Int(now.timeIntervalSince(date) / 60)) }

    func meta(for chat: Chat) -> String {
        let s = strings
        let m = minutes(since: chat.statusSince)
        switch chat.status {
        case .done: return m < 1 ? s.justNow : s.duration(m) + s.ago
        case .working: return m < 1 ? s.workingJustNow : s.working + " · " + s.duration(m)
        case .waiting: return waitingFor(chat)
        case .waitSeen: return s.waitSeen
        case .denied: return s.denied
        case .seen: return s.seen
        }
    }

    func waitingFor(_ chat: Chat) -> String {
        let m = minutes(since: chat.statusSince)
        return m < 1 ? strings.waitingJustNow : strings.waits + strings.duration(m)
    }

    func summary(for project: Project) -> String {
        let s = strings
        var done = 0, wait = 0, work = 0
        for chat in project.chats {
            switch chat.status {
            case .done: done += 1
            case .waiting, .waitSeen, .denied: wait += 1
            case .working: work += 1
            case .seen: break
            }
        }
        var parts: [String] = []
        if done > 0 { parts.append("\(done)\(s.nDone)") }
        if wait > 0 { parts.append("\(wait)\(s.nWait)") }
        if work > 0 { parts.append("\(work)\(s.nWork)") }
        return parts.isEmpty ? s.quiet : parts.joined(separator: " · ")
    }

    // MARK: - Действия

    func prepareOpen() {
        now = Date()
        screen = .list
        frozenOrder = nil
        frozenOrder = Dictionary(uniqueKeysWithValues: orderedChats.enumerated().map { ($1.id, $0) })
    }

    func didClose() {
        if case .detail(let id) = screen { markLeftDetail(id) }
        frozenOrder = nil
    }

    func tap(_ chat: Chat) {
        if chat.status.isWaiting {
            screen = .detail(chat.id)
            return
        }
        if chat.status == .done { setStatus(chat.id, .seen) }
        if settings.jumpOnClick { onOpenTerminal?(chat) }
    }

    /// «Назад» с экрана чата: ожидающий чат становится «видел», а не «просмотрен».
    func leaveDetail() {
        guard case .detail(let id) = screen else { return }
        markLeftDetail(id)
        screen = .list
    }

    func openInTerminal(_ id: String) {
        markLeftDetail(id)
        if let chat = chat(id) { onOpenTerminal?(chat) }
    }

    func toggleSettings() {
        screen = screen == .settings ? .list : .settings
    }

    func markAllSeen() {
        for i in chats.indices where chats[i].status == .done {
            chats[i].status = .seen
            chats[i].statusSince = Date()
        }
    }

    func setStatus(_ id: String, _ status: ChatStatus) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[i].setStatus(status)
    }

    private func markLeftDetail(_ id: String) {
        if chat(id)?.status == .waiting { setStatus(id, .waitSeen) }
    }
}
