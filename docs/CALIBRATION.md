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
- [決策層雙路](#決策層雙路2026-07-10-起)
- [校準紀錄](#校準紀錄)
- [設計背景](#設計背景)
---

## 何時該跑 calibration

**用事件觸發，不要用月曆。**

| 事件 | 該跑什麼 | 成本 |
|:---|:---|:---|
| 新增或修改規則 | 完整管線 `./scripts/calibrate.sh` | ~45–75 分鐘 |
| 回補了新的歷史資料 | 完整管線 | 同上 |
| 要補基本面（EPS/ROE/PE/PBR） | `BACKFILL_SKIP_FUNDAMENTALS=0 ./scripts/calibrate-retry.sh` | **~13 小時** |
| 改統計方法或 gate 閾值 | 只跑 `dart run tool/recalibrate.dart` | 數秒 |
| 以上都沒發生 | 不用跑 | — |

**為什麼不按月排程**：DB 已累積多年資料，多等一個月只增加約 1.4% 樣本，
而 t-stat 隨 √n 成長——改善幅度遠小於門檻距離。實際被 cut 的規則絕大多數卡在
t-stat 與 hit rate，而非樣本量；等再久也不會變。

> 具體數字每跑一次 backfill 就過期，這裡刻意不寫。要看當下的 cut 原因分布，
> 讀 candidate JSON 的 `cut_reason` 欄位。


唯一真正會改變結論的是規則集或資料本身變動。2026-07-13 那次把價格資料從
2 年補到 6 年、replay 樣本 +21%，`INSTITUTIONAL_BUY` 因此首次過關（t=2.2、
n=11,742）；那是資料變了，不是時間到了。

### 工具會自己告訴你

`recalibrate.dart` 啟動時比對 `ReasonType`（**不是** `RuleRegistry`——兩者是
不同命名空間，見 `coverageReferenceIds()`）與 `rule_accuracy`，把未校準的規則
分成三群並各給對應建議：

| 它說 | 意思 | 該做 |
|:---|:---|:---|
| N 條無 replay 樣本，**但所需資料都在** | 規則比上次 replay 新 | 重跑 Stage 2（約 12 分） |
| N 條**需要 FinMind 基本面資料** | 老問題，要額度 | 通常不動；要補才 `BACKFILL_SKIP_FUNDAMENTALS=0` |
| N 條**這條管線抓不到資料** | 集保／內部人／警示股／新聞無 backfill phase | 忽略，重跑無效 |

實際輸出跑一次就有（唯讀、約 1 秒、不寫任何檔）：

```bash
dart run tool/recalibrate.dart --db tool/calibration.db --dry-run
```

> **已知缺口**：這個比對只看 `ReasonType.code`。若 code 沒變、但規則內部閾值
> 改了（例如 `rule_params` 調整），觸發樣本其實已經失效，而差集看不出來——
> 需要靠自己記得。刻意不做參數雜湊：任何無關的參數改動都會誤觸發，訊號會被
> 稀釋成噪音。

## 如何執行

### 完整管線（backfill → replay → recalibrate → walk-forward）

```bash
export FINMIND_TOKEN=<你的 token>   # 必填,兩支腳本都會在缺少時 exit 1
./scripts/calibrate.sh          # 四階段一次跑完，產出 candidate JSON + gate 判準
./scripts/calibrate-retry.sh    # 同上，但自動處理 TWSE 限流（每輪間隔 15 分鐘）
```

規則、參數或資料來源有變動時走這條——只重算評分無法反映新的觸發樣本。

**實測耗時**（2026-08-22，既有 DB 已有 9 年價格的增量情境）：
backfill **~18 分**（實測 17:59:33 起跑、18:18:02 進入 revenue 階段；涵蓋
stock_list + 雙市場價格 + 法人 + 當沖，其中要補的價格缺口是 31 個交易日）、
replay **12–60 分**（實測增量情境 12 分,腳本 banner 保守估 30–60 分）、recalibrate 數秒、walk-forward **~13 分**。
**合計約 45 分鐘**；缺口更大時 backfill 會拉長，故實務上抓 45–75 分。

**基本面預設跳過**（`BACKFILL_SKIP_FUNDAMENTALS` 預設 `1`）。revenue /
financial / valuation 三個 phase 需約 7,710 次 FinMind 呼叫、額度 600/hr
（工具自己估 ~12h51m），單次跑不完，而撞限流會 **abort 整個 backfill**——
連帶讓下一輪只打 1 次的 stock_list 也被鎖在門外。要補時明確 opt-in：

```bash
BACKFILL_SKIP_FUNDAMENTALS=0 ./scripts/calibrate-retry.sh
```

**跳過 gate**：`SKIP_WALKFORWARD=1`（省 ~13 分鐘，但 promote 決策沒有依據）。

### 只重算評分

`recalibrate.dart` 是四階段中的**第三階段**，單獨跑等於沿用既有的 replay 樣本，
只重新計算分數。統計方法或閾值調整時這樣做是對的；規則本身變了則不夠。

工具啟動時會印出 replay 落檔時間**當作背景資訊**——刻意不對「距今幾天」下判決
（時間是錯的軸，理由見上方）。真正的判斷是規則涵蓋差集。

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

**要 approve 當前 candidate**——**三個檔一起搬,漏了 manifest 會靜默失效**：

```bash
mv assets/rule_scores_calibrated_short_candidate.json \
   assets/rule_scores_calibrated_short.json

mv assets/rule_scores_calibrated_long_candidate.json \
   assets/rule_scores_calibrated_long.json

# 🚨 別漏這一個:manifest 記著兩支 JSON 的 sha256,對不上時 OTA 會
# 「hash mismatch」直接跳過更新——沒有錯誤、沒有日誌,只是沒生效
mv assets/calibration_manifest_candidate.json \
   assets/calibration_manifest.json
```

**要退回**：
```bash
rm assets/rule_scores_calibrated_*_candidate.json \
   assets/calibration_manifest_candidate.json
```

退回不需要「等下個月」——校準是事件觸發的（見開頭「何時該跑」）。
先確認 walk-forward 的判準：`WALKFORWARD_VERDICT=FAIL` 就是不該 promote，
那是有效結論而非資料異常。

### 4. Commit + push

```bash
git add assets/rule_scores_calibrated_short.json assets/rule_scores_calibrated_long.json
git commit -m "chore(calibration): promote <horizon> YYYY-MM-DD"
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

判斷 `hit_rate` 是否統計顯著地超過**該 horizon 的實證 baseline**——不是 0.5。

```
z = (hit_rate − baseline) / sqrt(baseline × (1 − baseline) / n)
```

`baseline` 查 `CalibrationThresholds.successProbabilityBaselines`：
**5D = 0.3461、60D = 0.3965**（未列出的 period 才 fallback 0.5）。

> **2026-06-18 修正**：舊版把 null hypothesis 寫死 0.5，而台股實證 baseline
> 與 (horizon, threshold) 強相關——用 0.5 系統性**低估** alpha，曾造成短線
> 0 條 active。變異數也一併改用 `baseline × (1 − baseline)` 而非
> `hit_rate × (1 − hit_rate)`（null hypothesis 下的變異數才是對的）。

Degenerate case（`n ≤ 0` 或 `baseline ∈ {0, 1}`）回傳 `0.0`。注意
`hit_rate ∈ {0, 1}` **不再是** degenerate——hit_rate 已不在分母，
`hit_rate = 0` 且 n 大時會得到很負的 z，落入 `t_stat_below_threshold`。

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

**現行跑的是 clustered 路徑**（live DB 的 `calibration_run_meta.return_mode = excess`）。
兩條路徑的 cut 條件與**順序都不同**：

| # | clustered（現行） | legacy（meta 缺失時） |
|:--|:---|:---|
| 1 | `n < 30` → `sample_too_small` | 同左 |
| 2 | **`distinct_dates < 30` → `dates_too_few`** | *（無此檢查）* |
| 3 | `t_stat < 1.5` → `t_stat_below_threshold` | `z_stat < 1.5` → 同名 |
| 4 | `hit_rate < baseline_hit + 0.05` | `hit_rate < 0.55`（絕對值） |

門檻常數：`CalibrationThresholds` 的 `minDistinctDates`（30）、
`tStatCutThreshold`（1.5）、`hitRateLiftThreshold`（0.05）、
`sampleSizeCutThreshold`（30）。

被 cut 的規則 `score = 0`、`active = false`，runtime 行為見
[docs/RULE_ENGINE.md](RULE_ENGINE.md) 的「基準分不是實際生效的分數」。

### 邊界案例示意

> ⚠️ 這裡刻意不列具體 z 值。舊版曾列一張用 **2026-06-18 之前的公式**算出來的
> 表（baseline 寫死 0.5、變異數用 hit_rate），三個 case 的 z 與判定在現行
> 實作下全部不同。要看真實數字請跑 `--dry-run` 並讀 candidate JSON 的
> `t_stat` / `cut_reason` 欄位。

判定順序（clustered 路徑，見上一節）：

1. `n < 30` → `sample_too_small`
2. `distinct_dates < 30` → `dates_too_few`
3. `t_stat < 1.5` → `t_stat_below_threshold`
4. `hit_rate < baseline_hit + 0.05` → `hit_rate_below_threshold`

## JSON 輸出格式

```json
{
  "schema_version": 1,
  "horizon": "5d",
  "generated_at": "2026-08-22T13:01:34.014981Z",
  "backtest": {
    "success_threshold_pct": 0.0,
    "formula": "linear_map_v1",
    "return_mode": "excess",
    "stats_method": "date_clustered_t_v1",
    "baseline_hit_rate": 0.4357
  },
  "rules": {
    "WEEK_52_HIGH": {
      "score": 35,
      "hit_rate": 0.4776,
      "avg_return": 3.6545,
      "samples": 32241,
      "t_stat": 7.8173,
      "active": true
    },
    "PATTERN_DOJI": {
      "score": 0,
      "hit_rate": 0.3747,
      "avg_return": 0.0683,
      "samples": 6179,
      "t_stat": -1.6357,
      "active": false,
      "cut_reason": "t_stat_below_threshold"
    }
  }
}
```

> `rules` 的鍵是 **`ReasonType.code`（UPPER_SNAKE）**，直接來自
> `rule_accuracy.rule_id`——不是 Dart enum 的識別字。

### 欄位說明

| 欄位 | 說明 |
|:---|:---|
| `backtest.success_threshold_pct` | 「成功」的報酬門檻。clustered 路徑寫 `runMeta.excessThreshold`（現行 **0.0**，因為 excess 模式比的是超額報酬）；legacy 路徑才用 `CalibrationThresholds.successThresholds`（5D=1.5 / 60D=8.0） |
| `backtest.formula` | 目前恆為 `linear_map_v1` |
| `backtest.return_mode` | `excess`（橫斷面超額）或 `absolute`。**App 的 drift guard 會讀它**決定 canonical 門檻 |
| `backtest.stats_method` | clustered 路徑寫 `date_clustered_t_v1`；legacy 不寫 |
| `backtest.baseline_hit_rate` | 該 horizon 全 universe 實測的 P(excess ≥ threshold)，clustered 的 hit cut 以它為基準 |
| `rules.*.score` | 10–35 或 0（被 cut）。**這不是實際生效分數**，見 [RULE_ENGINE.md](RULE_ENGINE.md) |
| `rules.*.t_stat` | clustered 路徑是 date-clustered 單樣本 t；legacy 是 proportion z |
| `rules.*.cut_reason` | 只在 `active: false` 時出現，四種值見「Cut 規則」 |

> **已移除的欄位**：`window_days` / `train_ratio` 於 2026-07-23 稽核後刪除
> ——它們宣稱的「2 年窗 / 0.7 split」與實際脫節（replay 吃全庫多年資料、
> split 在獨立的 walkforward_validate）。舊的 production JSON 仍帶著這兩個鍵，
> 只是因為還沒重新產出過。

## Troubleshooting

### ❌ `DB file 找不到`

**先確認你是不是根本不該看到這個訊息。** 校準管線用的是 `tool/calibration.db`
（`scripts/calibrate.sh` 會設好 `CALIBRATION_DB`）。只有在**手動裸跑**
`dart run tool/recalibrate.dart` 而沒帶 `--db` 時，才會走到 auto-detect。

```bash
dart run tool/recalibrate.dart --db tool/calibration.db
```

> 🚨 **不要用 `find ~ -name "afterclose*.sqlite"` 的結果。**
> auto-detect 只找 App 容器的 `~/Library/Containers/com.neo.afterclose/…/afterclose.sqlite`
> ——那是**App 的即時資料庫，不是校準用的**。兩者都有 `rule_accuracy` 表，所以
> 指錯不會報錯，會**靜默算出無意義的結果**：
>
> | | App 容器 DB | `tool/calibration.db` |
> |:---|:---|:---|
> | periods | 1D/3D/5D/10D/20D（**無 60D**） | 5D / 60D |
> | 5D firings | 約 1.7 萬 | 約 312 萬 |
> | `calibration_run_meta` | **表不存在** | 有 |
>
> 後果：長線直接失敗；短線**會成功**，但因為缺 `calibration_run_meta`，
> 會退回舊的 absolute 決策層（輸出會印 `🧮 舊決策層（absolute / meta 缺失）`），
> 產出一份決策層與現行 production 不相容的 candidate。exit 0，檔案照寫。

### ⚠️ `rule_accuracy 沒有 XX 的統計資料`

這張表由 **Stage 2 replay** 寫入（每次執行整表刪除重建），不是 App 產生的。

| 可能原因 | 怎麼確認 / 解法 |
|:---|:---|
| 指錯 DB | 見上一節——`--db tool/calibration.db` |
| 還沒跑過 replay | `CALIBRATION_DB=tool/calibration.db flutter test test/tool/run_replay.dart` |
| replay 跑了但沒 firing | 檢查 `daily_price` 筆數是否合理；三檔以下的樣本會 0 firings 直接 exit 3 |
| **被 walk-forward 洗掉**（2026-08-22 前） | 見下方「所有規則都被 cut」 |

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

**歷次 promote 決策記在 commit body,不在這裡。** 這一節曾經是手抄的變更清單,
但六次 promote 只記了一次(而且記的是「決定不 promote」),漂移六週無人察覺——
git 本來就記得更完整,而且不會過期。

```bash
git log --format='%h %ad %s%n%b' --date=short \
  -- assets/rule_scores_calibrated_short.json assets/rule_scores_calibrated_long.json
```

決策報告(較深入的那幾次):

| 日期 | 報告 |
|:---|:---|
| 2026-07-10 | [excess 決策層 clustered t-stat](plans/2026-07-10-excess-decision-layer-clustered-tstat.md) |
| 2026-07-13 | [gapfill 重校準報告](plans/2026-07-13-gapfill-recalibration-report.md) |

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

關鍵決策（來自 2026-04-11 brainstorming session；原始設計文件已刪除，
其鎖定的門檻與 baseline 已被下方「實證背景」段落取代）：
- 公式選 **linear_map_v1**（interpretable），非 IC-based 或 logistic regression
- **雙 horizon** 策略：短 5D + 長 60D，每條規則在兩個 horizon 各有獨立分數
- Cut threshold **嚴格版**：t_stat<1.5 / hit_rate<55% / n<30
- **月度人工 review gate**：絕不自動覆寫 production
  （*節奏部分已於 2026-08-22 修訂為事件觸發，見上方「何時該跑 calibration」；「絕不自動覆寫」不變*）
- Stage 2 只建 pipeline，**不消費** JSON（消費工作在 Stage 5，需真實資料驗證架構）
