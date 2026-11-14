import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var windows: WindowsController?
    private var server: EventServer?
    private var inbox: InboxWatcher?
    private let store = StateStore()
    private var housekeepingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let settings = AppSettings()
        let model = AppModel(settings: settings, geometry: .detect())
        self.model = model

        if arguments.contains("--mock") {
            // Моковые данные из дизайна — для проверки вёрстки. События и сохранение отключены.
            model.chats = MockData.chats(lang: settings.lang, now: model.now)
            model.account = MockData.account
        } else {
            model.chats = store.load()
            model.account = AccountReader.read(configDir: nil)
            model.accountConfigDir = AccountReader.defaultConfigDir
            model.housekeeping()
            model.onChatsChanged = { [weak self, weak model] in
                guard let self, let model else { return }
                self.store.save(model.chats)
            }
            startEvents(model)
        }

        let windows = WindowsController(model: model)
        windows.show()
        if arguments.contains("--open") { windows.openPanel() }
        self.windows = windows
    }

    private func startEvents(_ model: AppModel) {
        let deliver: (Data) -> Void = { [weak model] data in
            guard let event = HookEvent(data: data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { model?.apply(event) }
            }
        }

        let server = EventServer(onEvent: deliver)
        let port = ProcessInfo.processInfo.environment["BANGS_PORT"].flatMap(UInt16.init) ?? EventServer.defaultPort
        do {
            try server.start(port: port)
        } catch {
            NSLog("Bangs: не удалось открыть порт \(port): \(error). Работаем через папку inbox.")
        }
        self.server = server

        let inbox = InboxWatcher(directory: StateStore.directory.appendingPathComponent("inbox"), onEvent: { data in
            // InboxWatcher уже на главной очереди.
            if let event = HookEvent(data: data) { MainActor.assumeIsolated { model.apply(event) } }
        })
        inbox.start()
        self.inbox = inbox

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.housekeeping() }
        }
    }
}
