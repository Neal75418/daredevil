# Rule Score Calibration

> 這份文件說明 `tool/recalibrate.dart` 如何把歷史 `rule_accuracy` 統計轉成 calibrated rule scores JSON 檔，以及人工 review 工作流程。
>
> **狀態**：pipeline + Stage 5 runtime loader 都已 ship — scoring 會透過 `calibrated_scores/` registry 消費 calibrated JSON，無資料時 fallback 到 `rule_scores.dart` 手調基礎分。目前 production JSON 多為 fallback（實質跑在手調分上，為設計非 bug）。

---

## 📋 目錄

- [何時該跑 calibration](#何時該跑-calibration)
- [如何執行](#如何執行)
- [Review workflow](#review-workflow)
- [公式：linear_map_v1](#公式linear_map_v1)
- [Cut 規則](#cut-規則)
- [JSON 輸出格式](#json-輸出格式)
- [Troubleshooting](#troubleshooting)

---

## 何時該跑 calibration

**用事件觸發，不要用月曆。**

| 事件 | 該跑什麼 | 成本 |
|:---|:---|:---|
| 新增或修改規則 | 完整管線 `./scripts/calibrate.sh` | 3–5 小時 |
| 回補了新的歷史資料 | 完整管線 | 3–5 小時 |
| 改統計方法或 gate 閾值 | 只跑 `dart run tool/recalibrate.dart` | 數秒 |
| 以上都沒發生 | 不用跑 | — |

**為什麼不按月排程**（2026-08-22 量測）：DB 已有 1468 個交易日（2017-05 起）。
多等一個月只增加 21 個交易日 ＝ +1.4% 樣本，t-stat 隨 √n 成長只改善 0.71%。
一條卡在 t=1.5 的規則要靠時間推過 1.96 門檻，需要 1.7× 資料 ＝ 再等 4.1 年。

同次量測：73 個被 cut 的規則裡 **61 個是 `t_stat_below_threshold`**、8 個是
hit rate 不足，**只有 4 個是 `dates_too_few`**。卡住的不是樣本量，是那些規則
本身沒有可測得的 edge——等再久也不會變。

唯一真正會改變結論的是規則集或資料本身變動。2026-07-13 那次把價格資料從
2 年補到 6 年、replay 樣本 +21%，`INSTITUTIONAL_BUY` 因此首次過關（t=2.2、
n=11,742）；那是資料變了，不是時間到了。

### 工具會自己告訴你

`recalibrate.dart` 啟動時比對 `RuleRegistry` 與 `rule_accuracy`，印出涵蓋落差：

```
📅 replay 落檔於 2026-07-13T02:13:42.224620Z（40 天前）
🔎 規則涵蓋：70 條註冊規則
   ⚠️  31 條無 replay 樣本，本次只會拿到手調分：
      BREAK_MA20, BREAK_MA60, COILING_BELOW_MA20, COILING_BELOW_MA60,
      CONCENTRATION_HIGH, DAY_TRADING_EXTREME …（另 25 條）
      → 要給它們統計基礎，需重跑完整管線：./scripts/calibrate.sh
   ℹ️  3 條樣本中的規則已不在註冊表（candidate JSON 會留下查不到的死列）
```

**已知缺口**：這個比對只看 rule **id**。若規則 id 沒變、但內部閾值改了
（例如 `rule_params` 調整），觸發樣本其實已經失效，而差集看不出來——需要
靠自己記得。刻意不做參數雜湊：任何無關的參數改動都會誤觸發，訊號會被稀釋
成噪音。

**不要**：
- 剛上線第一天就跑（樣本數 < 30 → 全部 cut）
- 自動覆寫 production（永遠要人工 review gate）

---

## 如何執行

### 完整管線（backfill → replay → recalibrate）

```bash
./scripts/calibrate.sh          # 三階段一次跑完，產出 candidate JSON
./scripts/calibrate-retry.sh    # 同上，但自動處理 TWSE 限流（每輪間隔 15 分鐘）
```

規則、參數或資料來源有變動時走這條——只重算評分無法反映新的觸發樣本。
一次完整回補約 3–5 小時，`calibrate-retry.sh` 會自行重試直到跑完。

### 只重算評分

`recalibrate.dart` 是管線的**第三階段**，單獨跑等於沿用既有的 replay 樣本，
只重新計算分數。統計方法或閾值調整時這樣做是對的；規則本身變了則不夠。

工具啟動時會印出 replay 落檔時間，超過 30 天示警：

```
📅 replay 落檔於 2026-07-13T02:13:42.224620Z（40 天前）
⚠️  超過 30 天——本次只重算評分，不會重跑 backfill／replay。
```

從 repo root 目錄：

```bash
# 兩個 horizon 都跑（預設）
dart run tool/recalibrate.dart

# 只跑短線（5D）或長線（60D）
dart run tool/recalibrate.dart --horizon short
dart run tool/recalibrate.dart --horizon long

# Dry run — 印出 candidate JSON 但不寫檔
dart run tool/recalibrate.dart --dry-run

# 自訂 DB 位置（若 auto-detect 失敗）
dart run tool/recalibrate.dart --db /path/to/afterclose.sqlite
```

### 輸出

工具會寫入 `assets/` 底下的 candidate 檔案：

```
assets/rule_scores_calibrated_short_candidate.json
assets/rule_scores_calibrated_long_candidate.json
```

**關鍵**：檔名有 `_candidate` 後綴。這不是 production 版本。需要人工 review 後手動 rename 才生效。

---

## Review workflow

### 1. 跑 recalibrate.dart

```bash
dart run tool/recalibrate.dart
```

確認 console 輸出：
- `✅ Wrote ...` 表示 candidate 產出成功
- `⚠️  rule_accuracy 沒有 XX 的統計資料 — skip` 表示資料不足，要等累積更多

### 2. 看 diff

candidate 檔在 `.gitignore` 內（`assets/*_candidate.json`），**`git diff` 對它們
永遠是空的**——不是「沒變動」，是 git 根本不追蹤。

#### 先看有效分數變動（`recalibrate.dart` 會自己印）

跑完 `recalibrate.dart` 的輸出尾端就是這段，不需要額外指令：

```
═══ Promote 影響(App 有效分數)═══
  short（負證據歸零生效）:9 條有效分數變動
    COILING_BELOW_MA60             8 → 0
    MA_ALIGNMENT_BULLISH           0 → 22
    PRICE_SPIKE                   15 → 0
    RECLAIM_MA20                   8 → 0
    REVERSAL_W2S                  35 → 0
    ...
  long（負證據歸零不套用）:3 條有效分數變動
    EPS_CONSECUTIVE_GROWTH        22 → 35
    INSTITUTIONAL_BUY             18 → 10
    WEEK_52_HIGH                  28 → 27
```

**為什麼不能自己拿 jq 比 `active`／`score`**（2026-08-22 實際踩到）：
`active:false, score:0` 與「規則根本不在 JSON 裡」在 App 眼中是兩回事——
前者可能被負證據歸零（`lookup` 回 0），後者 fallback 到 hardcoded 分。
本檔曾放過一段這樣比的 jq，短線報「無變動」而實際有 9 條改變。
同日 walk-forward gate 也栽在同一個坑（`parseCalibratedScores` 把 cut／
缺席都當 0，導致 OLD arm 被低估、長線平均勝幅虛報成 +5.60，修正後是
−0.048）。

判讀時走 `CalibratedScoresTable.lookup` 是唯一正解，`recalibrate.dart` 的
`diffEffectiveScores()` 就是這樣做的。

#### 要細節再看全文 diff

```bash
diff <(jq -S . assets/rule_scores_calibrated_long.json) \
     <(jq -S . assets/rule_scores_calibrated_long_candidate.json)
```

`jq -S` 先排序 key，否則欄位順序變動會混進 diff。這份可能有數百行——某個
horizon 隔了幾輪沒 promote 時，樣本數與 t_stat 全表都會動，所以先看上面的
摘要、需要追問再展開。

剛 promote 完兩檔會完全相同（promote＝把 candidate 複製成 production），
此時空輸出是正確的。

**檢查重點**：
- 分數變動幅度是否合理？（突然大增減要查）
- 新增 cut 的規則是否預期？（看 `cut_reason`）
- Active 的規則 score 分布是否合理？（不應該全部擠在 10 或 35）
- `samples` 欄位是否反映最近的資料量？

### 3. 判斷

**要 approve 當前 candidate**：
```bash
mv assets/rule_scores_calibrated_short_candidate.json \
   assets/rule_scores_calibrated_short.json

mv assets/rule_scores_calibrated_long_candidate.json \
   assets/rule_scores_calibrated_long.json
```

**要退回**：
```bash
rm assets/rule_scores_calibrated_*_candidate.json
```
然後檢查 DB 資料是否有異常，必要時等下個月再試。

### 4. Commit + push

```bash
git add assets/rule_scores_calibrated_short.json assets/rule_scores_calibrated_long.json
git commit -m "chore(calibration): monthly recalibration YYYY-MM"
git push origin main
```

Commit message 應該在 body 記錄 review 時的判斷與 anomaly observation。

---

## 決策層雙路（2026-07-10 起）

`recalibrate.dart` 依 replay 落檔的 `calibration_run_meta.return_mode` 自動分流：

| 路徑                  | 觸發條件                                   | t-stat                                          | hit-rate cut                                                    | raw weight                   |
|-----------------------|--------------------------------------------|-------------------------------------------------|-----------------------------------------------------------------|------------------------------|
| **clustered（超額）** | `return_mode = excess` 且 meta 有 baseline | date-clustered one-sample t（對「日均值序列」） | `hit ≥ universe baseline + 0.05`（baseline 為同次 replay 實測） | `hit × mean(日均值) × √日數` |
| **legacy（絕對）**    | meta 缺失或 `absolute`                     | pooled proportion z-test                        | `hit ≥ 0.55` 絕對                                               | `hit × avg × √n`             |

**為什麼 clustered**：pooled 統計把同日橫斷面相關 + 持有窗重疊的 firing 當
獨立樣本，名目 n（十萬級）遠大於有效樣本、|t| 動輒 >200 無意義。先對每個
觸發日取橫斷面平均，再對「日均值序列」做 t —— 有效樣本回到「日」的量級。
新增 cut：`dates_too_few`（觸發日 < 30）。

**資料來源**：replay 另落兩張表（僅存在 calibration DB、非 app schema）——
`rule_daily_stats`（rule × period × 日 → n、日均值）與 `calibration_run_meta`
（return_mode / excess threshold / universe baseline hit）。每次 replay 全刪重寫。

**walk-forward 同路**：`walkforward_validate` 的 NEW arm 走同一條
`calibrateAllClustered`（先前 walkforward 用 0.5、CLI 用絕對 baseline 的雙路
drift 已消除）。

**app loader**：excess JSON 的 `success_threshold_pct` 記實際超額門檻
（`CalibrationThresholds.excessSuccessThreshold` = 0.0），drift guard 依
`backtest.return_mode` 選 canonical 比對，不會誤殺。

以下 linear_map_v1 說明為 **legacy 路徑**原文；clustered 路徑僅替換 Step 1
的統計量與 Step 2 的輸入（映射與 cut 順序骨架相同）。

---

## 公式：linear_map_v1

給定單一規則的統計 `(hit_rate, avg_return, trigger_count)`：

### Step 1 — Proportion z-test

判斷 `hit_rate` 是否統計顯著地超過 0.5（純機率）：

```
z = (hit_rate - 0.5) / sqrt(hit_rate × (1 - hit_rate) / n)
```

Degenerate cases (z = 0)：
- `n = 0`
- `hit_rate ∈ {0, 1}`（variance = 0，undefined）

這些 case 會落入 `sample_too_small` cut，不影響後續計算。

### Step 2 — Raw weight

```
raw_weight = hit_rate × avg_return × √n
```

**為什麼用 `√n`**：
- 樣本數越多權重越高（越可信）
- 但用 `√n` 而非 `n` 避免大樣本規則壓垮小樣本（sub-linear scaling，跟統計學中標準誤差呈反比成正比）
- 雙重保險：跟 `hit_rate × avg_return` 相乘，防止「低勝率但一次大賺」造成假高分

### Step 3 — Cut thresholds（見下一節）

### Step 4 — Min-max normalization

```
score = 10 + (raw_weight - minRaw) / (maxRaw - minRaw) × 25
```

其中 `minRaw` / `maxRaw` 是**倖存者**的 raw weight 範圍（cut 掉的規則**不計入**）。這防止被 cut 的 outlier 規則扭曲 active 規則的分數分布。

**邊界處理**：
- 只有 1 條倖存者 → 分數設為中點 (22)
- 所有倖存者 raw 相同 → 同上
- `raw < minRaw` 或 `raw > maxRaw`（浮點誤差）→ clamp 到 [10, 35]

---

## Cut 規則

規則會被判定為 `active: false` 並得分 0 的三種情況，check order 重要：

| # | 門檻     | `cut_reason`               | 觸發條件            | 為什麼先檢查                   |
|:-:|:---------|:---------------------------|:--------------------|:-------------------------------|
| 1 | samples  | `sample_too_small`         | `triggerCount < 30` | 樣本太少，所有統計都不可信     |
| 2 | z-stat   | `t_stat_below_threshold`   | `z_stat < 1.5`      | 顯著性測試失敗，效果可能是雜訊 |
| 3 | hit_rate | `hit_rate_below_threshold` | `hit_rate < 0.55`   | 顯著但勝率太低，實戰價值不足   |

**Check order 的重要性**：檢查順序從「最嚴格 / 最通用」到「最細節」。樣本不足時無法做後續測試；z-stat 失敗時 hit_rate 數字本身不可靠。

### 邊界案例示意

| Scenario           | hit_rate | samples | z-stat | Cut reason               |
|:-------------------|:--------:|:-------:|:------:|:-------------------------|
| 新規則，資料不足   |   0.65   |   25    |   —    | sample_too_small         |
| 小樣本瞎貓撞死耗子 |   0.80   |   20    |   —    | sample_too_small         |
| 中性訊號           |   0.51   |   50    |  0.14  | t_stat_below_threshold   |
| 顯著但勝率邊緣     |   0.54   |   500   |  1.79  | hit_rate_below_threshold |
| 顯著且強勢         |   0.65   |   100   |  3.15  | **active** ✅            |

---

## JSON 輸出格式

```json
{
  "schema_version": 1,
  "generated_at": "2026-05-01T02:30:00.000Z",
  "horizon": "5d",
  "backtest": {
    "window_days": 504,
    "train_ratio": 0.7,
    "success_threshold_pct": 1.5,
    "formula": "linear_map_v1"
  },
  "rules": {
    "reversalW2S": {
      "score": 28,
      "hit_rate": 0.6523,
      "avg_return": 3.1247,
      "samples": 412,
      "t_stat": 6.2147,
      "active": true
    },
    "patternDoji": {
      "score": 0,
      "hit_rate": 0.5234,
      "avg_return": 1.1203,
      "samples": 89,
      "t_stat": 0.4425,
      "active": false,
      "cut_reason": "t_stat_below_threshold"
    }
  }
}
```

### 欄位說明

| 欄位                             | 型別                | 說明                                                                                                                                                                                                                           |
|:---------------------------------|:--------------------|:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `schema_version`                 | int                 | 目前固定為 1。升級公式（例如切到 IC-based）時 bump                                                                                                                                                                             |
| `generated_at`                   | ISO 8601 UTC string | 跑 `recalibrate.dart` 的時間戳                                                                                                                                                                                                 |
| `horizon`                        | `"5d"` \| `"60d"`   | 此檔對應的時間尺度                                                                                                                                                                                                             |
| `backtest.window_days`           | int                 | 回測天數（目前 504 = 2 trading years）                                                                                                                                                                                         |
| `backtest.train_ratio`           | float               | Train/test split ratio（目前 0.7，但 Stage 2 LEAN 未實作 out-of-sample validation）                                                                                                                                            |
| `backtest.success_threshold_pct` | float               | 對應 horizon 的 success 判定門檻。canonical 值由 [`CalibrationThresholds.successThresholds`](../lib/core/constants/calibration_thresholds.dart) 提供（5D=1.5%、60D=8.0%；drift guard 會把 JSON 對比 canonical 拒載失準版本）。 |
| `backtest.formula`               | string              | 公式版本識別子，目前 `linear_map_v1`                                                                                                                                                                                           |
| `rules.*.score`                  | int                 | 校準後分數（cut 為 0，active 為 [10, 35]）                                                                                                                                                                                     |
| `rules.*.hit_rate`               | float (4 dp)        | 命中率                                                                                                                                                                                                                         |
| `rules.*.avg_return`             | float (4 dp)        | 平均報酬率（%）                                                                                                                                                                                                                |
| `rules.*.samples`                | int                 | 觸發次數                                                                                                                                                                                                                       |
| `rules.*.t_stat`                 | float (4 dp)        | Proportion z-test 值                                                                                                                                                                                                           |
| `rules.*.active`                 | bool                | 是否通過 cut                                                                                                                                                                                                                   |
| `rules.*.cut_reason`             | string (optional)   | 只有 cut 規則有此欄位                                                                                                                                                                                                          |

---

## Troubleshooting

### ❌ `DB file 找不到`

Auto-detect 只知道 macOS Flutter container 的預設位置（`~/Library/Containers/com.neo.afterclose/Data/Documents/`）。若你的 DB 在別處：

```bash
find ~ -name "afterclose*.sqlite" 2>/dev/null
dart run tool/recalibrate.dart --db /path/found/above
```

### ⚠️ `rule_accuracy 沒有 XX 的統計資料`

`rule_accuracy` 表是空的或對應 period 沒資料。可能原因：

- App 從未跑過 post-update hook（`validatePastRecommendationsMultiPeriod` 或 `backfillAllHistoricalRecommendations`）
- `daily_reason` 本身沒資料（scoring pipeline 沒 persist reasons）
- 60D horizon 需要資料回溯至少 60 個交易日 + backtest window，pre-launch 根本不可能有

**解法**：跑 app，讓 daily scoring pipeline 生成資料，等幾週再重跑。

### 所有規則都被 cut

一次全砍通常代表：
1. **樣本數太少**（所有 rule `sample_too_small`）— 等資料累積
2. **資料格式問題**（`hit_rate` 全 0）— 看 `_computeValidation` 的 success threshold 是否合理
3. **backfill 沒跑完**（rule_accuracy 只有 partial 資料）— 重跑 `backfillAllHistoricalRecommendations`

### 分數分布異常（全擠 10 或 35）

表示**倖存者 raw weight 範圍**太窄：

- 全擠 10：`maxRaw - minRaw` 太小，所有 active 規則幾乎一樣強 → 正常，代表 rule set 同質性高
- 全擠 35：可能單一規則 raw 特別高，其他擠在 minRaw → 可能是資料異常，檢查該規則的樣本

### Candidate 比 production 差很多

**不要 approve**。查：
1. 是否剛經歷異常市場（如極端黑天鵝）？校準結果可能被污染
2. 是否 daily_reason 有 bug 多寫了假 trigger？
3. 是否 backfill 邏輯改過（例如 Stage 5 引入 dual-horizon）沒重跑？

**回退**：刪 `*_candidate.json`，保留目前 production，下個月再試。

---

## 校準紀錄

### 2026-07-09 — Mode C 首份 baseline（決定：不 rename）

**觸發**：4 條 Mode C 回檔規則（6/19 上線）的 CALIBRATION_PENDING。
**範圍**：2 年全市場回放（2024-07 ~ 2026-07，backfill 補完 2024 下半年 gap
後 88 萬+ firings、44 條規則）。

| 規則              | 5D 勝率 | 5D 均報酬 | 60D 均報酬 | 60D z | 樣本   |
|:------------------|:--------|:----------|:-----------|:------|:-------|
| PULLBACK_TO_MA20  | 43.7%   | -0.12%    | +0.53%     | -4.8  | 28,038 |
| PULLBACK_TO_MA10  | 42.7%   | -0.22%    | +1.08%     | 2.6   | 42,032 |
| HAMMER_AT_SUPPORT | 40.8%   | -0.39%    | +0.41%     | -1.9  | 5,467  |
| KD_HIGH_PULLBACK  | 43.5%   | -0.13%    | +1.19%     | 2.4   | 12,812 |

**解讀**：四條皆 cut（hit < 55%），但屬全體常態（44 條僅 1 active，與現行
production 1/40 一致）。5D 小幅負報酬符合「剛回檔的幾天常續回」直覺；60D
方向正、MA10/KD 顯著，符合 buy-the-dip 觀察 tab 的設計意圖。不退役、不改分。

**不 rename 的理由**：candidate 與 production 的唯一 active 差異是
short 的 TECH_BREAKDOWN（n=6,992）被 EPS_CONSECUTIVE_GROWTH（n=45、
long hit 100%——小樣本異象）取代，是變差不是變好；其餘 cut 規則
runtime 皆 fallback 手調分、rename 與否行為不變。

**附帶修復**：backfill TWSE/TPEx per-day batch 原無 skip-existing，
rate-limit retry 每輪從頭重抓推不動（commit 8a4debd 修復）。

---

## 設計背景

完整的 Stage 2 LEAN 設計文件在 [`docs/plans/2026-04-11-scoring-stage2-design.md`](plans/2026-04-11-scoring-stage2-design.md)。

關鍵決策（來自 2026-04-11 brainstorming session）：
- 公式選 **linear_map_v1**（interpretable），非 IC-based 或 logistic regression
- **雙 horizon** 策略：短 5D + 長 60D，每條規則在兩個 horizon 各有獨立分數
- Cut threshold **嚴格版**：t_stat<1.5 / hit_rate<55% / n<30
- **月度人工 review gate**：絕不自動覆寫 production
  （*節奏部分已於 2026-08-22 修訂為事件觸發，見上方「何時該跑 calibration」；「絕不自動覆寫」不變*）
- Stage 2 只建 pipeline，**不消費** JSON（消費工作在 Stage 5，需真實資料驗證架構）
