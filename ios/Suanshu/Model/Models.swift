import Foundation

// 資料結構與網頁版 0.3 的 localStorage JSON（v2）相容：
// 網頁版匯出的備份可以直接匯入 iOS 版，iOS 版匯出的也能貼回網頁版。
// 多出來的欄位（remindOn、haptics）網頁版會原樣保留，不影響它。

enum Rate: String, Codable, CaseIterable {
    case good = "順"
    case mid = "普通"
    case bad = "卡"
}

enum Seg {
    static let names = ["上午", "下午", "晚上"]
    static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
}

struct SegmentRecord: Codable, Equatable {
    var r: Rate
    var t: String
    var tags: [String]

    init(r: Rate, t: String = "", tags: [String] = []) {
        self.r = r
        self.t = t
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        r = try c.decode(Rate.self, forKey: .r)
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// 一天：剝過（s 有三瓣）或今天不剝（skip）
struct DayEntry: Codable, Equatable {
    var s: [SegmentRecord]?
    var skip: Bool?
    var at: Double?
    var line: String?

    var isSkip: Bool { skip == true }

    var segments: [SegmentRecord]? {
        if let s, s.count == 3 { return s }
        return nil
    }

    var rates: [Rate?] {
        if let segs = segments { return segs.map { Optional($0.r) } }
        return [nil, nil, nil]
    }

    static func peeled(_ s: [SegmentRecord], line: String) -> DayEntry {
        DayEntry(s: s, skip: nil, at: DK.nowMs(), line: line)
    }

    static func skipped() -> DayEntry {
        DayEntry(s: nil, skip: true, at: DK.nowMs(), line: nil)
    }
}

/// 白天說的一句
struct Fragment: Codable, Equatable {
    var t: String
    var ts: Double
    var seg: Int
}

struct ReviewAction: Codable, Equatable {
    var when: String
    var what: String
}

struct ChatMessage: Codable, Equatable {
    var role: String
    var content: String
    var hidden: Bool?

    var isHidden: Bool { hidden == true }

    init(role: String, content: String, hidden: Bool? = nil) {
        self.role = role
        self.content = content
        self.hidden = hidden
    }
}

/// 四格：有／沒有關鍵字 × 是／不是該評分
struct FourCounts: Codable, Equatable {
    var ab = 0
    var anb = 0
    var nab = 0
    var nanb = 0
}

/// AI 提的候選（還沒加入清單的那種）
struct AICandidate: Codable, Equatable {
    var name: String
    var keywords: [String]
    var outcome: Rate
    var prediction: String
    var question: String
    var four: FourCounts?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        outcome = try c.decode(Rate.self, forKey: .outcome)
        prediction = try c.decodeIfPresent(String.self, forKey: .prediction) ?? ""
        question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
        four = try c.decodeIfPresent(FourCounts.self, forKey: .four)
    }
}

struct ReviewAI: Codable, Equatable {
    var cands: [AICandidate] = []
    var chat: [ChatMessage] = []
    var added: [Int] = []
    var context: String?
    var talk: Int?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cands = try c.decodeIfPresent([AICandidate].self, forKey: .cands) ?? []
        chat = try c.decodeIfPresent([ChatMessage].self, forKey: .chat) ?? []
        added = try c.decodeIfPresent([Int].self, forKey: .added) ?? []
        context = try c.decodeIfPresent(String.self, forKey: .context)
        talk = try c.decodeIfPresent(Int.self, forKey: .talk)
    }
}

struct Review: Codable, Equatable {
    var memory = ""
    var gap = ""
    var action = ReviewAction(when: "", what: "")
    var lastResult = ""
    var done = false
    var at: Double?
    var ai: ReviewAI?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memory = try c.decodeIfPresent(String.self, forKey: .memory) ?? ""
        gap = try c.decodeIfPresent(String.self, forKey: .gap) ?? ""
        action = try c.decodeIfPresent(ReviewAction.self, forKey: .action) ?? ReviewAction(when: "", what: "")
        lastResult = try c.decodeIfPresent(String.self, forKey: .lastResult) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        at = try c.decodeIfPresent(Double.self, forKey: .at)
        ai = try c.decodeIfPresent(ReviewAI.self, forKey: .ai)
    }
}

enum CandStatus {
    static let watching = "觀察中"
    static let legacy = "候選"
    static let passed = "通過"
    static let failed = "淘汰"
}

/// 加入清單後的候選：預測寫好就不能改，兩週後判決
struct Candidate: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kw: [String]
    var outcome: Rate
    var pred: String
    var created: String
    var verdict: String
    var status: String
    var extended: Bool?
    var base: FourCounts?
    var passed: String?

    var isLive: Bool { status == CandStatus.watching || status == CandStatus.legacy }

    init(id: String, name: String, kw: [String], outcome: Rate, pred: String, created: String, verdict: String,
         status: String, extended: Bool? = false, base: FourCounts? = nil, passed: String? = nil) {
        self.id = id
        self.name = name
        self.kw = kw
        self.outcome = outcome
        self.pred = pred
        self.created = created
        self.verdict = verdict
        self.status = status
        self.extended = extended
        self.base = base
        self.passed = passed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "c\(Int(DK.nowMs()))"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kw = try c.decodeIfPresent([String].self, forKey: .kw) ?? []
        outcome = try c.decodeIfPresent(Rate.self, forKey: .outcome) ?? .bad
        pred = try c.decodeIfPresent(String.self, forKey: .pred) ?? ""
        created = try c.decodeIfPresent(String.self, forKey: .created) ?? ""
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? CandStatus.watching
        extended = try c.decodeIfPresent(Bool.self, forKey: .extended)
        base = try c.decodeIfPresent(FourCounts.self, forKey: .base)
        passed = try c.decodeIfPresent(String.self, forKey: .passed)
    }
}

struct TagDef: Codable, Equatable {
    var name: String
    var def: String
    var added: String?
}

struct Settings: Codable, Equatable {
    var anchor = "刷完牙"
    var remind = "22:30"
    var reviewDay = 6
    var tags: [TagDef] = []
    var restart = "斷了不補，今晚剝一顆就算回來。"
    var sound = true
    /// iOS 新增：提醒開關（網頁版推不了播，只記時間）
    var remindOn: Bool?
    /// iOS 新增：觸覺回饋
    var haptics: Bool?

    var remindEnabled: Bool {
        get { remindOn ?? false }
        set { remindOn = newValue }
    }

    var hapticsEnabled: Bool {
        get { haptics ?? true }
        set { haptics = newValue }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        anchor = try c.decodeIfPresent(String.self, forKey: .anchor) ?? d.anchor
        remind = try c.decodeIfPresent(String.self, forKey: .remind) ?? d.remind
        reviewDay = try c.decodeIfPresent(Int.self, forKey: .reviewDay) ?? d.reviewDay
        tags = try c.decodeIfPresent([TagDef].self, forKey: .tags) ?? []
        restart = try c.decodeIfPresent(String.self, forKey: .restart) ?? d.restart
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        remindOn = try c.decodeIfPresent(Bool.self, forKey: .remindOn)
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics)
        if anchor.isEmpty { anchor = d.anchor }
        if restart.isEmpty { restart = d.restart }
        if reviewDay < 0 || reviewDay > 6 { reviewDay = d.reviewDay }
    }
}

struct AISettings: Codable, Equatable {
    /// 金鑰只放 Keychain；這個欄位在檔案和備份裡永遠是空字串
    var key = ""
    var model = AIClient.defaultModel
    var early = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? AIClient.defaultModel
        early = try c.decodeIfPresent(Bool.self, forKey: .early) ?? false
        if model.trimmingCharacters(in: .whitespaces).isEmpty { model = AIClient.defaultModel }
    }
}

struct LogItem: Codable, Equatable {
    var d: String
    var what: String
}

/// 整個 app 的狀態（對應網頁版的 S）
struct Store: Codable, Equatable {
    var v = 2
    var created: String?
    var onboarded = false
    var demo = false
    var days: [String: DayEntry] = [:]
    var frags: [String: [Fragment]] = [:]
    var reviews: [String: Review] = [:]
    var cands: [Candidate] = []
    var settings = Settings()
    var ai = AISettings()
    var log: [LogItem] = []
    var lastLine = -1

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 2
        created = try c.decodeIfPresent(String.self, forKey: .created)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        demo = try c.decodeIfPresent(Bool.self, forKey: .demo) ?? false
        days = try c.decodeIfPresent([String: DayEntry].self, forKey: .days) ?? [:]
        frags = try c.decodeIfPresent([String: [Fragment]].self, forKey: .frags) ?? [:]
        reviews = try c.decodeIfPresent([String: Review].self, forKey: .reviews) ?? [:]
        cands = try c.decodeIfPresent([Candidate].self, forKey: .cands) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        ai = try c.decodeIfPresent(AISettings.self, forKey: .ai) ?? AISettings()
        log = try c.decodeIfPresent([LogItem].self, forKey: .log) ?? []
        lastLine = try c.decodeIfPresent(Int.self, forKey: .lastLine) ?? -1
    }
}

/// 解 AI 回的 JSON 時，壞掉的一條不要拖垮整批
struct Failable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct AICandidatesEnvelope: Decodable {
    var candidates: [Failable<AICandidate>]?
}
