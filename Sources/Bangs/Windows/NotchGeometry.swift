import AppKit

/// Где находится чёлка и какого она размера.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    static let ear: CGFloat = 12
    static let panelBodyWidth: CGFloat = 528
    static let panelWidth: CGFloat = panelBodyWidth + 2 * ear
    static let closedRadius: CGFloat = 14
    static let openRadius: CGFloat = 24
    /// Ширина пилюли, если чёлки нет (внешний монитор).
    static let pillWidth: CGFloat = 196

    /// На сколько чёрная форма выходит за вырез с каждой стороны, когда показан счётчик:
    /// внутри самого выреза пикселей нет, поэтому счётчик ставим справа от камеры.
    var extensionWidth: CGFloat { hasNotch ? 40 : 0 }
    var headerHeight: CGFloat { max(32, notchHeight) }

    func closedBodyWidth(active: Bool) -> CGFloat {
        active ? notchWidth + 2 * extensionWidth : notchWidth
    }

    /// Обычная чёлка без подсветки выглядит как родная — без «ушей». Пилюля на внешнем экране — всегда с ними.
    func closedEar(active: Bool) -> CGFloat {
        (active || !hasNotch) ? Self.ear : 0
    }

    /// Экран с чёлкой, иначе главный экран (с меню).
    @MainActor
    static func detect() -> NotchGeometry {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screens.first else {
            return .preview
        }
        let frame = screen.frame
        let top = screen.safeAreaInsets.top
        if top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = frame.width - left - right
            return NotchGeometry(screenFrame: frame, hasNotch: true,
                                 notchWidth: width > 0 && width < frame.width ? width : 185,
                                 notchHeight: top)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(screenFrame: frame, hasNotch: false,
                             notchWidth: pillWidth, notchHeight: menuBar > 0 ? menuBar : 24)
    }

    /// MacBook Air 13" при стандартном разрешении — для превью.
    static let preview = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                       hasNotch: true, notchWidth: 185, notchHeight: 32)
}
