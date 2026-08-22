# 📦 Release Build Guide

Daredevil 發布建置指南

---

## 🔄 建置流程

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR
    Clean["Clean"] --> CodeGen["Code Gen"]
    CodeGen --> Build["Build"]
    Build --> Sign["Sign"]
    Sign --> Dist["Distribute"]

    style Clean fill:#4B5563,color:#fff,stroke:#374151
    style CodeGen fill:#2563EB,color:#fff,stroke:#1D4ED8
    style Build fill:#059669,color:#fff,stroke:#047857
    style Sign fill:#7C3AED,color:#fff,stroke:#6D28D9
    style Dist fill:#D97706,color:#fff,stroke:#B45309
```

---

## ⚡ 快速指令

```bash
# 清理 + 準備
flutter clean && flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Android
flutter build apk --release --obfuscate --split-debug-info=build/debug-info --dart-define=SENTRY_DSN=$SENTRY_DSN
flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info --dart-define=SENTRY_DSN=$SENTRY_DSN

# iOS
flutter build ipa --release --obfuscate --split-debug-info=build/debug-info --dart-define=SENTRY_DSN=$SENTRY_DSN
```

---

## ⚙️ 平台設定

### Android 簽署

**1. 產生金鑰（首次）**

```bash
cd android
keytool -genkey -v -keystore daredevil-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias daredevil
```

**2. 設定 key.properties**

```bash
cp key.properties.template key.properties
# 編輯填入：storePassword, keyPassword, keyAlias, storeFile
```

### iOS 簽署

1. 開啟 `ios/Runner.xcworkspace`
2. 選擇 Team，Bundle ID: `com.neo.afterclose`
3. 啟用 "Automatically manage signing"
4. Product → Archive → Distribute App

---

## 🏷 版本管理

```yaml
# pubspec.yaml
version: 1.0.0+1  # major.minor.patch+buildNumber
```

---

## ✅ 發布檢查清單

| 項目              | 指令 / 動作                             |
|:------------------|:----------------------------------------|
| 更新版本號        | 修改 `pubspec.yaml` 的 `version`        |
| 測試通過          | `flutter test`                          |
| 靜態分析          | `flutter analyze`                       |
| 實機測試          | Android + iOS 裝置驗證                  |
| 移除 debug 程式碼 | 確認無 `debugPrint` / `kDebugMode` 殘留 |
| 更新圖示          | `dart run flutter_launcher_icons`       |
| 更新啟動畫面      | `dart run flutter_native_splash:create` |

---

## ⚠️ 注意事項

| 項目       | 說明                                                                |
|:-----------|:--------------------------------------------------------------------|
| 金鑰安全   | 勿 commit `key.properties` 或 keystore 檔案                         |
| Crash 解析 | 保留 `build/debug-info` 供 crash 分析                               |
| Sentry DSN | 手動建置需設定 `export SENTRY_DSN=<dsn>`，CI 從 GitHub Secrets 注入 |
