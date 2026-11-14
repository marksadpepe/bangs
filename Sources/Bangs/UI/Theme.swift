import SwiftUI

extension Color {
    /// `#RRGGBB` → Color (sRGB).
    init(hex: String, opacity: Double = 1) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Цвета темы из `renderVals()` → `T`.
struct Palette {
    let isDark: Bool
    let panel, island, line, text, muted, dim, code: Color
    let seenTitle, seenRing, working, seg, segOn: Color
    /// Скругление светлого тела панели под чёрной полосой.
    let bodyTopRadius: CGFloat

    /// Цвета верхней полосы: она всегда чёрная, независимо от темы.
    static let headerText = Color(hex: "#c9c9ce")
    static let headerMuted = Color(hex: "#9a9aa1")
    static let headerDim = Color(hex: "#6a6a70")
    static let headerButton = Color(hex: "#1a1a1d")

    static let dark = Palette(
        isDark: true,
        panel: .black, island: Color(hex: "#131315"), line: Color(hex: "#232327"),
        text: Color(hex: "#f2f2f4"), muted: Color(hex: "#9a9aa1"), dim: Color(hex: "#6a6a70"),
        code: Color(hex: "#1d1d21"), seenTitle: Color(hex: "#a8a8ae"), seenRing: Color(hex: "#55555c"),
        working: Color(hex: "#8E8E93"), seg: Color(hex: "#1e1e22"), segOn: Color(hex: "#3a3a40"),
        bodyTopRadius: 0)

    static let light = Palette(
        isDark: false,
        panel: Color(hex: "#f2f2f5"), island: .white, line: Color(hex: "#e2e2e7"),
        text: Color(hex: "#1c1c1e"), muted: Color(hex: "#5f5f66"), dim: Color(hex: "#8a8a90"),
        code: Color(hex: "#f0f0f3"), seenTitle: Color(hex: "#6b6b72"), seenRing: Color(hex: "#a0a0a7"),
        working: Color(hex: "#8E8E93"), seg: Color(hex: "#e9e9ee"), segOn: .white,
        bodyTopRadius: 18)
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Карточка-«островок»: фон, скругление 14, тонкая обводка.
    func island(_ pal: Palette, border: Color? = nil) -> some View {
        background(pal.island, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(border ?? pal.line, lineWidth: 1))
    }
}

/// Кнопка с фоном и подсветкой при наведении.
struct SurfaceButtonStyle: ButtonStyle {
    var background: Color = .clear
    var hover: Color = .clear
    var cornerRadius: CGFloat = 8
    var border: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, style: self)
    }

    private struct Surface: View {
        let configuration: Configuration
        let style: SurfaceButtonStyle
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            configuration.label
                .background {
                    ZStack {
                        shape.fill(style.background)
                        shape.fill(style.hover).opacity(hovering ? 1 : 0)
                    }
                }
                .overlay {
                    if let border = style.border { shape.strokeBorder(border, lineWidth: 1) }
                }
                .contentShape(shape)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { hovering = $0 }
        }
    }
}
