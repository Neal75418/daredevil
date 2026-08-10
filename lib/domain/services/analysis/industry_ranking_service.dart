import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/industry_ranking.dart';

/// 族群排行服務（使用者選股法則 L1 的自動化）
///
/// 由個股 20D 報酬聚合各產業動能（成員**中位數**，抗離群、與
/// `computeIndustryMomentum` 同口徑），加上外資+投信近
/// [SectorParams.rankingInstitutionalDays] 交易日合計淨買賣，輸出動能 DESC
/// 排行。純顯示/發現層、不進評分——sector tilt 因全期 IC≈0 dormant
/// （[SectorParams.tiltWeight] doc），那是評分因子的結論，不影響資訊呈現。
class IndustryRankingService {
  /// [industries] 為 null／空字串或含「ETF」字樣（`ETF`＋`上櫃ETF` 兩種標記
  /// 並存）的股票不進排行；歷史不足視窗需求（21／6 筆）的成員不計入。
  /// 成員數少於 [SectorParams.rankingMinMembers] 的產業整組略過。
  /// [window]：d20＝輪動主視角（預設）、d5＝轉折視角。
  List<IndustryRanking> rank({
    required Map<String, List<DailyPriceEntry>> priceHistories,
    required Map<String, String?> industries,
    required Map<String, String> names,
    required Map<String, List<DailyInstitutionalEntry>> institutionalHistories,
    RankingWindow window = RankingWindow.d20,
    Map<String, double>? volumeBySymbol,
    double? marketReturnPct,

    /// 取前 N 名;null = 全部。
    ///
    /// 🚨 [rankRotation] **必須傳 null**(2026-08-11 實機):它要比較兩個
    /// 窗口的名次,若兩邊都先砍成前 12,交集只剩 1 個族群——實測 20日 前 12
    /// 全是傳產、5日 前 12 全是電子,幾乎不重疊。單元測試抓不到,因為測試
    /// 資料只有 2~3 個族群、永遠碰不到上限。
    int? topN = SectorParams.rankingTopN,
  }) {
    final retOf = switch (window) {
      RankingWindow.d20 => PriceCalculator.ret20d,
      RankingWindow.d5 => PriceCalculator.ret5d,
    };

    // 產業 → 成員 (symbol, 選定視窗報酬)
    final membersByIndustry = <String, List<IndustryMember>>{};
    for (final entry in priceHistories.entries) {
      final industry = industries[entry.key];
      if (industry == null || industry.isEmpty) continue;
      if (industry.contains('ETF')) continue;
      final ret = retOf(entry.value);
      if (ret == null) continue;
      membersByIndustry
          .putIfAbsent(industry, () => [])
          .add(
            IndustryMember(
              symbol: entry.key,
              name: names[entry.key] ?? '',
              retPct: ret,
            ),
          );
    }

    // symbol → 外資+投信近 N 交易日合計
    final netBySymbol = <String, double>{};
    for (final entry in institutionalHistories.entries) {
      final sorted = List<DailyInstitutionalEntry>.from(entry.value)
        ..sort((a, b) => b.date.compareTo(a.date));
      var sum = 0.0;
      for (final e in sorted.take(SectorParams.rankingInstitutionalDays)) {
        sum += (e.foreignNet ?? 0) + (e.investmentTrustNet ?? 0);
      }
      netBySymbol[entry.key] = sum;
    }

    final rankings = <IndustryRanking>[];
    for (final entry in membersByIndustry.entries) {
      final members = entry.value;
      if (members.length < SectorParams.rankingMinMembers) continue;

      final rets = members.map((m) => m.retPct).toList()..sort();
      final mid = rets.length ~/ 2;
      final median = rets.length.isOdd
          ? rets[mid]
          : (rets[mid - 1] + rets[mid]) / 2;

      var net = 0.0;
      for (final m in members) {
        net += netBySymbol[m.symbol] ?? 0;
      }

      // 法人佔成交量比：族群內任一成員缺量就整組不算——部分成交量會讓分母
      // 偏小、比例虛高，寧可不顯示也不要給一個偏誤的數
      double? volRatio;
      if (volumeBySymbol != null) {
        var vol = 0.0;
        var complete = true;
        for (final m in members) {
          final v = volumeBySymbol[m.symbol];
          if (v == null) {
            complete = false;
            break;
          }
          vol += v;
        }
        if (complete && vol > 0) volRatio = net / vol;
      }

      final advancing = members.where((m) => m.retPct > 0).length;

      members.sort((a, b) {
        final byRet = b.retPct.compareTo(a.retPct);
        if (byRet != 0) return byRet;
        return a.symbol.compareTo(b.symbol);
      });

      rankings.add(
        IndustryRanking(
          industry: entry.key,
          momentumPct: median,
          memberCount: members.length,
          institutionalNetShares: net,
          excessPct: marketReturnPct == null ? null : median - marketReturnPct,
          institutionalVolumeRatio: volRatio,
          advancingRatio: advancing / members.length,
          topMembers: members
              .take(SectorParams.rankingTopMembersCount)
              .toList(),
        ),
      );
    }

    rankings.sort((a, b) {
      final byMomentum = b.momentumPct.compareTo(a.momentumPct);
      if (byMomentum != 0) return byMomentum;
      return a.industry.compareTo(b.industry);
    });
    return topN == null ? rankings : rankings.take(topN).toList();
  }

  /// 族群「轉向」——比較 20 日與 5 日的**排名**,而非水準值。
  ///
  /// **為什麼需要**(2026-08-11):既有 [rank] 只給單一窗口的水準值,而資金
  /// 轉向是變化率。2026-08-10 實測:半導體 20日排第 34(−13.6%)、5日排第 1
  /// (+7.2%)——單看任一窗口都看不出它正在變成主流,躍升 +33 名才是訊號。
  ///
  /// **為什麼要分類**:排名躍升在崩跌後會系統性地把「跌最深」的族群排到最
  /// 前面(它們反彈也最猛)。半導體是**跌深反彈**不是**持續強勢**,兩者對應
  /// v3.4 的結構 A 與結構 B,進場邏輯完全不同。見 [RotationCategory]。
  ///
  /// 刻意重用 [rank]:它是純函數,同一份已載入的 priceHistories 跑兩次幾乎
  /// 零成本,而且保證兩個窗口與既有排行**同口徑**(中位數、成員數門檻、
  /// ETF 排除),不會出現「轉向說第一、切到 5日 卻不是第一」的矛盾。
  List<IndustryRotation> rankRotation({
    required Map<String, List<DailyPriceEntry>> priceHistories,
    required Map<String, String?> industries,
    required Map<String, String> names,
    Map<String, List<DailyInstitutionalEntry>> institutionalHistories =
        const {},
  }) {
    // topN: null —— 必須拿**完整**排名。兩邊都砍成前 12 的話,20日 前 12
    // 全是傳產、5日 前 12 全是電子,交集只剩 1 個族群(2026-08-11 實機)。
    List<IndustryRanking> of(RankingWindow w) => rank(
      priceHistories: priceHistories,
      industries: industries,
      names: names,
      institutionalHistories: institutionalHistories,
      window: w,
      topN: null,
    );

    final r20 = of(RankingWindow.d20);
    final r5 = of(RankingWindow.d5);
    if (r20.isEmpty || r5.isEmpty) return const [];

    // rank() 已依動能由大到小排序,索引即名次
    final pos20 = <String, int>{
      for (var i = 0; i < r20.length; i++) r20[i].industry: i + 1,
    };
    final pos5 = <String, int>{
      for (var i = 0; i < r5.length; i++) r5[i].industry: i + 1,
    };
    final ret20 = {for (final e in r20) e.industry: e.momentumPct};
    final ret5 = {for (final e in r5) e.industry: e.momentumPct};
    final counts = {for (final e in r20) e.industry: e.memberCount};

    // 分位而非固定名次:族群數會隨資料完整度變動(實測 34~39),寫死
    // 「前 10 名」在族群變少時會把一半都算成強
    final n = pos20.length;
    final tier = (n * SectorParams.rotationTierFraction).ceil().clamp(1, n);

    final strongByIndustry = _strongListSymbols(priceHistories, industries);
    // 成員清單取自 20 日排行(見 IndustryRotation.topMembers 的理由)
    final membersByIndustry = {for (final e in r20) e.industry: e.topMembers};

    final out = <IndustryRotation>[];
    for (final industry in pos20.keys) {
      final a5 = pos5[industry];
      final a20 = pos20[industry];
      if (a5 == null || a20 == null) continue;
      final strong5 = a5 <= tier;
      final weak5 = a5 > n - tier;
      final strong20 = a20 <= tier;
      final weak20 = a20 > n - tier;
      final category = switch (null) {
        _ when strong5 && strong20 => RotationCategory.sustained,
        _ when strong5 && weak20 => RotationCategory.reboundFromDeep,
        _ when strong20 && weak5 => RotationCategory.cooling,
        _ => RotationCategory.neutral,
      };
      out.add(
        IndustryRotation(
          industry: industry,
          memberCount: counts[industry] ?? 0,
          rankJump: a20 - a5,
          rank5d: a5,
          rank20d: a20,
          ret5dPct: ret5[industry] ?? 0,
          ret20dPct: ret20[industry] ?? 0,
          category: category,
          strongListCount: strongByIndustry[industry]?.length ?? 0,
          topMembers: membersByIndustry[industry] ?? const [],
          strongListSymbols: strongByIndustry[industry] ?? const {},
        ),
      );
    }
    out.sort((a, b) {
      final byJump = b.rankJump.compareTo(a.rankJump);
      return byJump != 0 ? byJump : a.industry.compareTo(b.industry);
    });
    return out;
  }

  /// 各產業中通過 v3.4 強者榜「月漲 >15% ＋ 日均量 >3,000 張」的成員數。
  ///
  /// UI 用它決定卡片要不要淡化——0 檔代表點進去也沒東西可買。**不在此處
  /// 過濾掉 0 檔的族群**:躍升本身仍是市場資訊(2026-08-10 化學工業躍升
  /// +24 名但強者榜 0 檔,那個「空」正是使用者需要知道的事)。
  Map<String, Set<String>> _strongListSymbols(
    Map<String, List<DailyPriceEntry>> priceHistories,
    Map<String, String?> industries,
  ) {
    final out = <String, Set<String>>{};
    for (final entry in priceHistories.entries) {
      final industry = industries[entry.key];
      if (industry == null || industry.isEmpty) continue;
      if (industry.contains('ETF')) continue;
      final ret = PriceCalculator.ret20d(entry.value);
      if (ret == null || ret <= SectorParams.rotationStrongListRet20Pct) {
        continue;
      }
      final recent = entry.value.reversed.take(20).toList();
      if (recent.length < 20) continue;
      var sum = 0.0;
      var complete = true;
      for (final p in recent) {
        final v = p.volume;
        if (v == null) {
          complete = false;
          break;
        }
        sum += v;
      }
      if (!complete) continue;
      if (sum / 20 <= SectorParams.rotationStrongListDailyVolumeShares) {
        continue;
      }
      (out[industry] ??= <String>{}).add(entry.key);
    }
    return out;
  }
}
