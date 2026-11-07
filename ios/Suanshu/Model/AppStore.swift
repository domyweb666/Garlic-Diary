import Foundation
import Observation

/// 一段（某天的上午／下午／晚上）攤平後的樣子，給四格用
struct Unit {
    let k: String
    let i: Int
    let r: Rate
    let text: String
    let tags: [String]
}

struct PrevAction {
    let key: String
    let action: ReviewAction
}

enum ImportError: Error {
    case bad
}

/// 整個 app 的資料與規則。對應網頁版的 S 和那一堆小函式。
@Observable final class AppStore {
    var s: Store
    /// Keychain 裡的金鑰（唯讀；要改用 setApiKey）
    private(set) var apiKey: String

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "org.domyweb.suanshu.save", qos: .utility)
    @ObservationIgnored private var lastDay = DK.today()

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = support.appendingPathComponent("Suanshu", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("suanshu-v1.json")

        var loaded = Store()
        if let data = try? Data(contentsOf: url) {
            if let st = try? JSONDecoder().decode(Store.self, from: data) {
                loaded = st
            } else {
                // 讀不懂就先另存一份，不要蓋掉
                let name = "suanshu-v1.broken-\(Int(Date().timeIntervalSince1970)).json"
                try? data.write(to: dir.appendingPathComponent(name))
            }
        }
        var key = Keychain.read()
        var needsSave = false
        if !loaded.ai.key.isEmpty {
            // 舊檔或網頁版備份把金鑰留在 JSON 裡：搬進 Keychain
            Keychain.write(loaded.ai.key)
            key = Keychain.read()
            loaded.ai.key = ""
            needsSave = true
        }
        fileURL = url
        s = loaded
        apiKey = key
        if needsSave { save() }
        syncFeedbackFlags()
    }

    // MARK: - 存檔

    func save() {
        let snapshot = s
        let url = fileURL
        ioQueue.async {
            guard let d = try? JSONEncoder().encode(snapshot) else { return }
            try? d.write(to: url, options: [.atomic])
        }
    }

    func setApiKey(_ k: String) {
        Keychain.write(k)
        apiKey = Keychain.read()
    }

    func syncFeedbackFlags() {
        Feedback.shared.soundOn = s.settings.sound
        Feedback.shared.hapticsOn = s.settings.hapticsEnabled
    }

    /// 回到前景時看日期有沒有過
    func dayChanged() -> Bool {
        let t = DK.today()
        if t != lastDay {
            lastDay = t
            return true
        }
        return false
    }

    // MARK: - 讀

    var today: String { DK.today() }

    var isEmpty: Bool { s.days.isEmpty && s.frags.isEmpty }

    func peeledKeys() -> [String] {
        s.days.filter { !$0.value.isSkip }.map { $0.key }.sorted()
    }

    func monthCount(_ y: Int, _ m: Int) -> Int {
        let p = DK.monthPrefix(y, m)
        return peeledKeys().filter { $0.hasPrefix(p) }.count
    }

    func dayN() -> Int {
        guard let c = s.created else { return 1 }
        return DK.diffDays(today, c) + 1
    }

    func frags(_ k: String) -> [Fragment] {
        s.frags[k] ?? []
    }

    func seedCount(_ k: String) -> [Int] {
        var c = [0, 0, 0]
        for f in frags(k) where f.seg >= 0 && f.seg < 3 {
            c[f.seg] += 1
        }
        return c
    }

    var aiOpen: Bool { dayN() > 21 || s.ai.early || s.demo }

    /// 上一次剝是三天以前：算「回來了」
    func isBack() -> Bool {
        let t = today
        let ks = peeledKeys().filter { $0 < t }
        guard let last = ks.last else { return false }
        return DK.diffDays(t, last) >= 3
    }

    func reviewDue() -> Bool {
        let t = today
        return DK.weekday(t) == s.settings.reviewDay && !(s.reviews[t]?.done ?? false)
    }

    func logChange(_ what: String) {
        s.log.insert(LogItem(d: today, what: what), at: 0)
        if s.log.count > 60 { s.log = Array(s.log.prefix(60)) }
        save()
    }

    // MARK: - 寫

    /// 記一句；回傳落在哪一瓣
    @discardableResult
    func addFragment(_ text: String) -> Int {
        let t = today
        let seg = DK.segNow()
        var arr = s.frags[t] ?? []
        arr.append(Fragment(t: text, ts: DK.nowMs(), seg: seg))
        s.frags[t] = arr
        if s.created == nil { s.created = t }
        save()
        return seg
    }

    func skipToday() {
        let t = today
        s.days[t] = DayEntry.skipped()
        if s.created == nil { s.created = t }
        save()
    }

    func unskipToday() {
        s.days[today] = nil
        save()
    }

    /// 三瓣都點完；回傳完成語
    @discardableResult
    func savePeel(_ segs: [SegmentRecord], edit: Bool) -> String {
        let t = today
        let first = peeledKeys().isEmpty
        let back = isBack()
        let prev = s.days[t]
        let line: String
        if edit, let kept = prev?.line, !kept.isEmpty {
            line = kept
        } else {
            line = pickLine(segs.map { $0.r }, first: first, back: back)
        }
        s.days[t] = DayEntry.peeled(segs, line: line)
        if s.created == nil { s.created = t }
        save()
        return line
    }

    // MARK: - 完成語

    private static let linesAny = [
        "今天收好了。", "三瓣都收進籃子了。", "好，今天就這樣。", "收進去了，去睡吧。", "今天這顆，放好了。",
        "記下來了，明天見。", "又一顆。", "今天剝完了。", "這顆是今天的。", "籃子裡多一顆。", "收工。",
        "好，關燈吧。", "今晚的版本，存好了。", "今天的三瓣，都在這。", "剝好了。", "這顆跟昨天的不一樣。",
    ]
    private static let linesAllBad = ["三瓣都卡的一天，記下來就夠了。", "卡的一天也是一顆。"]
    private static let linesAllGood = ["三瓣都順，記著。", "整天都順的一天。"]
    private static let linesSomeBad = ["有一瓣卡住，記下來就好。", "卡在哪一瓣，籃子會記得。"]
    private static let linesFirst = ["第一顆。"]
    private static let linesBack = ["回來了，從這顆開始。"]

    private func pickLine(_ rates: [Rate], first: Bool, back: Bool) -> String {
        let pool: [String]
        var isAny = false
        if first {
            pool = Self.linesFirst
        } else if back {
            pool = Self.linesBack
        } else if rates.allSatisfy({ $0 == .bad }) {
            pool = Self.linesAllBad
        } else if rates.allSatisfy({ $0 == .good }) {
            pool = Self.linesAllGood
        } else if rates.contains(.bad) && Double.random(in: 0..<1) < 0.4 {
            pool = Self.linesSomeBad
        } else {
            pool = Self.linesAny
            isAny = true
        }
        var i = Int.random(in: 0..<pool.count)
        if isAny && pool.count > 1 && i == s.lastLine { i = (i + 1) % pool.count }
        if isAny { s.lastLine = i }
        return pool[i]
    }

    // MARK: - 四格（程式算，不交給 AI）

    func units(from: String, to: String) -> [Unit] {
        var out: [Unit] = []
        for k in s.days.keys.sorted() where k >= from && k <= to {
            guard let d = s.days[k], !d.isSkip, let segs = d.segments else { continue }
            let fs = frags(k)
            for i in 0..<3 {
                let seg = segs[i]
                let text = fs.filter { $0.seg == i }.map { $0.t }.joined(separator: " ") + " " + seg.t
                out.append(Unit(k: k, i: i, r: seg.r, text: text, tags: seg.tags))
            }
        }
        return out
    }

    func four(kw: [String], outcome: Rate, from: String, to: String) -> FourCounts {
        var c = FourCounts()
        for u in units(from: from, to: to) {
            let a = kw.contains { w in !w.isEmpty && (u.text.contains(w) || u.tags.contains(w)) }
            let b = u.r == outcome
            if a && b {
                c.ab += 1
            } else if a {
                c.anb += 1
            } else if b {
                c.nab += 1
            } else {
                c.nanb += 1
            }
        }
        return c
    }

    /// 給 AI 讀的文字：一行一段
    func corpus(from: String, to: String) -> String {
        let keys = Set(s.days.keys).union(s.frags.keys).filter { $0 >= from && $0 <= to }.sorted()
        var lines: [String] = []
        for k in keys {
            let d = s.days[k]
            let wd = "週" + Seg.weekdays[DK.weekday(k)]
            let segs = d?.segments
            for i in 0..<3 {
                let fs = frags(k).filter { $0.seg == i }.map { DK.hm($0.ts) + " " + $0.t }
                let seg: SegmentRecord? = segs?[i]
                if fs.isEmpty && seg == nil { continue }
                var line = "\(k) \(wd) \(Seg.names[i])｜"
                if let seg {
                    line += seg.r.rawValue
                } else if d?.isSkip == true {
                    line += "今天不剝"
                } else {
                    line += "沒剝"
                }
                if let seg, !seg.tags.isEmpty { line += "｜標籤：" + seg.tags.joined(separator: "、") }
                if let seg, !seg.t.isEmpty { line += "｜睡前補：" + seg.t }
                if !fs.isEmpty { line += "｜白天說：" + fs.joined(separator: "；") }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 候選

    func dueCands(_ t: String) -> [Candidate] {
        s.cands.filter { $0.status == CandStatus.watching && $0.verdict <= t }
    }

    func liveCands() -> [Candidate] {
        s.cands.filter { $0.isLive }
    }

    func knownCands() -> [Candidate] {
        s.cands.filter { $0.status == CandStatus.passed }
    }

    /// kind：pass／fail／ext
    func verdict(_ id: String, _ kind: String, at t: String) {
        guard let i = s.cands.firstIndex(where: { $0.id == id }) else { return }
        switch kind {
        case "pass":
            s.cands[i].status = CandStatus.passed
            s.cands[i].passed = t
        case "fail":
            s.cands[i].status = CandStatus.failed
        default:
            s.cands[i].extended = true
            s.cands[i].verdict = DK.addDays(t, 14)
        }
        save()
    }

    /// 一週最多加三條；回傳有沒有加成功
    func addCandidate(from c: AICandidate, reviewDate t: String) -> Bool {
        let thisWeek = s.cands.filter { $0.created == t }.count
        if thisWeek >= 3 { return false }
        s.cands.append(Candidate(id: "c\(Int(DK.nowMs()))", name: c.name, kw: c.keywords, outcome: c.outcome,
                                 pred: c.prediction, created: t, verdict: DK.addDays(t, 14),
                                 status: CandStatus.watching, extended: false, base: c.four, passed: nil))
        save()
        return true
    }

    // MARK: - 對帳

    func saveReview(_ t: String, _ r: Review) {
        s.reviews[t] = r
        save()
    }

    func prevAction(before t: String) -> PrevAction? {
        let ks = s.reviews.filter { $0.key < t && $0.value.done }.map { $0.key }.sorted()
        guard let k = ks.last, let r = s.reviews[k] else { return nil }
        return PrevAction(key: k, action: r.action)
    }

    // MARK: - 資料

    func wipeAll() {
        let ai = s.ai
        s = Store()
        s.ai = ai
        s.onboarded = true
        save()
    }

    func importBackup(_ data: Data) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["days"] is [String: Any] else { throw ImportError.bad }
        var st = try JSONDecoder().decode(Store.self, from: data)
        if !st.ai.key.isEmpty {
            Keychain.write(st.ai.key)
            apiKey = Keychain.read()
        }
        st.ai.key = ""
        st.onboarded = true
        s = st
        syncFeedbackFlags()
        save()
    }

    /// 備份不含金鑰
    func backupData() -> Data {
        var o = s
        o.ai.key = ""
        return (try? JSONEncoder().encode(o)) ?? Data()
    }

    /// 示範資料：看看一個月後的樣子
    func loadDemo() {
        let t = today
        var days: [String: DayEntry] = [:]
        var frags: [String: [Fragment]] = [:]
        let meet = ["跟合作方開會，講了一個多小時", "下午有會議，會後一直在回訊息", "開完會有點累，先滑了一下手機"]
        let work = ["開始剪片了", "腳本寫完一段", "在整理拍攝清單", "研究了一下收音麥克風", "回了一輪訊息才開工", "去咖啡廳寫稿"]
        func pick(_ pGood: Double, _ pMid: Double) -> Rate {
            let x = Double.random(in: 0..<1)
            if x < pGood { return .good }
            if x < pGood + pMid { return .mid }
            return .bad
        }
        let cal = Calendar.current
        for i in stride(from: 27, through: 1, by: -1) {
            let k = DK.addDays(t, -i)
            let r = Double.random(in: 0..<1)
            if r < 0.08 { continue }
            if r < 0.11 {
                days[k] = DayEntry(s: nil, skip: true, at: 0, line: nil)
                continue
            }
            let hasMeet = Double.random(in: 0..<1) < 0.35
            let pm = hasMeet ? pick(0.1, 0.25) : pick(0.45, 0.35)
            days[k] = DayEntry(s: [SegmentRecord(r: pick(0.55, 0.3)), SegmentRecord(r: pm), SegmentRecord(r: pick(0.45, 0.4))],
                               skip: nil, at: 0, line: "今天收好了。")
            let base = DK.parse(k)
            func ts(_ h: Int, _ mm: Int) -> Double {
                var dc = cal.dateComponents([.year, .month, .day], from: base)
                dc.hour = h
                dc.minute = mm
                return (cal.date(from: dc) ?? base).timeIntervalSince1970 * 1000
            }
            var fs: [Fragment] = []
            if Double.random(in: 0..<1) < 0.7 {
                fs.append(Fragment(t: work.randomElement() ?? work[0], ts: ts(10, 10 + Int.random(in: 0..<40)), seg: 0))
            }
            if hasMeet {
                fs.append(Fragment(t: meet.randomElement() ?? meet[0], ts: ts(15, Int.random(in: 0..<50)), seg: 1))
            } else if Double.random(in: 0..<1) < 0.5 {
                fs.append(Fragment(t: work.randomElement() ?? work[0], ts: ts(14, Int.random(in: 0..<50)), seg: 1))
            }
            if Double.random(in: 0..<1) < 0.4 {
                fs.append(Fragment(t: "晚上看了一部紀錄片", ts: ts(21, 5), seg: 2))
            }
            frags[k] = fs
        }
        s.days = days
        s.frags = frags
        s.created = DK.addDays(t, -27)
        s.demo = true
        var r = Review()
        r.memory = "這週還行，週三很爛。"
        r.gap = "記得週三很爛，紀錄上只有下午卡。"
        r.action = ReviewAction(when: "週二、週四下午會議後", what: "先只打開專案檔十五分鐘")
        r.done = true
        r.at = 0
        r.ai = ReviewAI()
        s.reviews = [DK.addDays(t, -7): r]
        s.cands = []
        save()
    }

    func clearDemo() {
        s.days = [:]
        s.frags = [:]
        s.reviews = [:]
        s.cands = []
        s.created = nil
        s.demo = false
        save()
    }
}
