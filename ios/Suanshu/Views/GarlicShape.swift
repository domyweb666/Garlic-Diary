import SwiftUI

/// 蒜頭的畫法。所有座標都在 100×100 的設計空間裡，呼叫端先把 context 縮放到位。
/// 同一套畫法給主畫面的蒜、月曆格子、週對帳的一排、籃子裡滾的那些。
enum GarlicArt {
    /// SVG：M50 13 C61 25 73 45 71 65 C69 84 31 84 29 65 C27 45 39 25 50 13 Z
    static let clove: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 50, y: 13))
        p.addCurve(to: CGPoint(x: 71, y: 65), control1: CGPoint(x: 61, y: 25), control2: CGPoint(x: 73, y: 45))
        p.addCurve(to: CGPoint(x: 29, y: 65), control1: CGPoint(x: 69, y: 84), control2: CGPoint(x: 31, y: 84))
        p.addCurve(to: CGPoint(x: 50, y: 13), control1: CGPoint(x: 27, y: 45), control2: CGPoint(x: 39, y: 25))
        p.closeSubpath()
        return p
    }()

    static let sprout: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 46, y: 20))
        p.addCurve(to: CGPoint(x: 50, y: 2), control1: CGPoint(x: 47, y: 12), control2: CGPoint(x: 49, y: 7))
        p.addCurve(to: CGPoint(x: 54, y: 20), control1: CGPoint(x: 51, y: 7), control2: CGPoint(x: 53, y: 12))
        p.closeSubpath()
        return p
    }()

    static let leaf: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 20, y: 78))
        p.addCurve(to: CGPoint(x: 84, y: 16), control1: CGPoint(x: 18, y: 40), control2: CGPoint(x: 46, y: 16))
        p.addCurve(to: CGPoint(x: 24, y: 82), control1: CGPoint(x: 86, y: 52), control2: CGPoint(x: 62, y: 80))
        p.closeSubpath()
        return p
    }()

    static let leafVein: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 24, y: 80))
        p.addCurve(to: CGPoint(x: 78, y: 22), control1: CGPoint(x: 40, y: 60), control2: CGPoint(x: 56, y: 42))
        return p
    }()

    static let rot: [Double] = [-13, 0, 13]
    static let tx: [CGFloat] = [-15, 0, 15]
    static let ty: [CGFloat] = [2, 0, 2]
    static let order = [0, 2, 1]
    static let rx: [CGFloat] = [35, 50, 65]

    static func drawGarlic(in ctx: GraphicsContext, rates: [Rate?], seeds: [Int], sprout showSprout: Bool,
                           active: Int?, highlight: Bool = true) {
        // 根：白天說過的話，一句一條，最多畫五條
        for i in 0..<3 {
            let n = min(i < seeds.count ? seeds[i] : 0, 5)
            if n <= 0 { continue }
            for j in 0..<n {
                let off = CGFloat(j) - CGFloat(n - 1) / 2
                let x = rx[i] + off * 3.4
                var p = Path()
                p.move(to: CGPoint(x: x, y: 85))
                p.addQuadCurve(to: CGPoint(x: x + off * 1.8, y: 96),
                               control: CGPoint(x: x + (j % 2 == 1 ? 2 : -2), y: 90))
                ctx.stroke(p, with: .color(T.root), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            }
        }
        if showSprout {
            ctx.fill(sprout, with: .color(T.skin))
            ctx.stroke(sprout, with: .color(T.edge), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: 28, y: 79, width: 44, height: 10)), with: .color(T.skin))
        for i in order {
            var c = ctx
            c.translateBy(x: tx[i], y: ty[i])
            c.translateBy(x: 50, y: 82)
            c.rotate(by: .degrees(rot[i]))
            c.translateBy(x: -50, y: -82)
            let isActive = (active == i)
            let r: Rate? = i < rates.count ? rates[i] : nil
            c.fill(clove, with: .color(T.rate(r)))
            c.stroke(clove, with: .color(isActive ? T.fg : T.edge),
                     style: StrokeStyle(lineWidth: isActive ? 3 : 2, lineJoin: .round))
        }
        if highlight {
            ctx.fill(Path(ellipseIn: CGRect(x: 42.4, y: 35, width: 5.2, height: 18)),
                     with: .color(Color.white.opacity(0.35)))
        }
    }

    static func drawLeaf(in ctx: GraphicsContext) {
        ctx.fill(leaf, with: .color(T.leaf))
        ctx.stroke(leafVein, with: .color(T.card), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    static func drawEmpty(in ctx: GraphicsContext) {
        ctx.stroke(Path(ellipseIn: CGRect(x: 10, y: 10, width: 80, height: 80)),
                   with: .color(T.sep), style: StrokeStyle(lineWidth: 3, dash: [4, 7]))
    }

    /// 籃子裡的一顆（有位置、旋轉、半徑）
    static func drawBall(in ctx: GraphicsContext, _ o: Ball) {
        var c = ctx
        c.translateBy(x: o.x, y: o.y)
        c.rotate(by: .radians(Double(o.rot)))
        let r = o.r
        if o.skip {
            var p = Path()
            p.move(to: CGPoint(x: -r * 0.7, y: r * 0.6))
            p.addCurve(to: CGPoint(x: r * 0.8, y: -r * 0.75),
                       control1: CGPoint(x: -r * 0.8, y: -r * 0.4), control2: CGPoint(x: 0, y: -r))
            p.addCurve(to: CGPoint(x: -r * 0.7, y: r * 0.6),
                       control1: CGPoint(x: r * 0.85, y: r * 0.1), control2: CGPoint(x: r * 0.2, y: r * 0.8))
            p.closeSubpath()
            c.fill(p, with: .color(T.leaf))
            return
        }
        let k = r / 46
        c.scaleBy(x: k, y: k)
        c.translateBy(x: -50, y: -55)
        drawGarlic(in: c, rates: o.rates, seeds: o.seeds, sprout: false, active: nil, highlight: false)
    }
}

/// 一顆蒜（主畫面、月曆、對帳用）
struct GarlicGlyph: View {
    var rates: [Rate?] = [nil, nil, nil]
    var seeds: [Int] = [0, 0, 0]
    var sprout = false
    var active: Int? = nil
    var label = "蒜頭"

    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            c.scaleBy(x: size.width / 100, y: size.height / 100)
            GarlicArt.drawGarlic(in: c, rates: rates, seeds: seeds, sprout: sprout, active: active)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text(label))
    }
}

/// 今天不剝：一片葉子
struct LeafGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            c.scaleBy(x: size.width / 100, y: size.height / 100)
            GarlicArt.drawLeaf(in: c)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text("今天不剝"))
    }
}

/// 沒剝的日子：虛線圈
struct EmptyGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            var c = ctx
            c.scaleBy(x: size.width / 100, y: size.height / 100)
            GarlicArt.drawEmpty(in: c)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
