---
paths:
  - "macos/**"
  - "build/**"
  - "ops/launchd/**"
  - "lib/core/services/notification_service.dart"
  - "lib/presentation/providers/notification_provider.dart"
---

# macOS 打包與通知授權

**更名的隱藏代價（2026-08-08 實機踩到）**：`PRODUCT_NAME` 改了會產生**新的 .app bundle 名**，而舊的 `afterclose.app` 若仍留在 `build/`，會**與新 bundle 共用同一個 bundle ID**（`com.neo.afterclose`）。
LaunchServices 會把該 ID 解析到舊的那個 → 新 app 要求通知授權時系統當場回絕（`requestAuthorization` 4ms 回 false、無對話框、無系統日誌）。

清法：`lsregister -u <舊.app>`、刪掉舊 bundle、`lsregister -f <新.app>`。

`flutter run` 由 dartvm 直接啟動、不走 LaunchServices——**通知相關問題要用 `open <app>` 啟動才有代表性**。

launchd 的 CLI 是 AOT 產物；重編用 `ops/launchd/install.sh --cli-only`，不必 bootout／bootstrap——plist 的 ProgramArguments 指向固定路徑，launchd 每次喚醒都重新 exec 那個檔案；盤中對 intraday job 做 bootout／bootstrap 反而可能打斷正在執行的那一輪。
