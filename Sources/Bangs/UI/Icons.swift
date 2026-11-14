import SwiftUI

/// Иконки из SVG дизайна, перенесённые в Path (координаты — в единицах viewBox).
enum IconKind {
    case asterisk, chevronUp, chevronRight, chevronLeft, arrowUpRight, moon, sun, sliders

    var viewBox: CGFloat {
        switch self {
        case .asterisk: 14
        case .chevronUp, .chevronRight, .chevronLeft, .arrowUpRight: 12
        case .moon, .sun, .sliders: 16
        }
    }
}

struct Icon: View {
    let kind: IconKind
    var size: CGFloat
    var lineWidth: CGFloat = 1.6

    init(_ kind: IconKind, size: CGFloat, lineWidth: CGFloat = 1.6) {
        self.kind = kind
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        IconShape(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: lineWidth * size / kind.viewBox, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

struct IconShape: Shape {
    let kind: IconKind

    func path(in rect: CGRect) -> Path {
        let s = rect.width / kind.viewBox
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        func line(_ pts: (CGFloat, CGFloat)...) {
            guard let first = pts.first else { return }
            p.move(to: pt(first.0, first.1))
            for q in pts.dropFirst() { p.addLine(to: pt(q.0, q.1)) }
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            p.addEllipse(in: CGRect(x: rect.minX + (cx - r) * s, y: rect.minY + (cy - r) * s, width: 2 * r * s, height: 2 * r * s))
        }

        switch kind {
        case .asterisk:
            line((7, 1), (7, 13)); line((1, 7), (13, 7))
            line((2.8, 2.8), (11.2, 11.2)); line((11.2, 2.8), (2.8, 11.2))
        case .chevronUp: line((2.5, 7.5), (6, 4), (9.5, 7.5))
        case .chevronRight: line((4.5, 2.5), (8, 6), (4.5, 9.5))
        case .chevronLeft: line((7.5, 2.5), (4, 6), (7.5, 9.5))
        case .arrowUpRight: line((4, 2.5), (9.5, 2.5), (9.5, 8)); line((9.5, 2.5), (3, 9))
        case .sliders:
            line((2, 4), (9, 4)); line((12, 4), (14, 4)); line((2, 12), (4, 12)); line((7, 12), (14, 12))
            circle(10.5, 4, 1.5); circle(5.5, 12, 1.5)
        case .sun:
            circle(8, 8, 3)
            line((8, 1), (8, 2.5)); line((8, 13.5), (8, 15)); line((1, 8), (2.5, 8)); line((13.5, 8), (15, 8))
            line((3, 3), (4, 4)); line((12, 12), (13, 13)); line((3, 13), (4, 12)); line((12, 4), (13, 3))
        case .moon:
            // SVG: M13.5 9.5 A6 6 0 0 1 6.5 2.5 a6 6 0 1 0 7 7z — два арочных сегмента радиуса 6.
            let a = (x: 13.5, y: 9.5), b = (x: 6.5, y: 2.5)
            let c1 = (x: 12.398, y: 3.602), c2 = (x: 7.602, y: 8.398)
            func angle(_ c: (x: Double, y: Double), _ q: (x: Double, y: Double)) -> Angle {
                .radians(atan2(q.y - c.y, q.x - c.x))
            }
            p.move(to: pt(a.x, a.y))
            p.addArc(center: pt(c1.x, c1.y), radius: 6 * s, startAngle: angle(c1, a), endAngle: angle(c1, b), clockwise: false)
            p.addArc(center: pt(c2.x, c2.y), radius: 6 * s, startAngle: angle(c2, b), endAngle: angle(c2, a), clockwise: true)
            p.closeSubpath()
        }
        return p
    }
}
