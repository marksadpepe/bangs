import Foundation

/// Сохраняет чаты между перезапусками приложения: ~/Library/Application Support/Bangs/state.json.
final class StateStore {
    static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Bangs", isDirectory: true)

    private let url: URL
    private var pending: DispatchWorkItem?

    init(url: URL = StateStore.directory.appendingPathComponent("state.json")) {
        self.url = url
    }

    func load() -> [Chat] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let chats = (try? decoder.decode([Chat].self, from: data)) ?? []
        // «Видел · ждёт ответа» больше не используется: чат ждёт, пока на него не ответят.
        return chats.map { chat in
            var chat = chat
            if chat.status == .waitSeen { chat.status = .waiting }
            return chat
        }
    }

    /// Пишет на диск не чаще раза в секунду.
    func save(_ chats: [Chat]) {
        pending?.cancel()
        let url = url
        let work = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard let data = try? encoder.encode(chats) else { return }
            try? FileManager.default.createDirectory(at: StateStore.directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        pending = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }
}
