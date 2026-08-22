---
paths:
  - "lib/core/**"
  - "lib/data/**"
  - "lib/domain/**"
  - "lib/presentation/**"
---

# 架構分層圖

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TB
    subgraph Core["core/"]
        Constants["constants/ — RuleParams + 其他常數"]
        Exceptions["exceptions/ — AppException sealed hierarchy"]
        Utils["utils/ — Logger, Calendar, RequestDeduplicator, LruCache"]
    end

    subgraph Data["data/"]
        Database["database/ — Drift SQLite (tables + DAOs)"]
        Remote["remote/ — TWSE, TPEX, FinMind, TDCC, RSS (5 sources)"]
        Repos["repositories/ — 實作"]
    end

    subgraph Domain["domain/"]
        Models["models/"]
        RepoIF["repositories/ — 介面"]
        Services["services/ — Analysis, Scoring, Screening, etc."]
        Update["services/update/ — syncers + helpers + coordinator"]
        Rules["services/rules/ — 70 rules"]
    end

    subgraph Presentation["presentation/"]
        Providers["providers/"]
        Screens["screens/"]
    end

    Core --> Data
    Core --> Domain
    Data --> Domain
    Domain --> Presentation
```

**core 純度不變量**：`lib/core/` 不得 import domain／data／presentation（守門：`test/core/core_layer_purity_test.dart`）。跨層共用的純值物件（如 `chip_strength.dart`）下沉 `core/constants/`，計算邏輯歸 `domain/services/`。

## 資料流

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR
    API["External APIs"] -->|fetch| Repo["Repository"]
    Repo -->|write| DB[("Drift DB")]
    DB -->|read| Provider["Riverpod"]
    Provider -->|notify| UI["UI"]
```
