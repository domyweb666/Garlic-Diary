import SwiftUI

/// 主畫面那顆蒜在哪裡（籃子要知道新的一顆從哪掉下來）
struct HeroFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

/// 中間那頁：記一句、今天的蒜、剝的三步、底下的籃子
struct MainPage: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(PileModel.self) private var pile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var heroFrame: CGRect = .zero
    @State private var heroScale: CGFloat = 1
    @State private var fragsOpen = false

    var body: some View {
        ZStack {
            PileView(pile: pile)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 52)
                    .padding(.bottom, 240)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: ui.locked) { _, _ in
                    proxy.scrollTo("top", anchor: .top)
                }
            }
        }
        .coordinateSpace(.named("main"))
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("main")).onEnded { v in
                pile.nudge(at: v.location)
            }
        )
        .onPreferenceChange(HeroFrameKey.self) { heroFrame = $0 }
    }

    @ViewBuilder private var content: some View {
        let t = store.today
        let day = store.s.days[t]
        header(t: t, day: day)
        if let draft = ui.peel {
            PeelView(draft: draft,
                     seeds: store.seedCount(t),
                     fragsForSeg: store.frags(t).filter { $0.seg == draft.i }.count,
                     tags: store.s.settings.tags,
                     onChoose: { choose($0) },
                     onCancel: cancelPeel,
                     onPrev: prevSeg)
        } else if let day, day.isSkip {
            skippedState(t)
        } else if let day {
            doneState(t: t, day: day)
        } else {
            notYetState(t)
        }
    }

    private func header(t: String, day: DayEntry?) -> some View {
        let c = DK.components(t)
        var sub = "這個月記了 \(store.monthCount(c.y, c.m)) 天"
        if day == nil && store.isBack() { sub = "從今晚這顆開始。" }
        return VStack(alignment: .leading, spacing: 4) {
            Text(DK.heading(t))
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.body)
                .foregroundStyle(T.fg2)
        }
    }

    // MARK: - 三種狀態

    private func notYetState(_ t: String) -> some View {
        let seeds = store.seedCount(t)
        let n = seeds.reduce(0, +)
        let night = DK.isNight()
        return VStack(alignment: .leading, spacing: 0) {
            CaptureCard(onSaved: fragmentSaved)
            heroCard(rates: [nil, nil, nil], seeds: seeds, label: "還沒剝的蒜") {
                Text((n > 0 ? "今天記了 \(n) 句。" : "") + "在\(store.s.settings.anchor)之後，剝今天")
                    .font(.subheadline)
                    .foregroundStyle(T.fg2)
                    .multilineTextAlignment(.center)
            }
            fragList(t)
            if night {
                PrimaryButton(title: "剝今天") { startPeel(existing: nil) }
                    .padding(.top, 18)
            } else {
                SecondaryButton(title: "剝今天") { startPeel(existing: nil) }
                    .padding(.top, 14)
                Text("晚上那瓣還沒發生，睡前再剝比較準。")
                    .font(.footnote)
                    .foregroundStyle(T.fg2)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            TextLink(title: "今天不想剝") { skipToday() }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private func doneState(t: String, day: DayEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CaptureCard(onSaved: fragmentSaved)
            heroCard(rates: day.rates, seeds: store.seedCount(t), label: "今天的蒜") {
                Text(day.line ?? "今天收好了。")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            if let segs = day.segments {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        if i > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            Circle()
                                .fill(T.rate(segs[i].r))
                                .frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Seg.names[i])
                                Text(detail(segs[i]))
                                    .font(.subheadline)
                                    .foregroundStyle(T.fg2)
                            }
                            Spacer()
                            Text(segs[i].r.rawValue)
                                .foregroundStyle(T.fg2)
                        }
                        .rowFrame(minHeight: 52)
                    }
                }
                .card()
                .padding(.top, 14)
            }
            fragList(t)
            if store.reviewDue() {
                PillButton(title: "今天是對帳日 ›") { ui.review = ReviewFlow(open: store) }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            TextLink(title: "改一下") { startPeel(existing: day) }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private func skippedState(_ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CaptureCard(onSaved: fragmentSaved)
            VStack(spacing: 10) {
                LeafGlyph()
                    .frame(width: 112, height: 112)
                Text("今天不剝。")
                    .font(.title3.weight(.semibold))
                Text("不進統計，也不算斷掉。")
                    .font(.subheadline)
                    .foregroundStyle(T.fg2)
            }
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
            .card()
            .padding(.top, 14)
            fragList(t)
            TextLink(title: "還是剝一下") { unskip() }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private func heroCard<Content: View>(rates: [Rate?], seeds: [Int], label: String,
                                         @ViewBuilder caption: () -> Content) -> some View {
        VStack(spacing: 10) {
            GarlicGlyph(rates: rates, seeds: seeds, sprout: true, label: label)
                .frame(width: 112, height: 112)
                .scaleEffect(heroScale)
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeroFrameKey.self, value: g.frame(in: .named("main")))
                })
            caption()
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .card()
        .padding(.top, 14)
    }

    @ViewBuilder private func fragList(_ t: String) -> some View {
        let fs = store.frags(t)
        if !fs.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { fragsOpen.toggle() }
                } label: {
                    Text("今天說了 \(fs.count) 句 " + (fragsOpen ? "⌃" : "›"))
                        .font(.subheadline)
                        .foregroundStyle(T.fg2)
                        .frame(maxWidth: .infinity)
                        .padding(6)
                }
                .buttonStyle(.plain)
                if fragsOpen {
                    VStack(spacing: 0) {
                        ForEach(Array(fs.enumerated()), id: \.offset) { pair in
                            if pair.offset > 0 { RowDivider() }
                            HStack(alignment: .top, spacing: 10) {
                                Text(DK.hm(pair.element.ts))
                                    .font(.footnote)
                                    .foregroundStyle(T.fg2)
                                    .monospacedDigit()
                                    .padding(.top, 2)
                                Text(pair.element.t)
                                    .font(.subheadline)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                        }
                    }
                    .card()
                }
            }
            .padding(.top, 10)
        }
    }

    private func detail(_ s: SegmentRecord) -> String {
        var d = s.t.isEmpty ? "—" : s.t
        if !s.tags.isEmpty { d += " · " + s.tags.joined(separator: "、") }
        return d
    }

    // MARK: - 動作

    private var heroPoint: CGPoint? {
        heroFrame == .zero ? nil : CGPoint(x: heroFrame.midX, y: heroFrame.midY)
    }

    private func fragmentSaved(_ key: String) {
        pile.updateSeeds(key: key, seeds: store.seedCount(key))
    }

    private func startPeel(existing: DayEntry?) {
        let d = PeelDraft()
        if let segs = existing?.segments {
            d.s = segs.map { SegDraft(r: $0.r, t: $0.t, tags: $0.tags) }
            d.edit = true
        }
        Feedback.shared.warmUp()
        withAnimation(.easeInOut(duration: 0.25)) {
            ui.peel = d
            pile.dim = true
        }
    }

    private func cancelPeel() {
        withAnimation(.easeInOut(duration: 0.25)) {
            ui.peel = nil
            pile.dim = false
        }
    }

    private func prevSeg() {
        guard let d = ui.peel, d.i > 0 else { return }
        d.i -= 1
    }

    private func choose(_ r: Rate) {
        guard let d = ui.peel else { return }
        d.s[d.i].r = r
        Feedback.shared.tick()
        if d.i < 2 {
            d.i += 1
            return
        }
        let segs = d.s.map { SegmentRecord(r: $0.r ?? r, t: $0.t.trimmed, tags: $0.tags) }
        let t = store.today
        store.savePeel(segs, edit: d.edit)
        withAnimation(.easeInOut(duration: 0.25)) {
            ui.peel = nil
            pile.dim = false
        }
        heroScale = 0.86
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.spring(duration: 0.55, bounce: 0.45)) { heroScale = 1 }
        }
        Feedback.shared.done()
        let delay = reduceMotion ? 0.0 : 0.52
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let e = store.s.days[t] {
                pile.drop(key: t, entry: e, seeds: store.seedCount(t), from: heroPoint)
            }
        }
    }

    private func skipToday() {
        let t = store.today
        store.skipToday()
        if let e = store.s.days[t] {
            pile.drop(key: t, entry: e, seeds: store.seedCount(t), from: heroPoint)
        }
    }

    private func unskip() {
        let t = store.today
        store.unskipToday()
        pile.remove(key: t)
        startPeel(existing: nil)
    }
}

// MARK: - 記一句

struct CaptureCard: View {
    @Environment(AppStore.self) private var store
    @Environment(SpeechService.self) private var speech
    @Environment(Toaster.self) private var toaster

    var onSaved: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let seg = Seg.names[DK.segNow()]
        let empty = text.trimmed.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            TextField("現在在做什麼？說一句就好", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .font(.title3)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($focused)
            HStack(spacing: 10) {
                if speech.supported {
                    Button {
                        speech.toggle(base: text) { text = $0 }
                    } label: {
                        Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(speech.isRecording ? Color.white : T.fg)
                            .frame(width: 44, height: 44)
                            .background(speech.isRecording ? T.danger : T.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(speech.isRecording ? "停止收音" : "用說的"))
                }
                Text("會記在今天「\(seg)」那一瓣" + (speech.supported ? "" : "，按鍵盤上的麥克風就能用說的"))
                    .font(.footnote)
                    .foregroundStyle(T.fg2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("記下") { save() }
                    .buttonStyle(SendStyle())
                    .disabled(empty)
            }
        }
        .padding(14)
        .card()
        .padding(.top, 18)
        .onChange(of: speech.lastError) { _, e in
            if let e {
                toaster.show(e)
                speech.lastError = nil
            }
        }
    }

    private func save() {
        let v = text.trimmed
        guard !v.isEmpty else { return }
        if speech.isRecording { speech.finish() }
        let seg = store.addFragment(v)
        text = ""
        focused = false
        Feedback.shared.seed()
        toaster.show("記下了，落在「\(Seg.names[seg])」")
        onSaved(store.today)
    }
}

// MARK: - 剝的三步

struct PeelView: View {
    let draft: PeelDraft
    let seeds: [Int]
    let fragsForSeg: Int
    let tags: [TagDef]
    let onChoose: (Rate) -> Void
    let onCancel: () -> Void
    let onPrev: () -> Void

    var body: some View {
        @Bindable var draft = draft
        let i = draft.i
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    GarlicGlyph(rates: draft.s.map { $0.r }, seeds: seeds, active: i)
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Seg.names[i])
                            .font(.title.bold())
                        Text("\(i + 1) / 3　順不順？")
                            .font(.subheadline)
                            .foregroundStyle(T.fg2)
                    }
                }
                if fragsForSeg > 0 {
                    Text("這段白天說過 \(fragsForSeg) 句。")
                        .font(.footnote)
                        .foregroundStyle(T.fg2)
                }
                TextField("補一句那段發生了什麼？（可以不寫）", text: $draft.s[i].t, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.title3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(tags, id: \.name) { tg in
                            Chip(title: tg.name, pressed: draft.s[i].tags.contains(tg.name)) {
                                toggleTag(tg.name)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .card()
            .padding(.top, 22)

            HStack(spacing: 10) {
                ForEach(Rate.allCases, id: \.self) { r in
                    Button {
                        onChoose(r)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.white.opacity(r == .good ? 1 : (r == .mid ? 0.75 : 0.55)))
                                .frame(width: 22, height: 22)
                            Text(r.rawValue)
                                .font(.title2.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .background(T.choiceGradient(r), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Text("\(Seg.names[i])：\(r.rawValue)"))
                }
            }
            .padding(.top, 14)

            HStack {
                if i > 0 {
                    TextLink(title: "‹ 上一段", action: onPrev)
                } else {
                    Spacer()
                }
                Spacer()
                TextLink(title: "先不剝", action: onCancel)
            }
            .padding(.top, 8)
        }
    }

    private func toggleTag(_ name: String) {
        var tags = draft.s[draft.i].tags
        if let k = tags.firstIndex(of: name) {
            tags.remove(at: k)
        } else {
            tags.append(name)
        }
        draft.s[draft.i].tags = tags
    }
}
