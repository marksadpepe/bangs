import Foundation

/// Сохраняет чаты между перезапусками приложения: ~/Library/Application Support/Bangs/state.json.
final class StateStore {
    static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Bangs", isDirectory: true)

    private let url = StateStore.directory.appendingPathComponent("state.json")
    private var pending: DispatchWorkItem?

    func load() -> [Chat] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([Chat].self, from: data)) ?? []
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
