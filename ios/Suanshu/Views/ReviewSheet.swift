import Observation
import SwiftUI

/// 一次週對帳的進行狀態（對應網頁版的 RV）
@Observable final class ReviewFlow {
    let t: String
    /// 只看舊的對帳，不能改
    let view: Bool
    var steps: [String]
    var i = 0
    var memory = ""
    var gap = ""
    var when = ""
    var what = ""
    var last = ""
    var pa: PrevAction?
    var ai = ReviewAI()
    var busy = false
    var err = ""
    var scrollChat = false

    init(open store: AppStore) {
        let t = store.today
        var st = ["mem", "rec", "gap"]
        if !store.dueCands(t).isEmpty { st.append("verdict") }
        if store.aiOpen { st.append("ai") }
        st.append("act")
        st.append("done")
        self.t = t
        self.view = false
        self.steps = st
        self.pa = store.prevAction(before: t)
        if let ex = store.s.reviews[t] {
            memory = ex.memory
            gap = ex.gap
            when = ex.action.when
            what = ex.action.what
            last = ex.lastResult
            ai = ex.ai ?? ReviewAI()
            if ex.done { i = st.count - 1 }
        }
    }

    init(past k: String, store: AppStore) {
        t = k
        view = true
        steps = ["done"]
        if let r = store.s.reviews[k] {
            memory = r.memory
            gap = r.gap
            when = r.action.when
            what = r.action.what
            last = r.lastResult
            ai = r.ai ?? ReviewAI()
        }
    }

    var stepID: String { steps[min(max(i, 0), steps.count - 1)] }

    /// 走到一半也先存著，中途關掉下次接著
    func draft(_ store: AppStore) {
        if view { return }
        if let ex = store.s.reviews[t], ex.done { return }
        var r = Review()
        r.memory = memory
        r.gap = gap
        r.action = ReviewAction(when: when, what: what)
        r.lastResult = last
        r.done = false
        r.ai = ai
        store.saveReview(t, r)
    }

    func next(_ store: AppStore) {
        i = min(i + 1, steps.count - 1)
        draft(store)
    }

    func back() {
        if i > 0 { i -= 1 }
    }

    func finish(_ store: AppStore) {
        var r = Review()
        r.memory = memory
        r.gap = gap
        r.action = ReviewAction(when: when, what: what)
        r.lastResult = last
        r.done = true
        r.at = DK.nowMs()
        r.ai = ai
        store.saveReview(t, r)
        i = steps.count - 1
        Feedback.shared.done()
        Reminders.reschedule(store.s)
    }

    // MARK: - AI

    func runAI(_ store: AppStore) {
        busy = true
        err = ""
        let to = t
        let from = DK.addDays(to, -27)
        let text = store.corpus(from: from, to: to)
        let existing = store.s.cands.filter { $0.status == CandStatus.watching }.map { $0.name }
        var prompt = "以下是使用者最近四週的紀錄，每行是一天的一段。\n\n"
        prompt += text.isEmpty ? "（沒有紀錄）" : text
        prompt += "\n\n"
        if !existing.isEmpty {
            prompt += "已經在觀察的候選（不要重複）：" + existing.joined(separator: "；") + "\n\n"
        }
        prompt += "請提出最多三條「可能的模式」，每條都要能用「某個情況出現時，那段比較容易是某個評分」來檢驗。\n"
        prompt += "只輸出 JSON，不要其他文字，格式：{\"candidates\":[{\"name\":\"一句話的候選，例如：下午有會議的時段比較容易卡\",\"keywords\":[\"會議\",\"開會\"],\"outcome\":\"卡\",\"prediction\":\"接下來兩週，……（會被新資料推翻的一句預測）\",\"question\":\"一個看得到答案的問題，不能是為什麼\"}]}\n"
        prompt += "keywords 必須是紀錄裡真的出現過的字詞（2 到 4 個），outcome 只能是「順」「普通」「卡」其中一個。資料太少就少提，甚至可以是空陣列。"
        let key = store.apiKey
        let model = store.s.ai.model
        Task { @MainActor in
            let r = await AIClient.complete(key: key, model: model,
                                            messages: [["role": "user", "content": prompt]],
                                            maxTokens: 4096, effort: "medium")
            switch r {
            case .success(let out):
                if let cands = AIClient.parseCandidates(out) {
                    self.ai.cands = cands.map { c in
                        var x = c
                        x.four = store.four(kw: c.keywords, outcome: c.outcome, from: from, to: to)
                        return x
                    }
                    self.ai.context = text
                    self.ai.added = []
                    self.ai.chat = []
                    self.ai.talk = nil
                    if cands.isEmpty {
                        self.err = "這四週的資料，AI 沒找到能檢驗的候選。資料多一點再試，這很正常。"
                    }
                } else {
                    self.err = AIClient.message(for: .format)
                }
            case .failure(let e):
                self.err = AIClient.message(for: e)
            }
            self.busy = false
            self.draft(store)
        }
    }

    func addCandidate(_ ix: Int, store: AppStore) -> Bool {
        guard ix < ai.cands.count else { return false }
        let ok = store.addCandidate(from: ai.cands[ix], reviewDate: t)
        if ok {
            ai.added.append(ix)
            draft(store)
        }
        return ok
    }

    func talk(_ ix: Int, store: AppStore) {
        guard ix < ai.cands.count else { return }
        let c = ai.cands[ix]
        let f = c.four ?? FourCounts()
        ai.talk = ix
        var ctx = "這是使用者最近四週的紀錄：\n" + (ai.context ?? "")
        ctx += "\n\n我們要聊的候選：" + c.name
        ctx += "\napp 算出的四格：有「" + c.keywords.joined(separator: "／") + "」的時段 \(f.ab) 段是「" + c.outcome.rawValue + "」、\(f.anb) 段不是；沒有的時段 \(f.nab) 段是、\(f.nanb) 段不是。"
        ctx += "\n預測：" + c.prediction
        ctx += "\n\n請先用一兩句講數字和他的原話，再問一個看得到答案的問題。"
        ai.chat = [ChatMessage(role: "user", content: ctx, hidden: true)]
        sendChat(nil, store: store)
    }

    func sendChat(_ text: String?, store: AppStore) {
        let sentUser = (text?.isEmpty == false)
        if let text, !text.isEmpty {
            ai.chat.append(ChatMessage(role: "user", content: text))
        }
        busy = true
        err = ""
        scrollChat = true
        let turns = ai.chat.filter { $0.role == "user" && !$0.isHidden }.count
        var msgs = ai.chat.map { ["role": $0.role, "content": $0.content] }
        if turns >= 4, let lastIdx = msgs.indices.last {
            let tail = "\n\n（app 提醒：這是最後一兩輪了，請收在一個下週的小實驗：什麼時候、做什麼、怎樣算有效。）"
            msgs[lastIdx]["content"] = (msgs[lastIdx]["content"] ?? "") + tail
        }
        let key = store.apiKey
        let model = store.s.ai.model
        Task { @MainActor in
            let r = await AIClient.complete(key: key, model: model, messages: msgs, maxTokens: 4096, effort: "low")
            switch r {
            case .success(let out):
                self.ai.chat.append(ChatMessage(role: "assistant", content: out.trimmed))
            case .failure(let e):
                self.err = AIClient.message(for: e)
                if sentUser, !self.ai.chat.isEmpty { self.ai.chat.removeLast() }
            }
            self.busy = false
            self.scrollChat = true
            self.draft(store)
        }
    }
}

// MARK: - 畫面

struct ReviewSheet: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        if let rv = ui.review {
            ReviewBody(rv: rv)
        } else {
            Color.clear
        }
    }
}

struct ReviewBody: View {
    let rv: ReviewFlow
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(Toaster.self) private var toaster

    @State private var chatText = ""

    var body: some View {
        let id = rv.stepID
        let last = rv.steps.count - 1
        let back = rv.i > 0 && id != "done"
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                GlassButton(symbol: back ? "chevron.left" : "xmark", label: back ? "上一步" : "關閉") {
                    if back { rv.back() } else { close() }
                }
                Spacer()
                Text(rv.view ? "過去的對帳" : "週對帳")
                    .font(.body.weight(.semibold))
                Spacer()
                Text(id != "done" ? "\(rv.i + 1) / \(last)" : "")
                    .font(.footnote)
                    .foregroundStyle(T.fg2)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        step(id)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .id(rv.i)
                .onChange(of: rv.scrollChat) { _, v in
                    if v {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        rv.scrollChat = false
                    }
                }
            }
        }
        .background(T.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) { ToastView() }
    }

    private func close() {
        ui.review = nil
    }

    private func judge(_ c: Candidate, _ kind: String) {
        store.verdict(c.id, kind, at: rv.t)
        if kind == "pass" {
            toaster.show("通過，寫進「我知道的自己」")
        } else if kind == "fail" {
            toaster.show("淘汰了，這也是一個知道")
        } else {
            toaster.show("延長兩週，只能延這一次")
        }
    }

    private func addCand(_ ix: Int) {
        if rv.addCandidate(ix, store: store) {
            toaster.show("加入候選，兩週後判決")
        } else {
            toaster.show("一週最多加三條候選")
        }
    }

    private func send() {
        let v = chatText.trimmed
        guard !v.isEmpty else { return }
        chatText = ""
        rv.sendChat(v, store: store)
    }

    private func title(_ s: String) -> some View {
        Text(s)
            .font(.title.bold())
            .padding(.top, 12)
    }

    private func lede(_ s: String) -> some View {
        Text(s)
            .font(.callout)
            .foregroundStyle(T.fg2)
            .padding(.top, 6)
            .padding(.bottom, 16)
    }

    @ViewBuilder private func step(_ id: String) -> some View {
        @Bindable var rv = rv
        switch id {
        case "mem":
            title("先說記憶")
            lede("資料還沒打開。這週你記得是怎樣的？一兩句，越直覺越好。")
            SayField(text: $rv.memory, placeholder: "例如：這週還行，週三很爛。", lines: 4)
            PrimaryButton(title: "打開這週的紀錄", enabled: !rv.memory.trimmed.isEmpty) { rv.next(store) }
                .padding(.top, 18)

        case "rec":
            title("看紀錄")
            lede("過去七天，照實看就好，先不加評語。")
            WeekBlock(t: rv.t)
            if let pa = rv.pa {
                Text("上週定的動作")
                    .font(.title3.bold())
                    .padding(.top, 22)
                Quote(k: pa.action.when, text: pa.action.what)
                    .padding(.top, 8)
                FlowLayout(spacing: 8) {
                    ForEach(["做到了", "做了一部分", "沒做"], id: \.self) { x in
                        Chip(title: x, pressed: rv.last == x) { rv.last = x }
                    }
                }
                .padding(.top, 10)
            }
            if !store.aiOpen {
                Text("前三週是資料累積期：只對帳，AI 先不提候選。")
                    .font(.footnote)
                    .foregroundStyle(T.fg2)
                    .padding(.top, 8)
            }
            PrimaryButton(title: "下一步") { rv.next(store) }
                .padding(.top, 18)

        case "gap":
            title("差在哪")
            lede("把剛剛的記憶和紀錄放在一起看。")
            VStack(spacing: 12) {
                Quote(k: "你記得的這週", text: rv.memory)
                WeekBlock(t: rv.t)
            }
            SayField(text: $rv.gap, placeholder: "例如：記得週三很爛，紀錄上只有下午卡。", lines: 3)
                .padding(.top, 14)
            FlowLayout(spacing: 8) {
                Chip(title: "看不出差別", pressed: rv.gap == "看不出差別") { rv.gap = "看不出差別" }
            }
            .padding(.top, 10)
            PrimaryButton(title: "下一步") { rv.next(store) }
                .padding(.top, 18)

        case "verdict":
            title("判決到期的候選")
            lede("預測寫好之後就不能改。拿新的資料對照：成立就通過，沒成立就淘汰。")
            VStack(spacing: 12) {
                ForEach(store.dueCands(rv.t)) { c in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(c.name)
                            .font(.body.weight(.semibold))
                        Text("預測：\(c.pred)")
                            .font(.subheadline)
                        Text("提出之後的新資料")
                            .font(.footnote)
                            .foregroundStyle(T.fg2)
                        FourGrid(c: store.four(kw: c.kw, outcome: c.outcome, from: c.created, to: rv.t),
                                 kw: c.kw, outcome: c.outcome)
                        FlowLayout(spacing: 8) {
                            MiniButton(title: "通過") { judge(c, "pass") }
                            MiniButton(title: "淘汰", ghost: true) { judge(c, "fail") }
                            if c.extended != true {
                                MiniButton(title: "延長一次", ghost: true) { judge(c, "ext") }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(T.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            PrimaryButton(title: "下一步") { rv.next(store) }
                .padding(.top, 18)

        case "ai":
            title("AI 讀你的語音")
            lede("AI 讀最近四週說過的話和三段評分，最多提三條「可能的模式」。四格數字由 app 自己算，AI 只負責提。")
            if rv.ai.cands.isEmpty {
                Button {
                    rv.runAI(store)
                } label: {
                    HStack(spacing: 8) {
                        if rv.busy { ProgressView().tint(T.onAccent) }
                        Text(rv.busy ? "正在讀" : "請 AI 讀這四週")
                    }
                }
                .buttonStyle(PrimaryStyle())
                .disabled(rv.busy)
                Text("按下去，這四週的語音文字和評分會送到 Anthropic。金鑰只存在這支手機。")
                    .font(.footnote)
                    .foregroundStyle(T.fg2)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(rv.ai.cands.enumerated()), id: \.offset) { pair in
                        let c = pair.element
                        let ix = pair.offset
                        let isAdded = rv.ai.added.contains(ix)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AI 猜的")
                                .font(.caption)
                                .foregroundStyle(T.fg2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(T.sep, lineWidth: 1))
                            Text(c.name)
                                .font(.body.weight(.semibold))
                            FourGrid(c: c.four ?? FourCounts(), kw: c.keywords, outcome: c.outcome)
                            Text("預測：\(c.prediction)")
                                .font(.subheadline)
                            Text(c.question)
                                .font(.subheadline)
                                .foregroundStyle(T.fg2)
                            FlowLayout(spacing: 8) {
                                MiniButton(title: isAdded ? "已加入候選" : "加入候選清單", ghost: isAdded) {
                                    if !isAdded { addCand(ix) }
                                }
                                MiniButton(title: "聊這條", ghost: true) { rv.talk(ix, store: store) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(T.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                if !rv.ai.chat.isEmpty || rv.ai.talk != nil {
                    chatBlock
                }
            }
            if !rv.err.isEmpty {
                Text(rv.err)
                    .font(.subheadline)
                    .foregroundStyle(T.danger)
                    .padding(.top, 12)
            }
            SecondaryButton(title: "下一步") { rv.next(store) }
                .padding(.top, 18)

        case "act":
            title("下週一個動作")
            lede("只定一個，一次只改一件事。寫到「什麼時候、做什麼」。")
            VStack(spacing: 12) {
                TextField("什麼時候？例如：週二、週四下午會議後", text: $rv.when)
                    .field()
                TextField("做什麼？例如：先只打開專案檔十五分鐘", text: $rv.what)
                    .field()
            }
            PrimaryButton(title: "完成對帳", enabled: !rv.when.trimmed.isEmpty && !rv.what.trimmed.isEmpty) {
                rv.finish(store)
            }
            .padding(.top, 18)

        default:
            title(rv.view ? "這次的對帳" : "對帳完成")
            if !rv.view {
                lede("下週同一天見。")
            } else {
                Color.clear.frame(height: 10)
            }
            VStack(spacing: 12) {
                Quote(k: "記得的", text: rv.memory)
                if !rv.last.isEmpty { Quote(k: "上週動作", text: rv.last) }
                Quote(k: "差在哪", text: rv.gap.isEmpty ? "看不出差別" : rv.gap)
                if !rv.ai.added.isEmpty {
                    Quote(k: "新加的候選",
                          text: rv.ai.added.compactMap { $0 < rv.ai.cands.count ? rv.ai.cands[$0].name : nil }.joined(separator: "\n"))
                }
                Quote(k: "下週動作", text: "\(rv.when)，\(rv.what)")
            }
            PrimaryButton(title: "好") { close() }
                .padding(.top, 18)
        }
    }

    private var chatBlock: some View {
        let turns = rv.ai.chat.filter { $0.role == "user" && !$0.isHidden }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("跟 AI 聊")
                .font(.title3.bold())
                .padding(.top, 22)
            ForEach(Array(rv.ai.chat.enumerated()), id: \.offset) { pair in
                if !pair.element.isHidden {
                    Bubble(text: pair.element.content, me: pair.element.role == "user")
                }
            }
            if rv.busy {
                Bubble(text: "想一下", me: false, busy: true)
            }
            if turns < 5 {
                HStack(alignment: .bottom, spacing: 8) {
                    SayField(text: $chatText, placeholder: "回答它，或補充", lines: 1, font: .callout)
                    Button("送出") { send() }
                        .buttonStyle(SendStyle())
                        .disabled(rv.busy || chatText.trimmed.isEmpty)
                }
                .padding(.top, 10)
            } else {
                Text("聊到這裡就好。下一步把下週要做的實驗寫下來。")
                    .font(.footnote)
                    .foregroundStyle(T.fg2)
            }
        }
    }
}

struct Bubble: View {
    let text: String
    let me: Bool
    var busy = false

    var body: some View {
        HStack {
            if me { Spacer(minLength: 40) }
            HStack(spacing: 6) {
                if busy { ProgressView() }
                Text(text)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(me ? T.onAccent : T.fg)
            .background(me ? T.accent : T.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !me { Spacer(minLength: 40) }
        }
    }
}

/// 過去七天一排蒜 + 三段計數
struct WeekBlock: View {
    @Environment(AppStore.self) private var store
    let t: String

    var body: some View {
        let ks = DK.weekKeys(ending: t)
        let pk = ks.filter { store.s.days[$0]?.isSkip == false }
        let nf = ks.reduce(0) { $0 + store.frags($1).count }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(ks, id: \.self) { k in
                    VStack(spacing: 4) {
                        Group {
                            if let d = store.s.days[k] {
                                if d.isSkip {
                                    LeafGlyph()
                                } else {
                                    GarlicGlyph(rates: d.rates, seeds: store.seedCount(k))
                                }
                            } else {
                                EmptyGlyph()
                            }
                        }
                        .frame(maxWidth: 40)
                        Text(Seg.weekdays[DK.weekday(k)])
                            .font(.caption)
                            .foregroundStyle(T.fg2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(T.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    if i > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Text(Seg.names[i])
                            .font(.callout.weight(.semibold))
                            .frame(width: 44, alignment: .leading)
                        HStack(spacing: 12) {
                            ForEach(Rate.allCases, id: \.self) { r in
                                HStack(spacing: 4) {
                                    Circle().fill(T.rate(r)).frame(width: 8, height: 8)
                                    Text("\(r.rawValue) \(count(pk, i, r))")
                                }
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(T.fg2)
                        .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 6)
            .card()
            Text("這週剝了 \(pk.count) 天，白天說了 \(nf) 句。")
                .font(.footnote)
                .foregroundStyle(T.fg2)
                .padding(.horizontal, 4)
        }
    }

    private func count(_ pk: [String], _ i: Int, _ r: Rate) -> Int {
        pk.reduce(0) { acc, k in
            acc + ((store.s.days[k]?.segments?[i].r == r) ? 1 : 0)
        }
    }
}
