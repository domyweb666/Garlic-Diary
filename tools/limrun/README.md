# Limrun 模擬器走一遍

沒有 Mac 的時候，用 Limrun 的雲端 iPhone 模擬器跑一遍 iOS 版的主流程，每一步截圖。
能抓到的是功能有沒有壞（按了沒反應、畫面不對、資料沒留住、閃退）；手感、震動、傾斜、真的麥克風抓不到，那些還是要真機。

## 前提

- 這台電腦的 `~/.lim/config.yaml` 有 `api-key`（或設環境變數 `LIM_API_KEY`）。
- Limrun 帳號有點數或訂閱。2026-11-07 試的時候沒有，開機被拒：`no remaining credits and no active subscription`，到 https://console.limrun.com 的 billing 補。
- Windows 上 `lim` CLI 每個指令會卡 15 秒，所以這裡直接用 `@limrun/api`。

## 跑法

1. 到 GitHub Actions 找最新一次綠的 run，下載 artifact `suanshu-build`，裡面有 `Suanshu-simulator.app.zip`（通用架構的模擬器版）。
   `gh run download <run id> -n suanshu-build -D ../../build-artifact`
2. 在這個資料夾 `npm install`。
3. `node test.mjs <Suanshu-simulator.app.zip 的路徑>`

跑完截圖在 `shots/`，每張檔名就是步驟。模擬器用完會自己刪，開著是扣點的（每分鐘約兩點）。

## 它走的流程

首次打開三步 → 記一句 → 剝三瓣（看完成語與籃子落下）→ 籃子頁 → 週對帳到完成 → 關掉重開看資料還在不在 → 設定頁清除、載示範資料 → 示範資料的對帳走到 AI 那步、按「請 AI 讀」看沒金鑰的錯誤 → 切深色模式再看主畫面和籃子。
