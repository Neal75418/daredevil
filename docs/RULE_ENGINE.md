# 🧠 Rule Engine

> ← [Back to README](../README.md)

Daredevil 推薦規則引擎 — **70 條異常偵測規則**（產生 72 種 reason type）

> 權威數字：`RuleRegistry.defaultRules.length` 與 `ReasonType` enum。四份文件的規則數
> 由 `test/docs/doc_rule_count_consistency_test.dart` 守住，新增規則時會提醒同步。

---

## 🎯 定位

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR
    Data["市場資料"] --> Engine["Rule Engine\n64 Rules"]
    Engine --> Score["分數合成"]
    Score --> Modes["三模式選股<br/>起漲 / 強勢 / 回檔"]

    style Data fill:#2563EB,color:#fff,stroke:#1D4ED8
    style Engine fill:#4F46E5,stroke:#3730A3,color:#fff
    style Score fill:#059669,color:#fff,stroke:#047857
    style Top fill:#D97706,color:#fff,stroke:#B45309
```

| 項目 | 說明                    |
|:---|:----------------------|
| 目的 | 異常提示（Attention Alert） |
| 產出 | 每檔全部去重理由（UI 以 take(2)/take(3) 控制顯示數量） |
| 分數 | 0 ~ 80（負分歸零，上限 80）    |
| 輸出 | 三模式選股（起漲 / 強勢 / 回檔）   |

---

## 📊 規則分佈

```mermaid
%%{init: {'theme': 'dark'}}%%
pie showData title 依類別分佈（66 reason / 64 規則）
    "技術型態 (21)" : 21
    "價量訊號 (12)" : 12
    "基本面 (15)" : 15
    "籌碼面 (7)" : 7
    "殺手級功能 (7)" : 7
    "強股回檔 (4)" : 4
```

---

## 📈 技術型態

### 基礎規則 (9)

| 規則                  |  分數 | 條件                         |
|:--------------------|----:|:---------------------------|
| REVERSAL_W2S        | +35 | 弱轉強：突破區間上緣                 |
| REVERSAL_S2W        | -25 | 強轉弱：跌破支撐                   |
| TECH_BREAKOUT       | +25 | 突破壓力位（3% buffer + MA20 確認） |
| TECH_BREAKDOWN      | -20 | 跌破支撐位（3% buffer + 量能確認；無 MA20 過濾，多空不對稱為現狀，對稱化需回測驗證） |
| VOLUME_SPIKE        | +22 | 量 >= 4x 均量且價變 >= 1.5%      |
| PRICE_SPIKE         | +15 | 日漲幅 >= 5%（僅正向；空方由 PRICE_VOLUME_BEARISH_DIVERGENCE / TECH_BREAKDOWN 覆蓋，2026-07 audit 修正） |
| INSTITUTIONAL_BUY   | +18 | 法人買超轉向                     |
| INSTITUTIONAL_SELL  | -12 | 法人賣超轉向                     |
| NEWS_RELATED        |  +8 | 近期相關新聞                     |

### K 線型態 (12)

| 規則                           |  分數 | 說明        |
|:-----------------------------|----:|:----------|
| PATTERN_DOJI                 | +10 | 十字線（低檔猶豫） |
| PATTERN_DOJI_BEARISH         |  -5 | 十字線（高檔警示） |
| PATTERN_BULLISH_ENGULFING    | +22 | 多頭吞噬      |
| PATTERN_BEARISH_ENGULFING    | -10 | 空頭吞噬      |
| PATTERN_HAMMER               | +18 | 錘子線（底部反轉） |
| PATTERN_HANGING_MAN          | -12 | 吊人線（頭部警示） |
| PATTERN_GAP_UP               | +20 | 跳空上漲      |
| PATTERN_GAP_DOWN             |  -8 | 跳空下跌      |
| PATTERN_MORNING_STAR         | +25 | 晨星（底部反轉）  |
| PATTERN_EVENING_STAR         | -10 | 暮星（頭部反轉）  |
| PATTERN_THREE_WHITE_SOLDIERS | +22 | 三白兵       |
| PATTERN_THREE_BLACK_CROWS    | -18 | 三黑鴉       |

---

## 📉 價量訊號

### 技術指標 (8)

| 規則                     |  分數 | 條件               |
|:-----------------------|----:|:-----------------|
| WEEK_52_HIGH           | +28 | 52 週新高           |
| WEEK_52_LOW            |  +8 | 52 週新低（逆勢機會）     |
| MA_ALIGNMENT_BULLISH   | +22 | 多頭排列（5>10>20>60） |
| MA_ALIGNMENT_BEARISH   | -15 | 空頭排列             |
| RSI_EXTREME_OVERBOUGHT |  -8 | RSI > 85（警示）     |
| RSI_EXTREME_OVERSOLD   | +10 | RSI < 30（反彈機會）   |
| KD_GOLDEN_CROSS        | +18 | K 上穿 D（低檔區 < 30） |
| KD_DEATH_CROSS         | -12 | K 下穿 D（高檔區 > 70） |

### 價量背離 (4)

| 規則                              |  分數 | 說明       |
|:--------------------------------|----:|:---------|
| PRICE_VOLUME_BULLISH_DIVERGENCE |  -8 | 價漲量縮（警示） |
| PRICE_VOLUME_BEARISH_DIVERGENCE | -15 | 價跌量增（恐慌） |
| HIGH_VOLUME_BREAKOUT            | +22 | 高檔爆量突破   |
| LOW_VOLUME_ACCUMULATION         | +12 | 低檔吸籌     |

---

## 👥 籌碼面

| 規則                              |  分數 | 條件                   |
|:--------------------------------|----:|:---------------------|
| INSTITUTIONAL_BUY_STREAK        | +20 | 法人連買 >= 4 日          |
| INSTITUTIONAL_SELL_STREAK       | -15 | 法人連賣 >= 4 日          |
| FOREIGN_SHAREHOLDING_INCREASING | +18 | 外資持股 5 日增 >= 0.5%    |
| FOREIGN_SHAREHOLDING_DECREASING | -12 | 外資持股 5 日減 >= 0.5%    |
| DAY_TRADING_HIGH                | +12 | 當沖比例 >= 50% + 萬張以上   |
| DAY_TRADING_EXTREME             |  -5 | 當沖比例 >= 70% + 3 萬張以上 |
| CONCENTRATION_HIGH              |   0 | 大戶持股集中度 >= 60%（noise filter, demote 0） |

---

## 🏦 基本面

### 營收與估值 (8)

| 規則                  |  分數 | 條件                      |
|:--------------------|----:|:------------------------|
| REVENUE_YOY_SURGE   | +20 | 營收年增 > 30% + 站上 MA60    |
| REVENUE_YOY_DECLINE | -10 | 營收年減 > 20%              |
| REVENUE_MOM_GROWTH  | +15 | 營收月增連續正成長 + 站上 MA20     |
| REVENUE_NEW_HIGH    |   0 | 營收創歷史新高（noise filter, demote 0）      |
| HIGH_DIVIDEND_YIELD | +18 | 殖利率 > 5.5%              |
| PE_UNDERVALUED      | +15 | PE < 10（且 > 0）+ 站上 MA20 |
| PE_OVERVALUED       |  -8 | PE > 60 + RSI > 75      |
| PBR_UNDERVALUED     | +12 | 股價淨值比 < 0.8             |

### EPS 分析 (4)

| 規則                     |  分數 | 條件                                |
|:-----------------------|----:|:----------------------------------|
| EPS_YOY_SURGE          | +22 | EPS 年增 >= 50% + 站上 MA60           |
| EPS_CONSECUTIVE_GROWTH | +18 | 連續 >= 2 季 EPS 季增 >= 10% + 站上 MA20 |
| EPS_TURNAROUND         | +15 | 前季虧損、本季 EPS >= 0.3 元              |
| EPS_DECLINE_WARNING    | -12 | 連續 2 季 EPS 季減 >= 20%              |

### ROE 分析 (3)

| 規則            |  分數 | 條件                                |
|:--------------|----:|:----------------------------------|
| ROE_EXCELLENT | +18 | ROE >= 15% + 站上 MA20              |
| ROE_IMPROVING | +15 | 連續 >= 2 季 ROE 改善 >= 5pt + 站上 MA20 |
| ROE_DECLINING | -10 | 連續 >= 2 季 ROE 衰退 >= 5pt           |

---

## 🚨 殺手級功能

### 警示股票 (2)

| 規則                        |  分數 | 條件      | 來源        |
|:--------------------------|----:|:--------|:----------|
| TRADING_WARNING_ATTENTION | -15 | 被列為注意股票 | TWSE/TPEX |
| TRADING_WARNING_DISPOSAL  | -50 | 被列為處置股票 | TWSE/TPEX |

### 董監持股 (3)

| 規則                         |  分數 | 條件             |
|:---------------------------|----:|:---------------|
| INSIDER_SELLING_STREAK     | -25 | 董監連續減持 >= 3 個月 |
| INSIDER_SIGNIFICANT_BUYING | +20 | 董監增持 >= 5%     |
| HIGH_PLEDGE_RATIO          | -18 | 質押比例 >= 70%    |

### 外資集中度 (2)

| 規則                            |  分數 | 條件              |
|:------------------------------|----:|:----------------|
| FOREIGN_CONCENTRATION_WARNING |  -8 | 外資持股 >= 60%     |
| FOREIGN_EXODUS                | -20 | 5 日外資流出 >= 2%   |

---

## 🔄 強股回檔（Mode C v2）

### 回檔進場 (4)

| 規則                |  分數 | 條件                            |
|:------------------|----:|:------------------------------|
| PULLBACK_TO_MA20  | +15 | 強勢趨勢拉回 MA20、量縮、趨勢未破           |
| PULLBACK_TO_MA10  | +12 | 淺回檔至 MA10（close 仍在 MA20 上）、量縮 |
| HAMMER_AT_SUPPORT | +18 | 拉回 MA20/MA60 支撐 + 錘子線止跌       |
| KD_HIGH_PULLBACK  | +12 | KD 高檔回落未死叉、多頭排列維持             |

---

## 🧮 分數合成

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR
    Rules["Rule Scores"] --> Bonus["加成"]
    Bonus --> Cap["0 ~ 80"]

    style Rules fill:#2563EB,color:#fff,stroke:#1D4ED8
    style Bonus fill:#059669,color:#fff,stroke:#047857
    style Cap fill:#D97706,color:#fff,stroke:#B45309
```

| 階段 | 邏輯                                                                                      |
|:---|:----------------------------------------------------------------------------------------|
| 加成 | 投信主導 +5（其餘 VOLUME / BREAKOUT 組合加成已於 2026-04 移除，改由個別規則內建量能要求） |
| 截斷 | 負分歸零、上限 80                                                                              |

---

## ⚙️ 關鍵參數

> 來源：`lib/core/constants/rule_params.dart`（8 typed classes, 200+ 參數）

| 參數                          |   值 | 說明         |
|:----------------------------|----:|:-----------|
| lookbackPrice               | 370 | 分析視窗（日曆日）  |
| volMa                       |  20 | 均量計算天數     |
| volumeSpikeMult             |  4x | 放量門檻       |
| breakoutBuffer              |  3% | 突破緩衝區      |
| institutionalStreakDays     |   4 | 法人連續買賣天數   |
| insiderSellingStreakMonths  |   3 | 董監連續減持月數   |
| highPledgeRatioThreshold    | 70% | 高質押門檻      |
| foreignConcentrationWarning | 60% | 外資集中警告     |
| concentrationHighThreshold  | 60% | 籌碼集中度門檻    |
| peOvervaluedThreshold       |  60 | PE 過高警示門檻  |
| epsYoYSurgeThreshold        | 50% | EPS 年增暴增門檻 |
| epsConsecutiveQuarters      |   2 | EPS 連續成長季數 |
| roeExcellentThreshold       | 15% | ROE 優異門檻   |
| minScoreThreshold           |  12 | 最低評分門檻     |

---

## 💾 資料表

| 表                    | 用途       |
|:---------------------|:---------|
| stock_master         | 股票主檔     |
| daily_price          | 日 K 資料   |
| daily_institutional  | 法人買賣超    |
| trading_warning      | 注意/處置股票  |
| insider_holding      | 董監持股     |
| daily_analysis       | 分析結果     |
| daily_reason         | 觸發理由（三模式選股即時聚合來源） |

---

← [Back to README](../README.md) | 📚 [All Documentation](../README.md#文件)
