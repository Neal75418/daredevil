---
paths:
  - "lib/core/**"
  - "lib/data/**"
  - "lib/domain/**"
  - "lib/presentation/**"
  - "lib/app/**"
  - "lib/main.dart"
---

# 架構分層

> ⚠️ **這裡畫的是實際的 import 方向,不是理想的 clean architecture。**
> 兩者差很多,而差異本身才是這份文件的價值——照理想圖推論會推錯。

```mermaid
flowchart LR
    Core["🧱 core/<br/>constants · exceptions · utils<br/>extensions · l10n · services · theme"]
    Data["💾 data/<br/>database · remote · repositories<br/>models · loaders · network · mappers"]
    Domain["⚙️ domain/<br/>models · repositories(介面)<br/>services · services/rules (70 rules) · services/update"]
    Pres["📱 presentation/<br/>providers · screens · widgets<br/>mappers"]

    Core ==>|142 檔| Pres
    Core ==> Data
    Core ==> Domain
    Data ==>|62 檔| Domain
    Domain -.->|10 檔<br/>雙向| Data
    Data ==>|68 檔| Pres
    Domain ==>|42 檔| Pres

    classDef core fill:#8B5CF6,stroke:#4C1D95,stroke-width:2px,color:#FFFFFF
    classDef data fill:#F59E0B,stroke:#78350F,stroke-width:2px,color:#FFFFFF
    classDef dom fill:#10B981,stroke:#065F46,stroke-width:2px,color:#FFFFFF
    classDef pres fill:#4F46E5,stroke:#312E81,stroke-width:2px,color:#FFFFFF

    class Core core
    class Data data
    class Domain dom
    class Pres pres
```

箭頭方向＝「被誰 import」，數字＝實測的檔案數（2026-08-23）。三件會讓人推錯的事：

1. **`presentation` 直接吃 `data/` 比吃 `domain/` 還多**（68 vs 42）。Provider 常繞過
   domain 直接打 DAO，甚至直接用 remote client。「UI 只跟 domain 講話」是錯的。
2. **`data` 與 `domain` 是雙向的**（domain→data 62 檔、data→domain 10 檔），不是單向。
3. **`domain/repositories/` 的「介面」沒有隔開 Drift**——7 個檔裡 6 個直接 import
   `data/database/app_database.dart` 拿 row type。那層抽象邊界實際上不存在。

**唯一真正單向的是 `core/`**：它不 import 上面任何一層（守門：
`test/core/core_layer_purity_test.dart`，含 >30 檔的 sanity floor 防假綠）。跨層共用的
純值物件（如 `chip_strength.dart`）下沉 `core/constants/`，計算邏輯歸 `domain/services/`。

## 三條讀取路徑

UI 的資料**不是只有一條路**。畫成單線會讓人以為改 Repository 就能攔截全部。

```mermaid
flowchart LR
    API["外部 API"] -->|syncer| Repo["Repository"]
    Repo --> DB[("Drift SQLite")]
    DB --> Score["Scoring<br/>Isolate.run()"]
    Score --> DB

    DB -->|① Provider| UI["Widget"]
    DB -->|② DAO 直取| UI
    API -->|③ client 直取| UI
    DB -.->|headless<br/>無 Riverpod| CLI["launchd CLI<br/>WorkManager"]

    classDef ext fill:#F59E0B,stroke:#78350F,stroke-width:2px,color:#FFFFFF
    classDef store fill:#8B5CF6,stroke:#4C1D95,stroke-width:2px,color:#FFFFFF
    classDef dom fill:#10B981,stroke:#065F46,stroke-width:2px,color:#FFFFFF
    classDef pres fill:#4F46E5,stroke:#312E81,stroke-width:2px,color:#FFFFFF

    class API,CLI ext
    class Repo,Score dom
    class DB store
    class UI pres
```

| 路徑 | 說明 |
|:---|:---|
| ① Provider | 標準路徑,但**不是多數** |
| ② DAO 直取 | Provider 繞過 domain 直接讀 DAO(法人排行、營收總覽、季報總覽等) |
| ③ client 直取 | 個股詳情、大盤總覽直接打 remote client,不經 DB |
| headless | `lib/app/headless_update_runner.dart` **完全不建 Riverpod container**——launchd CLI 與 WorkManager 背景 isolate 的唯一入口 |

**Scoring 在獨立 isolate**(`Isolate.run()`):static 不跨界,曾造成 AOT CLI 的規則/評分
日誌全部靜默,見 `scoring_isolate.dart` 的註解。
