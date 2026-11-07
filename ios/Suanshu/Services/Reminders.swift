import Foundation
import UserNotifications

/// 每天一次的提醒。只排未來七天、已經剝過的那天不排，每次回到前景重排一次。
enum Reminders {
    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    static func checkAuthorized(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            DispatchQueue.main.async { done(ok) }
        }
    }

    static func reschedule(_ s: Store) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard s.settings.remindEnabled else { return }
        let parts = s.settings.remind.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let hour = parts[0]
        let minute = parts[1]
        let today = DK.today()
        let cal = Calendar.current
        for off in 0..<7 {
            let k = DK.addDays(today, off)
            if s.days[k] != nil { continue }
            var base = DK.parse(k)
            // 提醒時間在凌晨四點前，屬於前一天的鍵，落在隔天的日曆上
            if hour < 4 { base = cal.date(byAdding: .day, value: 1, to: base) ?? base }
            var dc = cal.dateComponents([.year, .month, .day], from: base)
            dc.hour = hour
            dc.minute = minute
            guard let fire = cal.date(from: dc), fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            let reviewDay = DK.weekday(k) == s.settings.reviewDay && !(s.reviews[k]?.done ?? false)
            if reviewDay {
                content.title = "今天是對帳日"
                content.body = "先剝今天，再花二十分鐘對這週的帳。"
            } else {
                content.title = "剝今天"
                content.body = "\(s.settings.anchor)之後，把今天剝成三瓣。"
            }
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            center.add(UNNotificationRequest(identifier: "suanshu-" + k, content: content, trigger: trigger))
        }
    }
}
