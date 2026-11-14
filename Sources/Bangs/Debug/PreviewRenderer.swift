import AppKit
import SwiftUI

/// Рендер экранов в PNG через ImageRenderer — чтобы проверять вёрстку без Xcode и без запуска окна.
@MainActor
enum PreviewRenderer {
    static func renderAll(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func model(_ theme: ThemeMode = .dark, _ lang: Lang = .ru, _ screen: PanelScreen = .list,
                   geometry: NotchGeometry = .preview, edit: (AppModel) -> Void = { _ in }) -> AppModel {
            let settings = AppSettings(defaults: nil)
            settings.theme = theme
            settings.lang = lang
            let m = AppModel(settings: settings, geometry: geometry)
            m.chats = MockData.chats(lang: lang, now: m.now)
            m.account = MockData.account
            m.screen = screen
            edit(m)
            return m
        }

        let shots: [(String, AnyView)] = [
            ("closed-quiet", AnyView(ClosedScene(model: model { m in
                for id in ["a1", "b1"] { m.setStatus(id, .seen) }
                for id in ["b2", "c2"] { m.setStatus(id, .working) }
            }))),
            ("closed-done", AnyView(ClosedScene(model: model()))),
            ("closed-waiting", AnyView(ClosedScene(model: model { m in
                for id in ["a1", "b1"] { m.setStatus(id, .seen) }
            }))),
            ("closed-pill-external", AnyView(ClosedScene(model: model(geometry: NotchGeometry(
                screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), hasNotch: false,
                notchWidth: NotchGeometry.pillWidth, notchHeight: 24))))),
            ("panel-list-dark-ru", AnyView(PanelScene(model: model()))),
            ("panel-list-light-ru", AnyView(PanelScene(model: model(.light)))),
            ("panel-list-dark-en", AnyView(PanelScene(model: model(.dark, .en)))),
            ("panel-detail-permission", AnyView(PanelScene(model: model(.dark, .ru, .detail("b2"))))),
            ("panel-detail-question-light", AnyView(PanelScene(model: model(.light, .ru, .detail("c2"))))),
            ("panel-settings", AnyView(PanelScene(model: model(.dark, .ru, .settings)))),
            ("panel-empty", AnyView(PanelScene(model: model { $0.chats = [] }))),
            ("panel-list-light-en", AnyView(PanelScene(model: model(.light, .en)))),
            ("panel-detail-permission-en", AnyView(PanelScene(model: model(.dark, .en, .detail("b2"))))),
            ("panel-detail-question-light-en", AnyView(PanelScene(model: model(.light, .en, .detail("c2"))))),
            ("panel-settings-en", AnyView(PanelScene(model: model(.dark, .en, .settings)))),
        ]

        // Настоящее окно: так рисуется прокручиваемый список (ImageRenderer не умеет NSScrollView).
        snapshot(LiveScene(model: model(.dark, .en)), name: "live-list", in: dir)
        let statuses: [ChatStatus] = [.done, .waiting, .working]
        let long = model(.dark, .en)
        long.chats = (0..<14).map { (i: Int) -> Chat in
            makeDemoChat("long\(i)", statuses[i % 3], project: "project-\(i / 2)",
                         now: long.now, minutes: Double(i))
        }
        snapshot(LiveScene(model: long), name: "live-list-long", in: dir)

        for (name, view) in shots {
            let renderer = ImageRenderer(content: view.environment(\.staticRendering, true))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("✗ \(name)")
                continue
            }
            let url = dir.appendingPathComponent(name + ".png")
            try? png.write(to: url)
            print("✓ \(url.path)")
        }
    }
}

extension PreviewRenderer {
    static func makeDemoChat(_ id: String, _ status: ChatStatus, project: String, now: Date, minutes: Double) -> Chat {
        Chat(id: id, title: "Demo task \(id)", cwd: NSHomeDirectory() + "/work/" + project,
             status: status, statusSince: now.addingTimeInterval(-minutes * 60))
    }

    /// Снимок вида в окне вне экрана (cacheDisplay) — с прокруткой и настоящей вёрсткой AppKit.
    static func snapshot<V: View>(_ view: V, name: String, in dir: URL) {
        let size = CGSize(width: 700, height: 760)
        let host = NSHostingView(rootView: view.environment(\.staticRendering, true))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("✗ \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = dir.appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("✓ \(url.path)")
    }
}

/// Панель как в приложении: прокручиваемый список, прижатый к верху окна.
private struct LiveScene: View {
    let model: AppModel
    var body: some View {
        PanelView(model: model, scrollable: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(hex: "#1c1c1f"))
    }
}

/// Кусок «рабочего стола» со строкой меню — фон для превью.
private struct Desk<Content: View>: View {
    let menuBarHeight: CGFloat
    let content: Content

    var body: some View {
        content.background(alignment: .top) {
            ZStack(alignment: .top) {
                Color(hex: "#1c1c1f")
                Color(hex: "#141416").frame(height: menuBarHeight)
            }
        }
    }
}

private struct ClosedScene: View {
    let model: AppModel
    var body: some View {
        Desk(menuBarHeight: model.geometry.notchHeight,
             content: ClosedNotchView(model: model).frame(width: 460, height: 110))
    }
}

private struct PanelScene: View {
    let model: AppModel
    var body: some View {
        Desk(menuBarHeight: model.geometry.notchHeight,
             content: PanelView(model: model, scrollable: false)
                .padding(.horizontal, 50)
                .padding(.bottom, 70))
    }
}
