import Foundation

/// Запасной канал: notch-hook кладёт события файлами в inbox, если сервер недоступен.
/// Следим за папкой через DispatchSource и забираем файлы по порядку.
final class InboxWatcher {
    let directory: URL
    private let onEvent: (Data) -> Void
    private var source: DispatchSourceFileSystemObject?
    /// События старше этого возраста при запуске выбрасываем — состояние уже неактуально.
    private let maxAge: TimeInterval = 60 * 60

    init(directory: URL, onEvent: @escaping (Data) -> Void) {
        self.directory = directory
        self.onEvent = onEvent
    }

    func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        drain()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func drain() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let ready = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for url in ready {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if Date().timeIntervalSince(modified) < maxAge, let data = try? Data(contentsOf: url) {
                onEvent(data)
            }
            try? fm.removeItem(at: url)
        }
    }
}
