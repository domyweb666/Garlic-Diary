import Foundation

/// 日期鍵 "YYYY-MM-DD"。沿用網頁版的規則：凌晨四點前算前一天。
enum DK {
    private static var cal: Calendar { Calendar.current }

    static func ymd(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func today(_ now: Date = Date()) -> String {
        ymd(now.addingTimeInterval(-4 * 3600))
    }

    /// 解析成那天中午，避開夏令時間在午夜的邊界
    static func parse(_ k: String) -> Date {
        let p = k.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        var dc = DateComponents()
        dc.year = p[0]
        dc.month = p[1]
        dc.day = p[2]
        dc.hour = 12
        return cal.date(from: dc) ?? Date()
    }

    static func key(_ y: Int, _ m: Int, _ d: Int) -> String {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func addDays(_ k: String, _ n: Int) -> String {
        let base = parse(k)
        return ymd(cal.date(byAdding: .day, value: n, to: base) ?? base)
    }

    /// a 減 b 的天數
    static func diffDays(_ a: String, _ b: String) -> Int {
        cal.dateComponents([.day], from: parse(b), to: parse(a)).day ?? 0
    }

    /// 0 = 週日 … 6 = 週六
    static func weekday(_ k: String) -> Int {
        cal.component(.weekday, from: parse(k)) - 1
    }

    static func components(_ k: String) -> (y: Int, m: Int, d: Int) {
        let c = cal.dateComponents([.year, .month, .day], from: parse(k))
        return (c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// "11月7日 週五"
    static func heading(_ k: String) -> String {
        let c = components(k)
        return "\(c.m)月\(c.d)日 週\(Seg.weekdays[weekday(k)])"
    }

    /// "11/7"
    static func short(_ k: String) -> String {
        let c = components(k)
        return "\(c.m)/\(c.d)"
    }

    static func monthPrefix(_ y: Int, _ m: Int) -> String {
        String(format: "%04d-%02d", y, m)
    }

    static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        cal.range(of: .day, in: .month, for: parse(key(y, m, 1)))?.count ?? 30
    }

    static func firstWeekday(_ y: Int, _ m: Int) -> Int {
        weekday(key(y, m, 1))
    }

    /// 0 上午（4–12）、1 下午（12–18）、2 晚上
    static func segNow(_ d: Date = Date()) -> Int {
        let h = cal.component(.hour, from: d)
        if h >= 4 && h < 12 { return 0 }
        if h >= 12 && h < 18 { return 1 }
        return 2
    }

    static func isNight(_ d: Date = Date()) -> Bool {
        let h = cal.component(.hour, from: d)
        return h >= 18 || h < 4
    }

    static func hm(_ ts: Double) -> String {
        let c = cal.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ts / 1000))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func nowMs() -> Double {
        Date().timeIntervalSince1970 * 1000
    }

    /// 以 end 為最後一天的七天
    static func weekKeys(ending end: String) -> [String] {
        (0...6).reversed().map { addDays(end, -$0) }
    }
}
