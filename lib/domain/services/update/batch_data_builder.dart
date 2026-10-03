import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';

/// 批次資料轉換工具
///
/// 將 DB entry 轉換為型別安全的 DTO，供 [ScoringBatchData] 使用。
class BatchDataBuilder {
  const BatchDataBuilder._();

  /// 每檔用到還原價的規則（52 週）所需的股利情境：價格窗首日～[date] 的
  /// 除權除息完整（含價格）時帶窗內事件，否則 incomplete（見
  /// [DividendCompleteness.priceContext]）。沒有價格的代號不列入。
  static Map<String, DividendContext> buildDividendContexts({
    required Map<String, List<DailyPriceEntry>> pricesMap,
    required DividendCompleteness completeness,
    required Map<String, List<DividendDistributionEntry>> events,
    required DateTime date,
  }) => {
    for (final MapEntry(key: symbol, value: prices) in pricesMap.entries)
      if (prices.isNotEmpty)
        symbol: completeness.priceContext(
          symbol,
          from: prices.first.date,
          asOf: date,
          rows: events[symbol] ?? const [],
        ),
  };

  /// 為「當日無法人進出」的交易日補上淨額 0 的列
  ///
  /// 交易所對當日無法人進出的股票**根本不發列**（DB 實測：三法人全零的列
  /// 0 筆），每個交易日約有 100~168 檔股票有價格列卻無法人列。那些日子的
  /// 法人淨額就是 0，但連續買賣超規則的迴圈只走陣列、不比對日期，會把缺列
  /// 直接跳過、將不相鄰的兩天接成「連續」——憑空拉長 streak。
  ///
  /// 補零選在資料層而非規則迴圈，是因為迴圈內無法區分「中間的缺口」（該斷）
  /// 與「窗的邊界」（該標 truncated）：要區分就得把交易日曆塞進純函數規則，
  /// 而台股有臨時休市（颱風假），日曆猜錯會把跨越該日的 streak 全部誤斷。
  /// 補完之後窗內每個交易日都有列，歧義從源頭消失，規則一行都不用改。
  ///
  /// 判準（三種缺列語意必須分開處理，混為一談就會捏造資料）：
  /// - **該股有價格列 + 市場當日有法人資料** → 當日無進出，補 0
  /// - **該股無價格列** → 停牌，沒有交易時段，不補（streak 自然跨越）
  /// - **市場當日無任何法人資料** → 該日在同步窗外，我們一無所知，不得捏造
  ///
  /// 「市場當日是否有資料」以 [institutionalMap] 全體出現過的日期為準——只要
  /// 有任一檔在該日有列，就代表同步涵蓋該日。
  ///
  /// 窗內完全沒有法人列的股票不補：`history.isEmpty` 是規則判定「無資料」的
  /// 依據，補成一整排 0 會把「沒資料」偽裝成「法人都沒動作」。
  static Map<String, List<DailyInstitutionalEntry>> fillNoActivityDays(
    Map<String, List<DailyInstitutionalEntry>> institutionalMap,
    Map<String, List<DailyPriceEntry>> pricesMap,
  ) {
    final syncedDates = <DateTime>{
      for (final entries in institutionalMap.values)
        for (final e in entries) e.date,
    };
    if (syncedDates.isEmpty) return institutionalMap;

    var filledCount = 0;
    final result = <String, List<DailyInstitutionalEntry>>{};

    institutionalMap.forEach((symbol, entries) {
      if (entries.isEmpty) {
        result[symbol] = entries;
        return;
      }
      final have = {for (final e in entries) e.date};
      final missing = <DateTime>[
        for (final p in pricesMap[symbol] ?? const <DailyPriceEntry>[])
          if (syncedDates.contains(p.date) && !have.contains(p.date)) p.date,
      ];
      if (missing.isEmpty) {
        result[symbol] = entries;
        return;
      }
      filledCount += missing.length;
      result[symbol] = [
        ...entries,
        for (final d in missing)
          DailyInstitutionalEntry(
            symbol: symbol,
            date: d,
            foreignNet: 0,
            investmentTrustNet: 0,
            dealerNet: 0,
          ),
      ]..sort((a, b) => a.date.compareTo(b.date)); // 規則以 last 為今日
    });

    if (filledCount > 0) {
      AppLogger.info(
        'BatchDataBuilder',
        '法人無進出日補零：$filledCount 筆（涵蓋 ${syncedDates.length} 個同步日）',
      );
    }
    return result;
  }

  /// 建構外資持股 Map（含變化量計算 + 籌碼集中度）
  ///
  /// [evaluationDate] 用於新鮮度閘門：外資持股超過
  /// [InstitutionalParams.foreignShareholdingMaxStaleTradingDays] 個交易日未更新
  /// 者，ratio 與 change 一律不供給——**陳舊資料主動製造假訊號比沒資料更危險**。
  ///
  /// 閘門設在此處而非各規則內，是為了一處攔截全部消費端（外資增持/減持、
  /// 內部人規則的兩條）；若逐條補，任何新規則都會再度繞過。籌碼集中度來自
  /// 不同資料源，不受此閘門影響。
  static Map<String, ShareholdingData> buildShareholdingMap(
    Map<String, ShareholdingEntry> shareholdingEntries,
    Map<String, ShareholdingEntry> prevShareholdingEntries,
    Map<String, double> concentrationMap, {
    required DateTime evaluationDate,
    Map<String, String> symbolMarkets = const {},
  }) {
    final result = <String, ShareholdingData>{};
    final allSymbols = {...shareholdingEntries.keys, ...concentrationMap.keys};
    // 兩道門檻：變化量嚴（stale 時是捏造值）、水位寬（真實觀測、緩慢移動）
    final changeCutoff = TaiwanCalendar.subtractTradingDays(
      evaluationDate,
      InstitutionalParams.foreignShareholdingMaxStaleTradingDays,
    );
    final levelCutoff = TaiwanCalendar.subtractTradingDays(
      evaluationDate,
      InstitutionalParams.foreignShareholdingLevelMaxStaleTradingDays,
    );
    // 分市場統計：閘門會把「靜默的錯訊號」換成「靜默的無訊號」，若不揭露
    // 覆蓋退化，使用者只會覺得「上櫃外資訊號怎麼變少了」而不知原因。
    // 2026-07-25 實測：被擋的 64 檔中 53 檔是上櫃（未被 20/269 配額覆蓋）。
    final fresh = <String, int>{};
    final stale = <String, int>{};
    var staleCount = 0;

    for (final k in allSymbols) {
      final entry = shareholdingEntries[k];
      final changeStale = entry != null && entry.date.isBefore(changeCutoff);
      final levelStale = entry != null && entry.date.isBefore(levelCutoff);
      if (entry != null) {
        final market = symbolMarkets[k] ?? '?';
        final bucket = changeStale ? stale : fresh;
        bucket[market] = (bucket[market] ?? 0) + 1;
      }
      if (changeStale) staleCount++;

      // 水位走寬門檻——ForeignConcentrationWarningRule(-8) 只讀水位，
      // 與變化量同閘門會隱藏真實風險
      final currentRatio = levelStale ? null : entry?.foreignSharesRatio;
      // 變化量走嚴門檻，且水位本身過期時也不算
      final prevRatio = (changeStale || levelStale)
          ? null
          : prevShareholdingEntries[k]?.foreignSharesRatio;

      double? ratioChange;
      if (currentRatio != null && prevRatio != null) {
        ratioChange = currentRatio - prevRatio;
      }

      result[k] = ShareholdingData(
        foreignSharesRatio: currentRatio,
        foreignSharesRatioChange: ratioChange,
        concentrationRatio: concentrationMap[k],
      );
    }

    if (staleCount > 0) {
      final markets = {...fresh.keys, ...stale.keys}.toList()..sort();
      final breakdown = markets
          .map(
            (m) => '$m ${fresh[m] ?? 0}/${(fresh[m] ?? 0) + (stale[m] ?? 0)}',
          )
          .join(', ');
      AppLogger.info(
        'BatchDataBuilder',
        '外資持股新鮮度: $breakdown（新鮮/有資料；'
            '過期 $staleCount 檔早於 '
            '${changeCutoff.toIso8601String().substring(0, 10)}，'
            '多為未被上櫃配額覆蓋者，其外資訊號本輪不計分）',
      );
    }
    return result;
  }

  /// 建構董監持股狀態（含連續減持/增持判斷）
  static Future<Map<String, InsiderDataContext>> buildInsiderMap(
    Map<String, InsiderHoldingEntry> insiderEntries,
    List<String> candidates,
    InsiderRepository? insiderRepo,
  ) async {
    final insiderStatusMap = insiderRepo != null
        ? await insiderRepo.calculateInsiderStatusBatch(candidates)
        : <String, InsiderStatus>{};

    return insiderEntries.map((k, v) {
      final status = insiderStatusMap[k];
      return MapEntry(
        k,
        InsiderDataContext(
          insiderRatio: v.insiderRatio,
          pledgeRatio: v.pledgeRatio,
          hasSellingStreak: status?.hasSellingStreak ?? false,
          sellingStreakMonths: status?.sellingStreakMonths ?? 0,
          hasSignificantBuying: status?.hasSignificantBuying ?? false,
          // 單位必須是「百分點」（insiderRatio 的期間差）。曾寫成
          // `?? v.sharesChange` 回退，但 sharesChange 的單位是「股」——
          // 借來頂替會讓「增持 5 萬股」被當成「增持 50000 個百分點」，
          // 輕鬆越過 5.0 門檻並顯示「董監增持 50000.0%」。
          // 算不出來就誠實留 null，讓規則自然不觸發。
          buyingChange: status?.buyingChange,
        ),
      );
    });
  }
}
