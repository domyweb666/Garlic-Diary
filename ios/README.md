# 蒜數 iOS 版

網頁版（根目錄的 `index.html`）的原生重寫：SwiftUI、iOS 17 起、只做 iPhone 直向。
資料格式跟網頁版的備份 JSON 一樣，兩邊可以互相匯入。

## 跟網頁版不一樣的地方

- 資料存在 app 沙盒，跟著 iCloud 備份走。刪捷徑就掉資料的問題沒了。
- API 金鑰進 Keychain，不在備份檔裡。
- 每天一次提醒（設定頁開）。對帳日的文案不同，剝過的那天不會響。
- 觸覺回饋為主，聲音可以關。
- 用說的走 iOS 的語音辨識（zh-TW）。不行的時候，鍵盤上的麥克風一樣能用。
- 籃子會跟著手機傾斜滾，靜下來就停，不耗電。
- 字級跟著系統的動態字體。

## 怎麼跑

有 Mac 和 Xcode 16 以上：

1. 打開 `ios/Suanshu.xcodeproj`。
2. Target 的 Signing & Capabilities 選你的 Team。
3. 接上 iPhone，Run。

沒有 Mac：

- 推上 GitHub 之後，`.github/workflows/ios-build.yml` 會在 macOS runner 上做兩件事：先編模擬器版確認程式編得過，再編一個沒簽名的 iPhone 版，打包成 `Suanshu-unsigned.ipa` 放在那次 run 的 artifact 裡。
- 把 IPA 下載下來，用 Sideloadly 加你的 Apple ID 簽進 iPhone。免費帳號簽的七天到期，重簽一次就好。
- 要上 TestFlight 或 App Store 還是得有一台 Mac，借的、租的都行。

## 模擬器自動走一遍（截圖）

沒有 Mac 也能看畫面。同一個 workflow 裡還有一個 `ui-test` job：在 macOS runner 上開 iPhone 模擬器，用 XCUITest（`SuanshuUITests/`）把主流程走一遍，每個畫面截一張圖。

它走的流程：首次打開三步 → 記一句 → 剝三瓣（上午順、下午普通、晚上卡）→ 籃子頁 → 週對帳走到完成 → 關掉重開（那句、剝完的三瓣、對帳都要還在）→ 設定頁清除全部資料 → 載示範資料 → 回剝今天頁。

看截圖：到那次 run 的 Artifacts，下載 `suanshu-ui-screenshots`，解開是一疊 PNG，檔名開頭的數字就是步驟順序；`notes.txt` 是測試中途的備註（例如中文打不進去、改打英文）。另一個 artifact `suanshu-ui-xcresult` 是完整的 `.xcresult` 和 log，有 Xcode 的人可以雙擊打開看每一步。

能抓到的是功能有沒有壞：按了沒反應、畫面不對、資料沒留住、閃退。手感、震動、聲音、傾斜它測不到，那些還是要真機。

有 Mac 的話，在 Xcode 選 Suanshu scheme 按 Cmd+U 跑的就是同一支測試。要 PNG 檔的話：

```bash
TEST_RUNNER_SUANSHU_SCREENSHOT_DIR="$PWD/screenshots" xcodebuild test -project Suanshu.xcodeproj -scheme Suanshu -destination "platform=iOS Simulator,name=iPhone 16"
```

## 目前的狀態

0.4，第一次移植。2026-11-07 在 GitHub Actions（Xcode 26.6）編過模擬器版和 iPhone 版，Swift 零警告；還沒在真機上跑過。
下一步照手感原型的規矩上真機測：觸覺強度、落籃子的聲音、傾斜的靈敏度。

## 檔案

- `Suanshu/Model/`：資料結構（跟網頁版 JSON 對齊）、日期規則（凌晨四點前算前一天）、AppStore（所有規則）、畫面層狀態
- `Suanshu/Services/`：Keychain、AI 呼叫、回饋（觸覺＋聲音）、語音、傾斜、提醒
- `Suanshu/Views/`：三頁、剝的流程、週對帳、設定、首次打開、籃子物理、共用元件
- `SuanshuUITests/`：XCUITest，給 Actions 在模擬器上走主流程、截圖用
