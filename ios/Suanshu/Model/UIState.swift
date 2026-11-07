import Foundation
import Observation

/// 剝到一半的狀態（不存檔；關掉 app 就算了，跟網頁版一樣）
struct SegDraft {
    var r: Rate?
    var t = ""
    var tags: [String] = []
}

@Observable final class PeelDraft {
    var i = 0
    var s: [SegDraft] = [SegDraft(), SegDraft(), SegDraft()]
    var edit = false
}

struct YM: Equatable {
    var y: Int
    var m: Int
}

/// 畫面層的共用狀態：在哪一頁、剝到一半、對帳頁開著、籃子頁在看哪個月
@Observable final class UIState {
    /// 0 籃子、1 剝今天、2 設定
    var page: Int? = 1
    var peel: PeelDraft?
    var review: ReviewFlow?
    var viewMonth: YM?

    /// 剝的時候鎖住左右滑
    var locked: Bool { peel != nil }
}

/// 底部那條短訊息
@Observable final class Toaster {
    var message: String?
    @ObservationIgnored private var work: DispatchWorkItem?

    func show(_ m: String) {
        message = m
        work?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.message = nil }
        work = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: w)
    }
}
