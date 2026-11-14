import AppKit
import SwiftUI

/// Прозрачная панель поверх всего, на всех Spaces и в полноэкранном режиме.
final class OverlayPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // тень рисуем сами
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    // Не даём AppKit сдвигать окно ниже строки меню.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Первый клик по неактивному окну сразу срабатывает как нажатие.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Два окна: маленькое — закрытая чёлка, большое — панель (показывается только когда открыта).
/// Клики вне чёлки/панели проходят насквозь: `ignoresMouseEvents` переключается по положению курсора.
@MainActor
final class WindowsController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let notchPanel = OverlayPanel()
    private let mainPanel = OverlayPanel()
    private var monitors: [Any] = []
    private var clock: Timer?
    private var closeToken = 0
    /// До этого момента потеря фокуса не закрывает панель (Terminal активируется по клику в списке).
    private var keepOpenUntil = Date.distantPast

    private static let glowMargin: CGFloat = 40
    private static let shadowMargin: CGFloat = 60

    init(model: AppModel) {
        self.model = model
        super.init()

        mainPanel.allowsKey = true
        mainPanel.delegate = self

        let notchView = FirstMouseHostingView(rootView: ClosedNotchView(model: model) { [weak self] in
            self?.openPanel()
        })
        notchView.sizingOptions = []
        notchPanel.contentView = notchView

        let panelView = FirstMouseHostingView(rootView: PanelRoot(model: model))
        panelView.sizingOptions = []
        mainPanel.contentView = panelView

        model.onRequestClose = { [weak self] in self?.closePanel() }
        model.onOpenTerminal = { [weak self] chat in
            self?.closePanel()
            // Даём панели начать закрываться, затем переключаем Terminal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated { _ = TerminalJumper.open(chat) }
            }
        }
        model.onRevealTerminal = { [weak self] chat in
            guard let self else { return }
            self.keepOpenUntil = Date().addingTimeInterval(1.5)
            _ = TerminalJumper.open(chat)
            // Terminal стал активным — возвращаем фокус панели, чтобы работали Esc и клики.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.assumeIsolated {
                    guard self.model.isOpen else { return }
                    self.mainPanel.orderFrontRegardless()
                    self.mainPanel.makeKey()
                }
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        installMonitors()
    }

    func show() {
        layout()
        notchPanel.orderFrontRegardless()
        updateMouseRouting()
    }

    // MARK: - Раскрытие / закрытие

    func togglePanel() {
        model.isOpen ? closePanel() : openPanel()
    }

    func openPanel() {
        guard !model.isOpen else { return }
        keepOpenUntil = .distantPast
        closeToken += 1  // отменяет незавершённое закрытие
        model.prepareOpen()
        model.panelVisible = true
        mainPanel.ignoresMouseEvents = false
        mainPanel.orderFrontRegardless()
        mainPanel.makeKey()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.18)) {
            model.isOpen = true
        }
        clock = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.now = Date() }
        }
    }

    func closePanel() {
        guard model.isOpen else { return }
        model.didClose()
        clock?.invalidate()
        clock = nil
        closeToken += 1
        let token = closeToken
        let finish = { [weak self] in
            guard let self, self.closeToken == token else { return }
            self.model.panelVisible = false
            self.mainPanel.orderOut(nil)
            self.updateMouseRouting()
        }
        if reduceMotion {
            model.isOpen = false
            finish()
        } else {
            withAnimation(.spring(duration: 0.22, bounce: 0)) {
                model.isOpen = false
            } completion: {
                finish()
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Фокус ушёл в Terminal из-за клика по чату — панель остаётся.
        guard Date() >= keepOpenUntil else { return }
        closePanel()
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: - Расположение

    @objc private func screensChanged() {
        model.geometry = .detect()
        layout()
    }

    private func layout() {
        let g = model.geometry
        let f = g.screenFrame
        let nw = g.notchWidth + 2 * g.extensionWidth + 2 * NotchGeometry.ear + 2 * Self.glowMargin
        let nh = g.notchHeight + Self.glowMargin
        notchPanel.setFrame(CGRect(x: f.midX - nw / 2, y: f.maxY - nh, width: nw, height: nh), display: true)

        let pw = NotchGeometry.panelWidth + 2 * Self.shadowMargin
        let ph = floor(f.height * 0.9)
        mainPanel.setFrame(CGRect(x: f.midX - pw / 2, y: f.maxY - ph, width: pw, height: ph), display: true)
    }

    // MARK: - Мышь и клавиатура

    /// Тело закрытой чёлки в координатах экрана (+1 pt сверху, чтобы ловить самый край).
    private var closedHitRect: CGRect {
        let g = model.geometry
        let w = g.closedBodyWidth(active: model.indicator.isActive)
        return CGRect(x: g.screenFrame.midX - w / 2, y: g.screenFrame.maxY - g.notchHeight,
                      width: w, height: g.notchHeight + 1)
    }

    /// Панель в координатах экрана.
    private var openHitRect: CGRect {
        let r = model.panelFrame
        let wf = mainPanel.frame
        return CGRect(x: wf.minX + r.minX, y: wf.maxY - r.maxY, width: r.width, height: r.height + 1)
    }

    private func updateMouseRouting() {
        let p = NSEvent.mouseLocation
        if model.panelVisible {
            notchPanel.ignoresMouseEvents = true
            mainPanel.ignoresMouseEvents = !openHitRect.contains(p)
        } else {
            mainPanel.ignoresMouseEvents = true
            notchPanel.ignoresMouseEvents = !closedHitRect.contains(p)
        }
    }

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseRouting() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateMouseRouting() }
            return event
        }) { monitors.append(m) }

        // Клик в другом приложении — закрыть панель.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.isOpen else { return }
                if !self.openHitRect.contains(NSEvent.mouseLocation) { self.closePanel() }
            }
        }) { monitors.append(m) }

        // Esc — закрыть панель.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.model.isOpen else { return false }
                self.closePanel()
                return true
            }
            return handled ? nil : event
        }) { monitors.append(m) }
    }
}
