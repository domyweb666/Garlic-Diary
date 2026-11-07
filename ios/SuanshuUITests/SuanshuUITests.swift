import XCTest

/// 在模擬器上把蒜數的主流程走一遍，每個畫面截一張圖。
///
/// 截圖兩份：
/// - XCTAttachment 進 .xcresult（lifetime = .keepAlways），Xcode 裡點開每一步就看得到。
/// - 環境變數 SUANSHU_SCREENSHOT_DIR 有值時，直接寫 PNG 到那個資料夾，沒有 Xcode 也能看。
///   xcodebuild test 用 TEST_RUNNER_SUANSHU_SCREENSHOT_DIR=… 傳進來；模擬器裡的程序看得到主機的檔案系統。
///
/// 流程：首次打開三步 → 記一句 → 剝三瓣 → 籃子頁 → 週對帳走到完成 → 設定頁清除全部 → 載示範資料 → 回剝今天頁。
final class SuanshuUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shotIndex = 0
    private var shotDir: URL?
    private var swallowing = false
    private var swallowed: [String] = []

    private enum Page {
        case basket, main, settings
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        if let dir = ProcessInfo.processInfo.environment["SUANSHU_SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            shotDir = url
        }
        // 萬一跳出系統對話框（通知、麥克風……），按同意讓流程走下去
        addUIInterruptionMonitor(withDescription: "系統對話框") { alert in
            for title in ["Allow", "允許", "OK", "好", "Allow While Using App"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            let first = alert.buttons.firstMatch
            guard first.exists else { return false }
            first.tap()
            return true
        }
    }

    override func tearDownWithError() throws {
        if !swallowed.isEmpty {
            note("吞掉的失敗（那一段已改打英文重來）：\n" + swallowed.joined(separator: "\n"))
        }
    }

    /// 打中文偶爾會被 XCTest 判失敗（模擬器的鍵盤是英文的）。
    /// 打字那一段的失敗先吞下來，確認欄位真的沒字再改打英文，不讓整支測試因此中斷。
    override func record(_ issue: XCTIssue) {
        if swallowing {
            swallowed.append(issue.compactDescription)
            return
        }
        super.record(issue)
    }

    // MARK: - 主流程

    func testMainFlow() throws {
        app.launch()

        // 首次打開三步（模擬器是乾淨的，一定會看到；本機重跑時可能已經過了）
        let ok = button("好")
        if ok.waitForExistence(timeout: 20) {
            shot("onboarding-1")
            ok.tap()
            XCTAssertTrue(button("關燈前").waitForExistence(timeout: 5), "首次打開第二步沒出現")
            shot("onboarding-2-anchor")
            button("關燈前").tap()
            button("下一步").tap()
            XCTAssertTrue(button("記住了，開始").waitForExistence(timeout: 5), "首次打開第三步沒出現")
            shot("onboarding-3-restart")
            button("記住了，開始").tap()
        } else {
            note("沒看到首次打開的畫面（app 之前開過），直接走主流程")
        }

        // 主畫面：記一句
        let capture = field(id: "capture-field", placeholder: "現在在做什麼？說一句就好")
        XCTAssertTrue(capture.waitForExistence(timeout: 10), "主畫面的輸入欄不存在")
        settle()
        // 一打開停在哪一頁，先留一張。從 main 建的版本會停在籃子頁（頁點卻亮中間那顆）。
        shot("after-onboarding")
        goTo(.main)
        shot("main-empty")
        typeInto(capture, "下午跟合作方開會，講了一個多小時", fallback: "meeting with partner, one hour")
        shot("main-typed")
        button("記下").tap()
        let saved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "今天說了")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "按「記下」之後沒看到「今天說了 N 句」")
        shot("main-fragment-saved")

        // 剝今天：三瓣
        reveal(peelButton)
        peelButton.tap()
        XCTAssertTrue(button("上午：順").waitForExistence(timeout: 5), "沒進到剝的第一步")
        shot("peel-1-morning")
        button("上午：順").tap()
        XCTAssertTrue(button("下午：普通").waitForExistence(timeout: 5), "沒進到剝的第二步")
        shot("peel-2-afternoon")
        button("下午：普通").tap()
        XCTAssertTrue(button("晚上：卡").waitForExistence(timeout: 5), "沒進到剝的第三步")
        shot("peel-3-night")
        button("晚上：卡").tap()
        XCTAssertTrue(button("改一下").waitForExistence(timeout: 5), "剝完沒回到完成狀態")
        Thread.sleep(forTimeInterval: 2) // 完成語、蒜頭彈一下、掉進籃子
        shot("main-done-with-basket")

        // 籃子頁
        goTo(.basket)
        shot("basket-top")
        let reviewRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "做這週的對帳")).firstMatch
        XCTAssertTrue(reviewRow.waitForExistence(timeout: 5), "籃子頁找不到「做這週的對帳」")
        reveal(reviewRow)
        shot("basket-bottom")
        reviewRow.tap()

        // 週對帳：記憶 → 看紀錄 → 差在哪 → 下週一個動作 → 完成
        let memory = field(id: "review-memory", placeholder: "例如：這週還行，週三很爛。")
        XCTAssertTrue(memory.waitForExistence(timeout: 5), "對帳沒打開")
        shot("review-1-memory")
        typeInto(memory, "這週還行，週三很爛", fallback: "ok week, bad wednesday")
        button("打開這週的紀錄").tap()
        XCTAssertTrue(app.staticTexts["看紀錄"].waitForExistence(timeout: 5), "對帳沒走到「看紀錄」")
        shot("review-2-records")
        button("下一步").tap()
        XCTAssertTrue(button("看不出差別").waitForExistence(timeout: 5), "對帳沒走到「差在哪」")
        shot("review-3-gap")
        button("看不出差別").tap()
        button("下一步").tap()
        let when = field(id: "review-when", placeholder: "什麼時候？例如：週二、週四下午會議後")
        XCTAssertTrue(when.waitForExistence(timeout: 5), "對帳沒走到「下週一個動作」")
        shot("review-4-action-empty")
        typeInto(when, "週二下午", fallback: "tuesday afternoon")
        typeInto(field(id: "review-what", placeholder: "做什麼？例如：先只打開專案檔十五分鐘"),
                 "先只打開專案檔十五分鐘", fallback: "open the project file for 15 minutes")
        shot("review-4-action-filled")
        button("完成對帳").tap()
        XCTAssertTrue(app.staticTexts["對帳完成"].waitForExistence(timeout: 5), "按「完成對帳」之後沒看到完成頁")
        shot("review-5-done")
        button("好").tap()
        settle()
        shot("basket-after-review")

        // 設定頁：清除全部，再載示範資料
        goTo(.settings)
        shot("settings-top")
        let clear = app.buttons
            .matching(NSPredicate(format: "label IN %@", ["清除全部資料", "再按一次，清除全部"] as NSArray)).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "設定頁找不到「清除全部資料」")
        reveal(clear)
        shot("settings-bottom")
        let demo = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "看看一個月後的樣子")).firstMatch
        var wiped = false
        for attempt in 0..<3 where !wiped {
            clear.tap() // 第一下變成「再按一次，清除全部」，四秒內要按第二下
            if attempt == 0 { shot("settings-clear-armed") }
            clear.tap()
            wiped = demo.waitForExistence(timeout: 3) // 資料清空之後才會出現這一列
        }
        XCTAssertTrue(wiped, "按兩次「清除全部資料」之後沒出現「看看一個月後的樣子」")
        shot("settings-after-wipe")
        reveal(demo)
        demo.tap() // 載好會自己跳到籃子頁
        settle()
        Thread.sleep(forTimeInterval: 2) // 等籃子裡那堆蒜落定
        shot("basket-demo")
        goTo(.main)
        Thread.sleep(forTimeInterval: 2)
        shot("main-demo")
    }

    // MARK: - 找元件

    private func button(_ label: String) -> XCUIElement {
        app.buttons[label]
    }

    /// 主畫面那顆「剝今天」。頁點也叫剝今天，用 identifier 把頁點排掉。
    private var peelButton: XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", "剝今天", "dot-"))
            .firstMatch
    }

    /// 文字欄：先認 identifier，再認 placeholder（SwiftUI 不一定把 placeholder 當 label 露出來）。
    /// 單行是 textField，多行（axis: .vertical）在 XCUITest 裡可能是 textView，兩種都找。
    private func field(id: String, placeholder: String) -> XCUIElement {
        let p = NSPredicate(format: "(elementType == %ld OR elementType == %ld) AND (identifier == %@ OR label == %@ OR placeholderValue == %@)",
                            Int(XCUIElement.ElementType.textField.rawValue),
                            Int(XCUIElement.ElementType.textView.rawValue),
                            id, placeholder, placeholder)
        return app.descendants(matching: .any).matching(p).firstMatch
    }

    private func dot(_ page: Page) -> XCUIElement {
        switch page {
        case .basket: return app.buttons["dot-basket"]
        case .main: return app.buttons["dot-main"]
        case .settings: return app.buttons["dot-settings"]
        }
    }

    /// 每頁一個「看到它就代表在這頁」的元件
    private func anchor(_ page: Page) -> XCUIElement {
        switch page {
        case .basket: return app.staticTexts["籃子"]
        case .main: return field(id: "capture-field", placeholder: "現在在做什麼？說一句就好")
        case .settings: return app.staticTexts["設定"]
        }
    }

    // MARK: - 動作

    /// 用頁點切頁，切完用 anchor 的位置確認真的到了。
    /// 第一次沒到就先切去別頁再切回來：scrollPosition 的值沒變時 SwiftUI 不會捲。
    private func goTo(_ page: Page) {
        let other: Page = page == .basket ? .main : .basket
        for attempt in 0..<3 {
            if attempt > 0 {
                dot(other).tap()
                settle()
            }
            dot(page).tap()
            settle()
            if onScreen(anchor(page)) { return }
        }
        XCTFail("切不到 \(page) 頁")
    }

    /// 三頁是橫向排的，用左右位置判斷元件是不是在目前這一頁
    private func onScreen(_ el: XCUIElement) -> Bool {
        guard el.exists else { return false }
        let f = el.frame
        let s = app.frame
        return f.width > 0 && f.minX >= s.minX - 1 && f.maxX <= s.maxX + 1
    }

    /// 元件在捲動範圍外時，往上或往下捲到看得見為止
    private func reveal(_ el: XCUIElement) {
        let s = app.frame
        for _ in 0..<12 {
            guard el.exists else {
                Thread.sleep(forTimeInterval: 0.3)
                continue
            }
            let f = el.frame
            // 上面留 100pt：頁點那條膠囊在那裡，別讓點擊落在它上面
            let inside = f.height > 0 && f.minY >= s.minY + 100 && f.maxY <= s.maxY - 24
            if inside || el.isHittable { return }
            let below = f.midY > s.midY
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.8 : 0.3))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.4 : 0.7))
            from.press(forDuration: 0.1, thenDragTo: to)
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    /// 點欄位、等鍵盤、打字，打完確認欄位真的有字；中文沒進去就清掉改打英文
    private func typeInto(_ f: XCUIElement, _ text: String, fallback: String) {
        XCTAssertTrue(f.waitForExistence(timeout: 5), "要打字的欄位不存在")
        reveal(f)
        f.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        swallowing = true
        f.typeText(text)
        swallowing = false
        if !has(f, text) {
            note("中文「\(text)」沒打進去，改打英文：\(fallback)")
            clear(f)
            f.typeText(fallback)
        }
        XCTAssertTrue(has(f, text) || has(f, fallback), "字沒進到欄位，現在的值：\(String(describing: f.value))")
    }

    private func has(_ f: XCUIElement, _ text: String) -> Bool {
        (f.value as? String)?.contains(text) == true
    }

    private func clear(_ f: XCUIElement) {
        guard let v = f.value as? String, !v.isEmpty else { return }
        f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
    }

    /// 等切頁、關 sheet 這類動畫跑完
    private func settle() {
        Thread.sleep(forTimeInterval: 0.7)
    }

    // MARK: - 截圖與備註

    private func shot(_ name: String) {
        shotIndex += 1
        let base = String(format: "%02d-%@", shotIndex, name)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = base
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = shotDir else { return }
        do {
            try screenshot.pngRepresentation.write(to: dir.appendingPathComponent(base + ".png"))
        } catch {
            note("寫不進 \(dir.path)：\(error)")
        }
    }

    private func note(_ text: String) {
        NSLog("[SuanshuUITests] %@", text)
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = shotDir else { return }
        let url = dir.appendingPathComponent("notes.txt")
        let line = String(format: "%02d  %@\n", shotIndex, text)
        if let h = FileHandle(forWritingAtPath: url.path) {
            _ = h.seekToEndOfFile()
            h.write(Data(line.utf8))
            h.closeFile()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
