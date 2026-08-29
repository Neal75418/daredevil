import 'dart:math' as math;

import 'package:daredevil/domain/models/market_overview_models.dart';

/// 市場情緒分數等級
enum SentimentLevel {
  extremeFear, // 0-20
  fear, // 20-40
  neutral, // 40-60
  greed, // 60-80
  extremeGreed, // 80-100
}

/// 市場情緒計算結果
/// 情緒分數的子指標權重。
///
/// **有效權重正規化**：缺席的子指標不算進分母——這讓「25% 法人分量憑空
/// 消失」與完整計算的 gauge 外觀完全相同(靜默稽核 #7 附帶效應)。權重表
/// 公開讓 UI 拿得到權威分母,對 [MarketSentiment.subScores] 的長度差
/// 掛「N 項子指標缺席」註記,而不是在 widget 裡重寫魔術數字 5。
const Map<String, double> subScoreWeights = {
  'advanceRatio': 0.35,
  'institutional': 0.25,
  'volumeMomentum': 0.15,
  'marginChange': 0.15,
  'industryBreadth': 0.10,
};

class MarketSentiment {
  const MarketSentiment({
    required this.score,
    required this.level,
    required this.subScores,
  });

  /// 綜合分數 0-100
  final double score;

  /// 情緒等級
  final SentimentLevel level;

  /// 各子指標分數 (key → 0~100)
  final Map<String, double> subScores;

  static const _empty = MarketSentiment(
    score: 50,
    level: SentimentLevel.neutral,
    subScores: {},
  );
}

/// 市場情緒計算服務
///
/// 綜合 5 項市場指標計算單一情緒分數 (0-100)。
/// 純計算，無 IO 依賴，易於單元測試。
class MarketSentimentService {
  const MarketSentimentService._();

  /// 漲跌比子指標的線性映射下界／上界（ratio = advance / (advance+decline)）。
  ///
  /// **依實測母體百分位錨定**（2026-08-29 稽核 H2，597 個市場日）：
  /// 排除平盤後的 ratio 分布 p5 = 0.149、p95 = 0.801。上界 0.80 沿用舊值
  /// （本來就等於 p95）；下界由 0.20 下修到 0.15，飽和率因此從 9.5%/2.8%
  /// （不對稱、偏向恐慌側）變成 5%/5%，而中位日（ratio 0.481）從讀 39.2 分
  /// 變成讀 50.9 分。
  ///
  /// **兩件事必須一起改**：只換分母是半套——上下界原本是配著含平盤的分母
  /// 定的。錨定方法與籌碼集中度門檻那次相同（量母體、取百分位）。
  ///
  /// 專案早有同樣的區分：`MarketReadingService` 的內部家數判定寫著「分母
  /// **刻意排除持平**……門檻常數是依『排除持平』的比例校準」——門檻判定排除
  /// 持平、顯示（漲/平/跌三段堆疊條）保留它。情緒儀表原本是唯一的例外。
  static const double advanceRatioFloor = 0.15;
  static const double advanceRatioCeil = 0.80;

  /// 回溯計算歷史情緒分數所需的最少對齊交易日數。
  ///
  /// 等同 Z-score（法人動向子指標）的最小樣本數：少於此日數無法產生有意義的
  /// 標準差，[calculateHistoricalScores] 直接回傳空列表。
  static const _kMinHistoricalDays = 5;

  /// 計算市場情緒分數
  ///
  /// 所有 history 參數為 oldest→newest 時序排列。
  static MarketSentiment calculate({
    required AdvanceDecline advanceDecline,
    required List<double> institutionalNetHistory,
    required List<double> turnoverHistory,
    required List<double> marginBalanceHistory,
    List<IndustrySummary> industries = const [],
  }) {
    final subScores = <String, double>{};

    // 1. 漲跌比 (35%) — advance / (advance + decline) 線性映射
    //
    // **分母不含平盤**（2026-08-29 稽核 H2）：`AdvanceDecline.total` 含
    // unchanged，而那是真實計數（實測佔上市櫃股 7.8–11.1%）。[_linearMap]
    // 的中點對應 50 分，把平盤算進分母就需要遠超過半數的股票上漲才達得到
    // ——實測 597 個市場日的中位 ratio：含平盤 0.435、排除平盤 0.481。
    // 舊界下中位日讀 39.2 分（偏恐慌側），而這是**權重最大**的子指標（0.35），
    // 其他指標缺席時的有效權重正規化還會把偏差放大到約 8 分。
    // 具體：2026-08-27 TWSE 589 漲 / 521 跌（真的偏多）卻讀 46.7。
    // ⚠️ 條件由 `total > 0` 改成 `advance + decline > 0`，這也改了一個邊界
    // 語意：**全場平盤**（advance = decline = 0、unchanged > 0）時本子指標
    // 整條缺席，由有效權重正規化把其餘四項放大；舊碼會算出 ratio 0 → 0 分
    // ＝「極度恐慌」。沒有漲跌家數就不該宣稱方向，缺席比 0 分誠實。
    final adDirectional = advanceDecline.advance + advanceDecline.decline;
    if (adDirectional > 0) {
      final ratio = advanceDecline.advance / adDirectional;
      subScores['advanceRatio'] = _linearMap(
        ratio,
        advanceRatioFloor,
        advanceRatioCeil,
      );
    }

    // 2. 法人動向 (25%) — 近10日淨額 Z-score → 0-100
    if (institutionalNetHistory.length >= 5) {
      final recent10 = institutionalNetHistory.length >= 10
          ? institutionalNetHistory.sublist(institutionalNetHistory.length - 10)
          : institutionalNetHistory;
      subScores['institutional'] = _zScoreToScore(recent10);
    }

    // 3. 成交量動能 (15%) — 今日量 / 5日均量
    if (turnoverHistory.length >= 2) {
      final today = turnoverHistory.last;
      final histDays = turnoverHistory.length >= 6
          ? turnoverHistory.sublist(
              turnoverHistory.length - 6,
              turnoverHistory.length - 1,
            )
          : turnoverHistory.sublist(0, turnoverHistory.length - 1);
      final avg = histDays.fold<double>(0, (s, v) => s + v) / histDays.length;
      if (avg > 0) {
        final volumeRatio = today / avg;
        // 0.5→0, 1.0→50, 2.0→100
        subScores['volumeMomentum'] = _linearMap(volumeRatio, 0.5, 2.0);
      }
    }

    // 4. 融資變化 (15%) — 近5日融資餘額變動方向+幅度
    if (marginBalanceHistory.length >= 2) {
      final recent5 = marginBalanceHistory.length >= 5
          ? marginBalanceHistory.sublist(marginBalanceHistory.length - 5)
          : marginBalanceHistory;
      final change = recent5.last - recent5.first;
      final base = recent5.first.abs();
      if (base > 0) {
        final changePct = change / base;
        // -5%→0, 0→50, +5%→100
        subScores['marginChange'] = _linearMap(changePct, -0.05, 0.05);
      }
    }

    // 5. 產業廣度 (10%) — 上漲產業數/總產業數
    if (industries.isNotEmpty) {
      final upCount = industries.where((i) => i.avgChangePct > 0).length;
      subScores['industryBreadth'] = upCount / industries.length * 100;
    }

    // 加權計算
    if (subScores.isEmpty) return MarketSentiment._empty;

    const weights = subScoreWeights;

    double totalWeight = 0;
    double weightedSum = 0;
    for (final entry in subScores.entries) {
      final w = weights[entry.key] ?? 0;
      weightedSum += entry.value * w;
      totalWeight += w;
    }

    // 有效權重正規化（某些指標可能缺失）
    final score = totalWeight > 0
        ? (weightedSum / totalWeight).clamp(0.0, 100.0)
        : 50.0;

    return MarketSentiment(
      score: score,
      level: _scoreToLevel(score),
      subScores: subScores,
    );
  }

  /// 計算歷史情緒分數序列（供趨勢 sparkline）
  ///
  /// ⚠️ **輸入口徑與 [calculate] 不一致，目前無害但要知道**（2026-08-29）：
  /// 本函式把 [advanceRatioHistory] 重建成 `AdvanceDecline(advance: r*1000,
  /// decline: (1-r)*1000)` 再交給 [calculate]，也就是**當作排除持平的比例**
  /// 在用；而唯一的來源 `market_overview_provider` 的 `historyTrends
  /// .advanceRatio` 算的是 `advance / (advance + decline + unchanged)`
  /// ——**含持平**。於是歷史的 advanceRatio 子指標會比現況儀表系統性偏低約
  /// 11.8 分（子指標權重 0.35 → 五項齊備時綜合分數差約 4.1 分）。
  ///
  /// 為什麼不順手改來源：同一個序列還餵給 `AdvanceDeclineGauge` 的
  /// sparkline，而那裡「含持平」才與它自己的漲/平/跌三段堆疊條一致——
  /// 門檻判定與顯示需要不同口徑（`MarketReadingService` 也是這樣分的）。
  /// 真要修就得拆成兩條序列，而本函式的輸出**目前不渲染**
  /// （`SentimentGaugeSection.sentimentHistory` 的 dartdoc 記載視覺 pass
  /// 已移除趨勢 sparkline），為零收益付兩條序列的代價不值得。
  ///
  /// 🚧 **若要重新啟用 sparkline，先修這個口徑**。
  ///
  /// 利用 30 日歷史資料回溯計算每日情緒分數。
  /// 歷史日缺少 industries（權重 10%），已有指標的權重會自動正規化，
  /// 趨勢形狀仍正確。
  ///
  /// **依日期 inner-join 對齊**：四個輸入序列來自不同 coverage 的來源
  /// （漲跌比/成交額經完整日 filter；法人/融資餘額為未 filter 的完整每日），
  /// 日期集不同。若按 array index 直接拼接，「index i」會把不同交易日的資料
  /// 混在同一筆情緒分數裡。故先取四序列共同日期、依時序排序後再逐日計分，
  /// 確保每筆分數的四項輸入皆來自同一交易日。
  ///
  /// 所有 history 參數為 oldest→newest（內部會自行依日期重排，不依賴傳入順序）。
  static List<double> calculateHistoricalScores({
    required List<DatedValue> advanceRatioHistory,
    required List<DatedValue> institutionalNetHistory,
    required List<DatedValue> turnoverHistory,
    required List<DatedValue> marginBalanceHistory,
  }) {
    // 依日期 inner-join：僅保留四序列皆存在的日期，並依時序（oldest→newest）排序。
    final aligned = _innerJoinByDate([
      advanceRatioHistory,
      institutionalNetHistory,
      turnoverHistory,
      marginBalanceHistory,
    ]);

    // Z-score 至少需要 5 天資料
    if (aligned.length < _kMinHistoricalDays) return [];

    final advanceRatio = aligned.map((row) => row[0]).toList();
    final institutional = aligned.map((row) => row[1]).toList();
    final turnover = aligned.map((row) => row[2]).toList();
    final marginBalance = aligned.map((row) => row[3]).toList();

    final scores = <double>[];

    for (int i = _kMinHistoricalDays - 1; i < aligned.length; i++) {
      final ratio = advanceRatio[i].clamp(0.0, 1.0);
      final syntheticAd = AdvanceDecline(
        advance: (ratio * 1000).round(),
        decline: ((1 - ratio) * 1000).round(),
      );

      final result = calculate(
        advanceDecline: syntheticAd,
        institutionalNetHistory: institutional.sublist(0, i + 1),
        turnoverHistory: turnover.sublist(0, i + 1),
        marginBalanceHistory: marginBalance.sublist(0, i + 1),
      );

      scores.add(result.score);
    }

    return scores;
  }

  /// 將多個帶日期序列依日期 inner-join，回傳依日期升序排列的對齊值列表。
  ///
  /// 回傳的每一筆 `row` 為 `List<double>`，順序對應傳入的 [series] 順序
  /// （`row[k]` 即第 k 個序列在該日期的值）。僅保留所有序列皆存在的日期。
  static List<List<double>> _innerJoinByDate(List<List<DatedValue>> series) {
    if (series.isEmpty) return const [];

    // 每個序列各自建 date(正規化到日) → value 索引，便於 O(1) 查找。
    final maps = series
        .map((s) => {for (final p in s) _dateKey(p.date): p.value})
        .toList();

    // 共同日期 = 第一個序列的鍵交集其餘序列。
    final commonKeys =
        maps.first.keys
            .where((k) => maps.every((m) => m.containsKey(k)))
            .toList()
          ..sort();

    return [
      for (final k in commonKeys) [for (final m in maps) m[k]!],
    ];
  }

  /// 將 [DateTime] 正規化為「當日」整數鍵（忽略時分秒），供日期對齊比對。
  static int _dateKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// 線性映射 [low, high] → [0, 100]
  static double _linearMap(double value, double low, double high) {
    if (high <= low) return 50;
    return ((value - low) / (high - low) * 100).clamp(0.0, 100.0);
  }

  /// Z-score 轉 0-100 分數
  ///
  /// 線性映射近似，均值→50，+2σ→90，-2σ→10（定義域 ±2.5σ）
  static double _zScoreToScore(List<double> values) {
    if (values.isEmpty) return 50;

    final mean = values.fold<double>(0, (s, v) => s + v) / values.length;
    final variance =
        values.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) /
        values.length;
    final std = math.sqrt(variance);

    if (std == 0) return values.last > 0 ? 75 : (values.last < 0 ? 25 : 50);

    final z = (values.last - mean) / std;
    // 線性映射: z ∈ [-2.5, 2.5] → [0, 100]
    return _linearMap(z, -2.5, 2.5);
  }

  static SentimentLevel _scoreToLevel(double score) {
    if (score < 20) return SentimentLevel.extremeFear;
    if (score < 40) return SentimentLevel.fear;
    if (score < 60) return SentimentLevel.neutral;
    if (score < 80) return SentimentLevel.greed;
    return SentimentLevel.extremeGreed;
  }
}
