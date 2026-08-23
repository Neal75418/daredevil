# Rule Score 重新校準 — Design Spec

> ⚠️ **四項已被後續決策推翻：**
> 1. §2 非目標「不改 recalibrate.dart 的 cut 規則」——三週後被 clustered
>    超額設計推翻，現行 cut 見 `docs/CALIBRATION.md`。
> 2. §4a「`successThresholds` 改為超額語意」**沒有發生**，改為另加
>    `excessSuccessThreshold`。
> 3. §4b「季末 + 45 天」**刻意否決**，現行是固定 5/15、8/14、11/14、次年 3/31。
> 4. §3／§7 的 `scripts/recalibrate.sh` 從未建立，包裝腳本是 `scripts/calibrate.sh`，
>    且順序是 backfill → replay → recalibrate → walkforward（與本文圖相反）。
>
> 仍有效的是 §1 的三項偏誤診斷，與 §5「勝幅 > 折間離散度」判準。

> 用「修正後的回測方法論」重新產生 calibrated rule scores，讓選股建立在**真 alpha**（超額報酬）而非多頭 beta 上，並用 **rolling walk-forward（含 2022 空頭樣本外）** 證明新校準在沒看過的資料上確實不輸舊版，才允許 ship。
>
> **狀態**：Design（待實作）。全程離線於 `tool/`，production scoring 不動，直到人工確認新 JSON 樣本外勝出。

---

## 1. 背景與動機

現行 calibrated scores（`assets/rule_scores_calibrated_{short,long}.json`，餵 scoring isolate）由現有離線 pipeline 產生：`tool/backfill.dart` → `tool/replay_calibrator.dart`（算 forward return → `rule_accuracy`）→ `tool/recalibrate.dart`（→ JSON）。

審查發現該方法論有三個會「高估訊號準度、把 beta 當 alpha」的問題：

1. **絕對 forward 報酬**（`prices[i+N] / prices[i]`，未減基準）→ 多頭期所有股票都漲，訊號看起來都準。`tool/calibration.db` 樣本實為 **2024–2026 多頭主導**（507/518 天；缺 2021–2023；2017–2020 各僅 1–7 天）。
2. **look-ahead**：replay 以 `date <= currentDate` 過濾歷史（正確），但 `monthly_revenue.date` 是「營收月」而非「公布日」。台股月營收次月 10 號才公布 → 5/15 的訊號會偷看到尚未公布的 5 月營收（~40 天前視偏誤），膨脹基本面訊號表現。
3. **單一多頭樣本**：缺空頭/盤整，無法驗證 regime-robustness。

**目標**：修正以上三點 → 重算 → 用 walk-forward 樣本外驗證 →（僅在勝出時）人工 ship 新 JSON。

## 2. 非目標（Non-goals）

- 不改 runtime scoring/選股邏輯（只換產出的 JSON assets）。
- 不做類股相對基準、per-股 beta 調整、多因子 IC 分解、完整顯著性檢定機制 — 對散戶本地 app 過度。
- 不改 `tool/recalibrate.dart` 的 `linear_map_v1` 映射公式與 cut 規則（只改其輸入統計的正確性）。
- 不自動覆寫 production JSON — 永遠保留人工 review gate。

## 3. 架構與資料流

延伸既有 `tool/` 離線 pipeline，新增一個 walk-forward 驗證器。

```
backfill.dart            replay_calibrator.dart          walkforward_validate.dart (NEW)        recalibrate.dart
──────────────           ──────────────────────          ──────────────────────────────        ────────────────
+ 2021-2023 全日   →     橫斷面超額報酬             →     rolling folds（含 2022 OOS）       →   rule_accuracy
  價格（全市場）         （當日全市場均值為基準）         新校準 vs 舊校準的高分股               → 候選 JSON
                         look-ahead 修正                  樣本外超額報酬／回檔／一致性                ↓
                         → rule_accuracy                  → PASS/FAIL 報告                      人工 review → ship
```

**5 個元件（4 個既有延伸 + 1 個新增）：**

| 元件 | 現況 | 本次改動 |
|---|---|---|
| `tool/backfill.dart` | 抓歷史價格進 `calibration.db` | **+ 2021–2023 全日全市場價格** |
| `tool/replay_calibrator.dart` | 算絕對 forward return → `rule_accuracy` | **改橫斷面超額報酬 + 修 look-ahead** |
| `tool/walkforward_validate.dart` | ❌ 不存在 | **新增：rolling 樣本外驗證 gate** |
| `tool/recalibrate.dart` | `rule_accuracy` → JSON | 不動邏輯（吃修正後的統計） |
| `scripts/recalibrate.sh` | 部分存在（`calibrate.sh`） | **包成一鍵 wrapper：backfill→replay→validate→recalibrate** |

**原則**：整條離線跑；production 的 `assets/*.json` 完全不動，直到人工確認新版樣本外勝出才換上（換上只是替換 asset 檔，runtime loader 已會讀）。

## 4. 方法論修正（3）

### 4a. 橫斷面超額報酬（cross-sectional demean）

取代絕對報酬。對每個 firing 在 horizon `N`（5D / 60D）：

```
universeMeanReturn[d, N] = mean over all symbols s with valid price[d] and price[d+N] of
                           (price[s, d+N] - price[s, d]) / price[s, d]
excessReturn[s, d, N]    = (price[s, d+N] - price[s, d]) / price[s, d]  -  universeMeanReturn[d, N]
```

- **基準 = 當日全市場（universe）平均 forward 報酬**，不需 backfill 任何指數序列（universe 本身即基準），自動 regime 中性、部分中性化類股。
- success 判定改用「`excessReturn >= 0`」（贏過當日大盤平均）取代現行絕對門檻；`CalibrationThresholds.successThresholds` 改為「超額」語意（5D/60D 門檻可保留為超額百分點，預設 0）。
- `universeMeanReturn` 採 equal-weight（每日對所有有效 symbol 取算術平均）；cap-weight 留 v2。

### 4b. look-ahead 修正（基本面 lag 公布日）

point-in-time 過濾改用「實際公布日」而非「資料期間」：

- **月營收**：可見日 = 營收月次月 10 號（例：5 月營收 → 6/10 起可見）。replay 過濾條件由 `revenue.date <= currentDate` 改為 `announceDate(revenue) <= currentDate`，其中 `announceDate = 次月 10 號`。
- **季財報 / EPS（`stock_valuation`）**：可見日 = 季末 + 45 天（法說慣例）。**實作前先確認 `stock_valuation.date` 語意**（若已是公布日則不需 lag）。
- 純價量訊號不受影響（價格當日即可見）。

### 4c. 多空樣本回補

- `tool/backfill.dart` 補 **2021–2023 全日全市場價格**進 `calibration.db`（含 2022 空頭 −22% + 2023 復甦），湊成 **2021–2026 跨多空 ~1250 交易日**。
- 2017–2020 的 11 天太稀疏 → 留著無害、不特別補（replay 逐日處理）。

## 5. Walk-forward 驗證（核心 gate）

新增 `tool/walkforward_validate.dart`。

- **Fold 方案：leave-one-year-out（2022–2026 各當一折測試集）**。每折用「其餘所有年度」校準（replay + recalibrate on train），在「held-out 該年」模擬高分股的**樣本外超額報酬**。共 5 折。
  - 解讀：這是**跨 regime 穩定度**測試（用其餘年度的市況校準，看在沒納入的那一年是否仍成立），非即時前瞻模擬。
  - **2022 折最關鍵**（train = 2021 + 2023–2026，test = 2022 空頭）→ 直接、誠實地測「沒看過這段空頭時撐不撐得住」。
  - 2021 最早年資料較薄，仍納入為一折但權重視為次要參考。
- **對照組**：每折同時用「現行 production 校準（舊 JSON）」在同測試集模擬，作為 baseline。
- **多準則 ship gate**（全部需通過）：
  1. **超額報酬**：新校準各折樣本外平均超額報酬 ≥ 舊校準，且勝幅 **大於折間離散度**（不是噪音）。
  2. **下檔**：新校準的樣本外最大回檔 **不惡化**於舊校準（尤其 2022 折）。
  3. **一致性**：新校準在「多數折」勝出，而非單折暴衝平均。
  4. **不偷調**：方法論定稿後**跑一次就認帳**，不對著測試集反覆調參（避免選擇性過擬合）。
- gate 未過 → **不 ship**，結論為「現有校準已足夠」（亦為有效結果）。

## 6. Review / Ship / Rollback

- **產出**：候選 JSON（`*_candidate.json`，沿用現有命名）+ **驗證報告**（各折樣本外新舊對比 + 2022 折細節 + 新舊分數 diff）。
- **人工 gate**：使用者讀報告 → 多準則通過 → 核准 → 以候選覆蓋 `assets/rule_scores_calibrated_{short,long}.json` + 更新 `assets/calibration_manifest.json` + commit。
- **Rollback**：舊 JSON 留 git 歷史，回退一個 commit 即還原。

## 7. 操作模式

- 離線腳本 + **一鍵 wrapper**（`scripts/recalibrate.sh`：backfill→replay→validate→recalibrate，印出 gate 報告）。
- **本次由開發協作方背景執行**（backfill ~1–3h、replay 數十分、validate/recalibrate 數分；總計約半天、unattended），完成後將驗證報告交付使用者決定是否 ship。
- wrapper 留作未來重校準用（每月 / 版本前 / 新增 rule 後）。

## 8. 測試

- **單元**：橫斷面超額報酬計算（含當日 universe 均值）、look-ahead lag（次月 10 號 / 季末 +45 天的可見日過濾）、walk-forward 折切分與 gate 判定。
- **回歸**：現有 `replay_calibrator` / `recalibrate` / `rule_accuracy_service` 測試保持綠（或對齊新語意更新）。
- **Sanity**：候選 JSON 無 NaN、score 量級合理、未整批被 cut。
- 不需 widget / runtime 測試（無 app runtime 改動）。

## 9. 風險與已知限制

- **測試集仍偏多頭**：2025–2026 偏多頭，故 2022 折是空頭樣本外的主要證據；rolling 多折降低單刀運氣。
- **2021–2023 資料品質**：FinMind 歷史可能有缺漏 / 調整股價問題 → backfill 後做覆蓋率 sanity。
- **橫斷面均值的 universe 一致性**：半套日（覆蓋不全）會使當日均值偏移 → 計算 `universeMeanReturn` 時對每日設最小 symbol 數門檻，不足者該日不納入。
- **可能結論是「不該動」**：若 gate 未過，產出即「現行校準在樣本外已足夠」— 這是預期且可接受的結果。
- **look-ahead 假設**：次月 10 號 / 季末 +45 天是慣例近似；個別公司提前/延後公布未逐一精確對齊（v2 可接精確公布日資料）。

## 10. 變更紀錄

- 2026-06-22：初稿。方案 B（修核心偏誤 + walk-forward），基準採 cross-sectional demean（取代 TAIEX 超額）、切分採 rolling 含 2022 樣本外、gate 採多準則務實版。
