import SwiftUI

/// 左邊那頁：月曆、三段的數字、候選清單、我知道的自己、週對帳
struct BasketPage: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(PileModel.self) private var pile

    var body: some View {
        let t = store.today
        let tc = DK.components(t)
        let ym = ui.viewMonth ?? YM(y: tc.y, m: tc.m)
        let isCur = ym.y == tc.y && ym.m == tc.m
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("籃子")
                        .font(.largeTitle.bold())
                    Text((isCur ? "這個月" : "\(ym.m) 月") + "記了 \(store.monthCount(ym.y, ym.m)) 天")
                        .font(.body)
                        .foregroundStyle(T.fg2)
                }
                if store.s.demo { demoBanner }
                monthCard(ym: ym, today: t, isCur: isCur)
                SectionTitle("三段的數字")
                countsCard(ym: ym)
                FootNote(store.dayN() <= 21 && !store.s.demo
                         ? "第 \(store.dayN()) 天。前三週只看數字，先不找模式。"
                         : "只算有剝的日子；葉子和空格不算進來。")
                SectionTitle("候選清單")
                candidates(t)
                SectionTitle("我知道的自己")
                known
                SectionTitle("週對帳")
                reviews(t)
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
            .padding(.bottom, 40)
        }
    }

    private var demoBanner: some View {
        HStack {
            Text("正在看示範資料")
                .font(.subheadline)
                .foregroundStyle(T.fg2)
            Spacer()
            Button("清除示範") {
                store.clearDemo()
                ui.viewMonth = nil
                pile.requestRebuild()
            }
            .font(.subheadline)
            .foregroundStyle(T.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 14)
    }

    // MARK: - 月曆

    private func monthCard(ym: YM, today t: String, isCur: Bool) -> some View {
        let days = DK.daysInMonth(ym.y, ym.m)
        let lead = DK.firstWeekday(ym.y, ym.m)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 0) {
            HStack {
                Button {
                    shiftMonth(ym, -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(RoundIconStyle())
                .accessibilityLabel(Text("上個月"))
                Spacer()
                Text("\(String(ym.y)) 年 \(ym.m) 月")
                    .font(.body.weight(.semibold))
                Spacer()
                Button {
                    shiftMonth(ym, 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(RoundIconStyle())
                .disabled(isCur)
                .accessibilityLabel(Text("下個月"))
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Seg.weekdays[i])
                        .font(.caption)
                        .foregroundStyle(T.fg2)
                }
                ForEach(0..<lead, id: \.self) { _ in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
                ForEach(1...days, id: \.self) { dd in
                    dayCell(DK.key(ym.y, ym.m, dd), dd: dd, today: t)
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 16, trailing: 12))
        .card()
        .padding(.top, 20)
    }

    private func dayCell(_ k: String, dd: Int, today t: String) -> some View {
        let day = store.s.days[k]
        let future = k > t
        let seeds = store.seedCount(k)
        return ZStack(alignment: .bottomTrailing) {
            Group {
                if future {
                    Color.clear
                } else if let day {
                    if day.isSkip {
                        LeafGlyph()
                    } else {
                        GarlicGlyph(rates: day.rates, seeds: seeds)
                    }
                } else if !store.frags(k).isEmpty {
                    GarlicGlyph(rates: [nil, nil, nil], seeds: seeds)
                } else {
                    EmptyGlyph()
                }
            }
            .padding(2)
            Text("\(dd)")
                .font(.system(size: 10))
                .foregroundStyle(T.fg3)
                .monospacedDigit()
                .offset(x: -1, y: 1)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if k == t {
                Circle().strokeBorder(T.accent, lineWidth: 1.5).padding(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(cellLabel(k: k, dd: dd, day: day, future: future)))
    }

    private func cellLabel(k: String, dd: Int, day: DayEntry?, future: Bool) -> String {
        if future { return "\(dd) 日" }
        guard let day else {
            let n = store.frags(k).count
            return n > 0 ? "\(dd) 日，說了 \(n) 句，沒剝" : "\(dd) 日，沒剝"
        }
        if day.isSkip { return "\(dd) 日，今天不剝" }
        let r = day.rates.map { $0?.rawValue ?? "" }.joined(separator: "、")
        return "\(dd) 日，\(r)"
    }

    private func shiftMonth(_ ym: YM, _ d: Int) {
        var y = ym.y
        var m = ym.m + d
        if m < 1 {
            m = 12
            y -= 1
        }
        if m > 12 {
            m = 1
            y += 1
        }
        ui.viewMonth = YM(y: y, m: m)
    }

    // MARK: - 三段的數字

    private func countsCard(ym: YM) -> some View {
        let pre = DK.monthPrefix(ym.y, ym.m)
        let ks = store.peeledKeys().filter { $0.hasPrefix(pre) }
        let tot = CGFloat(max(ks.count, 1))
        return VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                let c = counts(ks, seg: i)
                if i > 0 { RowDivider() }
                HStack(alignment: .center, spacing: 12) {
                    Text(Seg.names[i])
                        .font(.callout.weight(.semibold))
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { g in
                            HStack(spacing: 0) {
                                ForEach(Rate.allCases, id: \.self) { r in
                                    Rectangle()
                                        .fill(T.rate(r))
                                        .frame(width: g.size.width * CGFloat(c[r] ?? 0) / tot)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: 12)
                        .background(T.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        HStack(spacing: 12) {
                            ForEach(Rate.allCases, id: \.self) { r in
                                HStack(spacing: 4) {
                                    Circle().fill(T.rate(r)).frame(width: 8, height: 8)
                                    Text("\(r.rawValue) \(c[r] ?? 0)")
                                }
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(T.fg2)
                        .monospacedDigit()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
        .padding(.vertical, 6)
        .card()
    }

    private func counts(_ ks: [String], seg i: Int) -> [Rate: Int] {
        var c: [Rate: Int] = [.good: 0, .mid: 0, .bad: 0]
        for k in ks {
            if let segs = store.s.days[k]?.segments {
                c[segs[i].r, default: 0] += 1
            }
        }
        return c
    }

    // MARK: - 候選與已知

    @ViewBuilder private func candidates(_ t: String) -> some View {
        let live = store.liveCands()
        if live.isEmpty {
            FootNote(store.aiOpen
                     ? "還沒有候選。週對帳時請 AI 讀你的語音，它會提幾條。"
                     : "還沒有候選。第三週起，週對帳會請 AI 讀你的語音提候選。")
        } else {
            VStack(spacing: 0) {
                ForEach(live) { c in
                    if c.id != live.first?.id { RowDivider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name)
                            Text(c.pred)
                                .font(.subheadline)
                                .foregroundStyle(T.fg2)
                            Text("判決日 \(c.verdict)" + (c.verdict <= t ? "，已經到了，週對帳時判" : ""))
                                .font(.subheadline)
                                .foregroundStyle(T.fg2)
                        }
                        Spacer()
                        StatusTag(text: "觀察中")
                    }
                    .rowFrame()
                }
            }
            .card()
        }
    }

    @ViewBuilder private var known: some View {
        let list = store.knownCands()
        if list.isEmpty {
            FootNote("只放預測真的成立過的條目。現在是空的，這是正常的。")
        } else {
            VStack(spacing: 0) {
                ForEach(list) { c in
                    if c.id != list.first?.id { RowDivider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name)
                            Text("\(c.pred)｜\(c.passed ?? "") 通過")
                                .font(.subheadline)
                                .foregroundStyle(T.fg2)
                        }
                        Spacer()
                        StatusTag(text: "通過", pass: true)
                    }
                    .rowFrame()
                }
            }
            .card()
        }
    }

    // MARK: - 週對帳

    private func reviews(_ t: String) -> some View {
        let done = store.s.reviews[t]?.done ?? false
        let past = Array(store.s.reviews.filter { $0.value.done }.map { $0.key }.sorted(by: >).prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    ui.review = ReviewFlow(open: store)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(done ? "這週對過了" : "做這週的對帳")
                            Text("對帳日：每週\(Seg.weekdays[store.s.settings.reviewDay])，大約二十分鐘")
                                .font(.subheadline)
                                .foregroundStyle(T.fg2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(T.fg3)
                    }
                    .rowFrame()
                }
                .buttonStyle(RowButtonStyle())
                ForEach(past, id: \.self) { k in
                    RowDivider()
                    Button {
                        ui.review = ReviewFlow(past: k, store: store)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(DK.short(k)) 的對帳")
                                Text("下週動作：\(store.s.reviews[k]?.action.when ?? "")，\(store.s.reviews[k]?.action.what ?? "")")
                                    .font(.subheadline)
                                    .foregroundStyle(T.fg2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(T.fg3)
                        }
                        .rowFrame()
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            .card()
            FootNote("對帳沒有本週摘要。它只留下記憶跟紀錄差在哪、判決過的候選，和下週一個動作。")
        }
    }
}
