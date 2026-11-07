import Observation
import SwiftUI

struct Ball {
    var x: CGFloat
    var y: CGFloat
    var px: CGFloat
    var py: CGFloat
    var r: CGFloat
    var rates: [Rate?]
    var seeds: [Int]
    var skip: Bool
    var rot: CGFloat
    var fresh: Bool
    let key: String
}

/// 籃子的物理：Verlet 積分、四輪碰撞修正，參數照網頁版。
/// 每一幀都在動的資料（balls、重力）不追蹤；只有 running／dim 讓 SwiftUI 知道。
@Observable final class PileModel {
    @ObservationIgnored var balls: [Ball] = []
    @ObservationIgnored var w: CGFloat = 0
    @ObservationIgnored var h: CGFloat = 0
    @ObservationIgnored var gx: CGFloat = 0
    @ObservationIgnored var gy: CGFloat = 1
    @ObservationIgnored var tilt = false
    @ObservationIgnored var calm = 0
    @ObservationIgnored var needsRebuild = true
    @ObservationIgnored var reduceMotion = false

    /// true 時 TimelineView 每幀跑；靜下來 90 幀就停，省電
    var running = false
    /// 剝的時候整個籃子淡掉
    var dim = false

    func ballR(_ n: Int) -> CGFloat {
        max(14, min(23, sqrt(w * 170 * 0.62 / (CGFloat(max(n, 1)) * .pi))))
    }

    func start() {
        calm = 0
        if !running { running = true }
    }

    func requestRebuild() {
        needsRebuild = true
    }

    /// Canvas 每次畫之前呼叫：尺寸變了就補跑幾步，要重建就重建
    func prepare(size: CGSize, store: AppStore) {
        if size.width != w || size.height != h {
            let had = w > 0
            w = size.width
            h = size.height
            if had {
                for _ in 0..<60 { step(silent: true) }
            }
        }
        if needsRebuild && w > 0 && h > 0 {
            needsRebuild = false
            rebuild(store: store)
        }
    }

    /// 把這個月剝過的日子排進籃子，先靜靜落好
    private func rebuild(store: AppStore) {
        let t = DK.today()
        let pre = String(t.prefix(8))
        let keys = store.s.days.keys.filter { $0.hasPrefix(pre) }.sorted()
        let r = ballR(keys.count)
        var list: [Ball] = []
        for (i, k) in keys.enumerated() {
            guard let d = store.s.days[k] else { continue }
            let span = max(w - 2 * r, 1)
            let fi = CGFloat(i)
            let x = r + (fi * 2.3 * r).truncatingRemainder(dividingBy: span)
            let y = h - r - floor(fi * 2.3 * r / span) * 1.9 * r
            list.append(Ball(x: x, y: y, px: x, py: y, r: d.isSkip ? r * 0.8 : r, rates: d.rates,
                             seeds: store.seedCount(k), skip: d.isSkip, rot: CGFloat.random(in: 0..<6.28),
                             fresh: false, key: k))
        }
        balls = list
        for _ in 0..<240 { step(silent: true) }
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    func step(silent: Bool) {
        let G: CGFloat = 0.55
        let n = balls.count
        if n == 0 { return }
        for i in 0..<n {
            let vx = (balls[i].x - balls[i].px) * 0.985
            let vy = (balls[i].y - balls[i].py) * 0.985
            balls[i].px = balls[i].x
            balls[i].py = balls[i].y
            balls[i].x += vx + gx * G
            balls[i].y += vy + gy * G
            balls[i].rot += vx / balls[i].r * 0.6
        }
        for _ in 0..<4 {
            for i in 0..<n {
                if balls[i].y > h - balls[i].r {
                    if balls[i].fresh && !silent {
                        let v = balls[i].y - balls[i].py
                        if v > 2 { Feedback.shared.thud(Double(v)) }
                        balls[i].fresh = false
                    }
                    balls[i].y = h - balls[i].r
                }
                if balls[i].x < balls[i].r { balls[i].x = balls[i].r }
                if balls[i].x > w - balls[i].r { balls[i].x = w - balls[i].r }
                if tilt && balls[i].y < balls[i].r { balls[i].y = balls[i].r }
                for j in (i + 1)..<n {
                    let dx = balls[j].x - balls[i].x
                    let dy = balls[j].y - balls[i].y
                    let d = hypot(dx, dy)
                    let m = balls[i].r + balls[j].r
                    if d < m && d > 0.001 {
                        let k = (m - d) / d * 0.5
                        balls[i].x -= dx * k
                        balls[i].y -= dy * k
                        balls[j].x += dx * k
                        balls[j].y += dy * k
                        if !silent && (balls[i].fresh || balls[j].fresh) {
                            let f = balls[i].fresh ? i : j
                            let v = balls[f].y - balls[f].py
                            if v > 2 { Feedback.shared.thud(Double(v) * 0.8) }
                            balls[f].fresh = false
                        }
                    }
                }
            }
        }
    }

    /// 每一幀：跑一步，然後看是不是都靜下來了
    func tickFrame() {
        step(silent: false)
        var maxV: CGFloat = 0
        for b in balls {
            maxV = max(maxV, abs(b.x - b.px) + abs(b.y - b.py))
        }
        if maxV < 0.03 {
            calm += 1
        } else {
            calm = 0
        }
        if calm > 90 {
            calm = 0
            DispatchQueue.main.async { [weak self] in self?.running = false }
        }
    }

    /// 今天那顆從蒜頭圖的位置掉下來
    func drop(key: String, entry: DayEntry, seeds: [Int], from point: CGPoint?) {
        let x = point?.x ?? w / 2
        let y = point?.y ?? -30
        let others = balls.filter { $0.key != key }
        let R = ballR(others.count + 1)
        balls = others.map { b in
            var o = b
            o.r = o.skip ? R * 0.8 : R
            return o
        }
        balls.append(Ball(x: x, y: y, px: x + CGFloat.random(in: -1...1), py: y + 2,
                          r: entry.isSkip ? R * 0.8 : R, rates: entry.rates, seeds: seeds,
                          skip: entry.isSkip, rot: 0, fresh: true, key: key))
        if reduceMotion {
            for _ in 0..<240 { step(silent: true) }
        }
        start()
    }

    func remove(key: String) {
        balls.removeAll { $0.key == key }
    }

    func updateSeeds(key: String, seeds: [Int]) {
        if let i = balls.firstIndex(where: { $0.key == key }) {
            balls[i].seeds = seeds
        }
    }

    /// 戳一下籃子裡的蒜，它會跳一下
    @discardableResult
    func nudge(at p: CGPoint) -> Bool {
        for i in balls.indices where hypot(balls[i].x - p.x, balls[i].y - p.y) < balls[i].r + 6 {
            balls[i].py = balls[i].y + 10 + CGFloat.random(in: 0..<4)
            balls[i].px = balls[i].x + CGFloat.random(in: -3...3)
            Feedback.shared.tick()
            start()
            return true
        }
        return false
    }

    /// 來自 CoreMotion 的重力方向；x 往右、y 往下為正
    func setGravity(_ x: Double, _ y: Double) {
        tilt = true
        let nx = CGFloat(max(-1, min(1, x * 1.5)))
        let ny0 = CGFloat(max(-1, min(1, y * 1.5)))
        let ny: CGFloat = (abs(ny0) < 0.12 && abs(nx) < 0.12) ? 0.12 : ny0
        if abs(nx - gx) > 0.03 || abs(ny - gy) > 0.03 {
            gx = nx
            gy = ny
            start()
        }
    }
}

/// 畫籃子：TimelineView 驅動、Canvas 畫，放在主畫面最底層
struct PileView: View {
    let pile: PileModel
    @Environment(AppStore.self) private var store

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !pile.running)) { timeline in
            Canvas { ctx, size in
                _ = timeline.date
                pile.prepare(size: size, store: store)
                if pile.running { pile.tickFrame() }
                for b in pile.balls {
                    GarlicArt.drawBall(in: ctx, b)
                }
            }
        }
        .allowsHitTesting(false)
        .opacity(pile.dim ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: pile.dim)
    }
}
