import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// 右邊那頁
struct SettingsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(PileModel.self) private var pile
    @Environment(Toaster.self) private var toaster

    @State private var keyText = ""
    @State private var modelText = ""
    @State private var restartText = ""
    @State private var tagFormOpen = false
    @State private var tagName = ""
    @State private var tagDef = ""
    @State private var confirmClear = false
    @State private var showAsk = false
    @State private var showImport = false
    @State private var showBackupText = false
    @State private var backupText = ""
    @State private var shareItem: ShareItem?
    @FocusState private var keyFocused: Bool
    @FocusState private var modelFocused: Bool
    @FocusState private var restartFocused: Bool
    @FocusState private var tagNameFocused: Bool

    private let anchors = ["刷完牙", "關燈前", "躺上床前"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("設定")
                    .font(.largeTitle.bold())
                dailySection
                weeklySection
                aiSection
                tagsSection
                restartSection
                dataSection
                logSection
                Text("蒜數 0.4 · iOS")
                    .font(.footnote)
                    .foregroundStyle(T.fg2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: refreshFields)
        .onChange(of: store.s.settings) { _, _ in
            store.save()
            store.syncFeedbackFlags()
            Reminders.reschedule(store.s)
        }
        .onChange(of: store.s.ai) { _, _ in store.save() }
        .onChange(of: keyFocused) { _, f in if !f { commitKey() } }
        .onChange(of: modelFocused) { _, f in if !f { commitModel() } }
        .onChange(of: restartFocused) { _, f in if !f { commitRestart() } }
        .sheet(isPresented: $showAsk) {
            AskAnchorSheet(initial: anchors.contains(store.s.settings.anchor) ? "" : store.s.settings.anchor) { v in
                setAnchor(v)
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSheet { data in try importData(data) }
        }
        .sheet(isPresented: $showBackupText) {
            BackupTextSheet(text: backupText)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
    }

    // MARK: - 每天

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("每天")
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("在什麼之後剝今天")
                    FlowLayout(spacing: 6) {
                        ForEach(anchors, id: \.self) { a in
                            Chip(title: a, pressed: store.s.settings.anchor == a) { setAnchor(a) }
                        }
                        Chip(title: anchors.contains(store.s.settings.anchor) ? "自己寫" : store.s.settings.anchor,
                             pressed: !anchors.contains(store.s.settings.anchor)) { showAsk = true }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                RowDivider()
                HStack {
                    Text("提醒")
                    Spacer()
                    Toggle("提醒", isOn: remindBinding).labelsHidden()
                }
                .rowFrame()
                if store.s.settings.remindEnabled {
                    RowDivider()
                    HStack {
                        Text("提醒時間")
                        Spacer()
                        DatePicker("提醒時間", selection: remindDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .rowFrame()
                }
                RowDivider()
                HStack {
                    Text("聲音")
                    Spacer()
                    Toggle("聲音", isOn: Binding(get: { store.s.settings.sound },
                                                set: { store.s.settings.sound = $0 }))
                        .labelsHidden()
                }
                .rowFrame()
                RowDivider()
                HStack {
                    Text("觸覺")
                    Spacer()
                    Toggle("觸覺", isOn: Binding(get: { store.s.settings.hapticsEnabled },
                                                set: { store.s.settings.hapticsEnabled = $0 }))
                        .labelsHidden()
                }
                .rowFrame()
            }
            .card()
            FootNote("提醒一天只響一次；剝過的那天不會響。")
        }
    }

    private var remindBinding: Binding<Bool> {
        Binding(get: { store.s.settings.remindEnabled }, set: { on in
            if !on {
                store.s.settings.remindEnabled = false
                return
            }
            Reminders.requestPermission { ok in
                if ok {
                    store.s.settings.remindEnabled = true
                } else {
                    toaster.show("通知沒有打開。到 iPhone「設定」→「蒜數」允許通知，再回來開。")
                }
            }
        })
    }

    private var remindDate: Binding<Date> {
        Binding(get: {
            let p = store.s.settings.remind.split(separator: ":").compactMap { Int($0) }
            var dc = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            dc.hour = p.count == 2 ? p[0] : 22
            dc.minute = p.count == 2 ? p[1] : 30
            return Calendar.current.date(from: dc) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            let v = String(format: "%02d:%02d", c.hour ?? 22, c.minute ?? 30)
            if v != store.s.settings.remind {
                store.s.settings.remind = v
                store.logChange("提醒時間改成 \(v)")
            }
        })
    }

    // MARK: - 每週

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("每週")
            VStack(spacing: 0) {
                HStack {
                    Text("對帳日")
                    Spacer()
                    Picker("對帳日", selection: Binding(get: { store.s.settings.reviewDay }, set: { v in
                        guard v != store.s.settings.reviewDay else { return }
                        store.s.settings.reviewDay = v
                        store.logChange("對帳日改成週\(Seg.weekdays[v])")
                    })) {
                        ForEach(0..<7, id: \.self) { i in
                            Text("週\(Seg.weekdays[i])").tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(T.fg2)
                }
                .rowFrame()
            }
            .card()
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("AI 對帳（雲端）")
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anthropic API 金鑰")
                    SecureField("sk-ant-…", text: $keyText)
                        .field()
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($keyFocused)
                        .onSubmit { commitKey() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                RowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("模型")
                    TextField(AIClient.defaultModel, text: $modelText)
                        .field()
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($modelFocused)
                        .onSubmit { commitModel() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                RowDivider()
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("試用：提早開放 AI 候選")
                        Text("書的建議是前三週先累積資料，不找模式")
                            .font(.subheadline)
                            .foregroundStyle(T.fg2)
                    }
                    Spacer()
                    Toggle("提早開放", isOn: Binding(get: { store.s.ai.early }, set: { v in
                        store.s.ai.early = v
                        store.logChange(v ? "提早開放 AI 候選（試用）" : "關閉提早開放 AI 候選")
                    }))
                    .labelsHidden()
                }
                .rowFrame()
            }
            .card()
            FootNote("只有在週對帳按下「請 AI 讀」時，最近四週的語音文字和評分才會送到 Anthropic。金鑰放在這支手機的 Keychain，匯出備份不含金鑰。")
        }
    }

    // MARK: - 標籤

    private var tagsSection: some View {
        let tags = store.s.settings.tags
        return VStack(alignment: .leading, spacing: 0) {
            GroupLabel("情境標籤")
            VStack(spacing: 0) {
                ForEach(Array(tags.enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.element.name)
                            Text(pair.element.def)
                                .font(.subheadline)
                                .foregroundStyle(T.fg2)
                        }
                        Spacer()
                        PillButton(title: "移除") { removeTag(pair.offset) }
                    }
                    .rowFrame()
                }
                if tagFormOpen {
                    if !tags.isEmpty { RowDivider() }
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("標籤名，例如：會議", text: $tagName)
                            .field()
                            .focused($tagNameFocused)
                            .onChange(of: tagName) { _, v in
                                if v.count > 8 { tagName = String(v.prefix(8)) }
                            }
                        TextField("一行定義，例如：超過十五分鐘、有固定時間的通話或見面", text: $tagDef)
                            .field()
                        HStack(spacing: 8) {
                            MiniButton(title: "加入") { addTag() }
                            MiniButton(title: "取消", ghost: true) {
                                tagFormOpen = false
                                tagName = ""
                                tagDef = ""
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))
                } else if tags.count < 5 {
                    if !tags.isEmpty { RowDivider() }
                    Button {
                        tagFormOpen = true
                        tagNameFocused = true
                    } label: {
                        Text("新增標籤")
                            .foregroundStyle(T.accent)
                            .rowFrame()
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            .card()
            FootNote("最多五個，每個都要寫一行定義。前兩週先不用，第三週再開比較好；一季之內不改定義，不然前後的數字對不起來。")
        }
    }

    // MARK: - 斷掉的時候

    private var restartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("斷掉的時候")
            TextField("斷掉那天要照做的一句話", text: $restartText, axis: .vertical)
                .lineLimit(2...5)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($restartFocused)
                .padding(12)
                .card()
            FootNote("這條規則現在寫好，斷掉那天就不用重想。")
        }
    }

    // MARK: - 資料

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("資料")
            VStack(spacing: 0) {
                actionRow("匯出備份檔") { exportFile() }
                RowDivider()
                actionRow("複製備份文字") { copyBackup() }
                RowDivider()
                actionRow("匯入備份") { showImport = true }
                if store.isEmpty {
                    RowDivider()
                    Button {
                        loadDemo()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("看看一個月後的樣子")
                                .foregroundStyle(T.accent)
                            Text("載入示範資料，看完可以清除")
                                .font(.subheadline)
                                .foregroundStyle(T.fg2)
                        }
                        .rowFrame()
                    }
                    .buttonStyle(RowButtonStyle())
                }
                RowDivider()
                Button {
                    wipe()
                } label: {
                    Text(confirmClear ? "再按一次，清除全部" : "清除全部資料")
                        .foregroundStyle(T.danger)
                        .rowFrame()
                }
                .buttonStyle(RowButtonStyle())
            }
            .card()
            FootNote("資料存在這支手機的 app 裡，會跟著 iCloud 備份走。換手機前先匯出一份比較穩。")
        }
    }

    private func actionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(T.accent)
                .rowFrame()
        }
        .buttonStyle(RowButtonStyle())
    }

    // MARK: - 紀錄

    @ViewBuilder private var logSection: some View {
        if !store.s.log.isEmpty {
            GroupLabel("系統調整紀錄")
            VStack(spacing: 0) {
                ForEach(Array(store.s.log.prefix(10).enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 { RowDivider() }
                    Text("\(pair.element.d)｜\(pair.element.what)")
                        .font(.subheadline)
                        .foregroundStyle(T.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
            }
            .card()
        }
    }

    // MARK: - 動作

    private func refreshFields() {
        keyText = store.apiKey
        modelText = store.s.ai.model
        restartText = store.s.settings.restart
    }

    private func setAnchor(_ v: String) {
        let a = v.trimmed
        guard !a.isEmpty, a != store.s.settings.anchor else { return }
        store.s.settings.anchor = a
        store.logChange("錨點改成「\(a)」")
    }

    private func commitKey() {
        let v = keyText.trimmed
        guard v != store.apiKey else { return }
        store.setApiKey(v)
        keyText = store.apiKey
        toaster.show(v.isEmpty ? "金鑰清掉了" : "金鑰存好了")
    }

    private func commitModel() {
        let v = modelText.trimmed
        let m = v.isEmpty ? AIClient.defaultModel : v
        modelText = m
        if m != store.s.ai.model { store.s.ai.model = m }
    }

    private func commitRestart() {
        let v = restartText.trimmed
        let r = v.isEmpty ? Settings().restart : v
        restartText = r
        if r != store.s.settings.restart { store.s.settings.restart = r }
    }

    private func addTag() {
        let n = tagName.trimmed
        let d = tagDef.trimmed
        guard !n.isEmpty, !d.isEmpty else { return }
        store.s.settings.tags.append(TagDef(name: n, def: d, added: store.today))
        store.logChange("新增標籤「\(n)」：\(d)")
        tagFormOpen = false
        tagName = ""
        tagDef = ""
    }

    private func removeTag(_ i: Int) {
        guard i < store.s.settings.tags.count else { return }
        let tg = store.s.settings.tags.remove(at: i)
        store.logChange("移除標籤「\(tg.name)」")
    }

    private func wipe() {
        if !confirmClear {
            confirmClear = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { confirmClear = false }
            return
        }
        confirmClear = false
        store.wipeAll()
        ui.peel = nil
        pile.dim = false
        ui.viewMonth = nil
        pile.requestRebuild()
        refreshFields()
        toaster.show("清掉了")
    }

    private func loadDemo() {
        store.loadDemo()
        ui.viewMonth = nil
        pile.requestRebuild()
        withAnimation(.easeInOut(duration: 0.3)) { ui.page = 0 }
        toaster.show("示範資料載好了，這是籃子頁")
    }

    private func exportFile() {
        let data = store.backupData()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("蒜數備份-\(store.today).json")
        do {
            try data.write(to: url, options: [.atomic])
            shareItem = ShareItem(url: url)
        } catch {
            toaster.show("匯出失敗，改用「複製備份文字」")
        }
    }

    private func copyBackup() {
        let t = String(decoding: store.backupData(), as: UTF8.self)
        UIPasteboard.general.string = t
        backupText = t
        toaster.show("備份文字已複製，貼到備忘錄存著")
    }

    private func importData(_ data: Data) throws {
        try store.importBackup(data)
        ui.peel = nil
        pile.dim = false
        ui.viewMonth = nil
        pile.requestRebuild()
        refreshFields()
        toaster.show("匯入好了")
    }
}

// MARK: - 小 sheet

struct AskAnchorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: String
    let onDone: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("在什麼之後剝今天？")
                    .font(.title.bold())
                TextField("例如：洗完澡", text: $text)
                    .field()
                    .focused($focused)
                    .onSubmit { done() }
                PrimaryButton(title: "好", enabled: !text.trimmed.isEmpty) { done() }
                Spacer()
            }
            .padding(16)
            .background(T.bg.ignoresSafeArea())
            .navigationTitle("錨點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                text = initial
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func done() {
        let v = text.trimmed
        guard !v.isEmpty else { return }
        onDone(v)
        dismiss()
    }
}

struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: (Data) throws -> Void

    @State private var text = ""
    @State private var err: String?
    @State private var picker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("選備份檔，或把備份文字貼進來。匯入會取代這支手機上現在的資料（AI 金鑰保留）。")
                        .font(.callout)
                        .foregroundStyle(T.fg2)
                    SecondaryButton(title: "選備份檔") { picker = true }
                    TextEditor(text: $text)
                        .font(.footnote)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("或貼上備份文字")
                                    .font(.footnote)
                                    .foregroundStyle(T.fg3)
                                    .padding(16)
                                    .allowsHitTesting(false)
                            }
                        }
                    if let err {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(T.danger)
                    }
                    PrimaryButton(title: "匯入", enabled: !text.trimmed.isEmpty) { run() }
                }
                .padding(16)
            }
            .background(T.bg.ignoresSafeArea())
            .navigationTitle("匯入備份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.json, .plainText, .data]) { result in
                guard case .success(let url) = result else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url), let s = String(data: d, encoding: .utf8) {
                    text = s
                    err = nil
                } else {
                    err = "讀不到這個檔。"
                }
            }
        }
    }

    private func run() {
        do {
            try onImport(Data(text.utf8))
            dismiss()
        } catch {
            err = "讀不懂這份備份。確認貼上的是完整的備份文字，從 { 開始、到 } 結束。"
        }
    }
}

struct BackupTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("全選後複製，貼到備忘錄存著。")
                        .font(.callout)
                        .foregroundStyle(T.fg2)
                    Text(text)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(T.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(16)
            }
            .background(T.bg.ignoresSafeArea())
            .navigationTitle("備份文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }
}

/// 系統分享面板
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
