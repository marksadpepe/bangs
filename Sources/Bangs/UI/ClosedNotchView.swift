import SwiftUI

/// Закрытая чёлка (States.dc.html): тихо / свечение «готово» / контур «ждёт».
struct ClosedNotchView: View {
    let model: AppModel
    var onTap: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticRendering) private var staticRendering

    var body: some View {
        let animate = !reduceMotion && !staticRendering
        let g = model.geometry
        let indicator = model.indicator
        let active = indicator.isActive
        let bodyWidth = g.closedBodyWidth(active: active)
        let ear = g.closedEar(active: active)

        ZStack(alignment: .top) {
            switch indicator {
            case .done:
                DoneGlow(color: model.doneColor, width: bodyWidth, height: g.notchHeight, animated: animate)
            case .waiting:
                NotchGlow(color: model.waitColor, width: bodyWidth, height: g.notchHeight,
                          ring: 0.85, glow: 0.35, blur: 20, y: 6, spread: 2)
            case .quiet:
                EmptyView()
            }

            NotchSilhouette(ear: ear, bottomRadius: NotchGeometry.closedRadius)
                .fill(Color.black)
                .frame(width: bodyWidth + 2 * ear, height: g.notchHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(model.strings.openPanel)

            Group {
                switch indicator {
                case .done(let n): NotchCounter(count: n, color: model.doneColor, blink: false)
                case .waiting(let n): NotchCounter(count: n, color: model.waitColor, blink: animate)
                case .quiet: EmptyView()
                }
            }
            .padding(.trailing, 12)
            .frame(width: bodyWidth, height: g.notchHeight, alignment: .trailing)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(model.panelVisible ? 0 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.2), value: active)
    }
}

/// Счётчик справа от камеры: точка + число.
private struct NotchCounter: View {
    let count: Int
    let color: Color
    let blink: Bool
    @State private var dim = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)").font(.ui(11, .semibold)).monospacedDigit()
        }
        .foregroundStyle(color)
        .opacity(dim ? 0.25 : 1)
        .onAppear {
            guard blink else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

/// Пульсирующее свечение «готово» (CSS @keyframes glow, 2.4 с).
private struct DoneGlow: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let animated: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        let p = phase
        NotchGlow(color: color, width: width, height: height,
                  ring: 0.9 - 0.3 * p, glow: 0.45 - 0.2 * p,
                  blur: 22 - 10 * p, y: 6 - 2 * p, spread: 2 - 2 * p)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { phase = 1 }
            }
    }
}

/// Аналог CSS `box-shadow: 0 0 0 1.5px ring, 0 y blur spread glow` для тела чёлки.
struct NotchGlow: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let ring: Double
    let glow: Double
    let blur: CGFloat
    let y: CGFloat
    let spread: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            NotchBody(radius: NotchGeometry.closedRadius + spread)
                .fill(color.opacity(glow))
                .frame(width: width + 2 * spread, height: height + spread)
                .blur(radius: blur / 2)
                .offset(y: y)
            NotchBody(radius: NotchGeometry.closedRadius + 1.5)
                .fill(color.opacity(ring))
                .frame(width: width + 3, height: height + 1.5)
        }
    }
}
