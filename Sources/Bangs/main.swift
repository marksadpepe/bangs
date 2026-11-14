import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments

// `Bangs --render-previews <папка>` — отрисовать экраны в PNG и выйти (замена превью Xcode).
if let i = arguments.firstIndex(of: "--render-previews") {
    let dir = i + 1 < arguments.count ? arguments[i + 1] : "previews"
    MainActor.assumeIsolated { PreviewRenderer.renderAll(to: URL(fileURLWithPath: dir)) }
    exit(0)
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
