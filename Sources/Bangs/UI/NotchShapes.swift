import SwiftUI

/// Силуэт чёлки/панели: верхний край прямой, сверху по бокам вогнутые «уши» радиуса `ear`,
/// снизу скругления `bottomRadius`. Ширина тела = ширина фигуры − 2·ear.
struct NotchSilhouette: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottomRadius) }
        set { ear = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let e = max(0, min(ear, rect.height, rect.width / 2))
        let r = max(0, min(bottomRadius, (rect.width - 2 * e) / 2, rect.height - e))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if e > 0 {
            p.addArc(center: CGPoint(x: rect.maxX, y: rect.minY + e), radius: e,
                     startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
        }
        p.addLine(to: CGPoint(x: rect.maxX - e, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - e - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + e + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + e + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + e, y: rect.minY + e))
        if e > 0 {
            p.addArc(center: CGPoint(x: rect.minX, y: rect.minY + e), radius: e,
                     startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        }
        p.closeSubpath()
        return p
    }
}

/// Тело чёлки без «ушей»: прямой верх, скруглённый низ.
struct NotchBody: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .circular)
            .path(in: rect)
    }
}
