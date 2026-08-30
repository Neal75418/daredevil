import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/domain/models/scan_models.dart';
import 'package:daredevil/domain/models/signal_names.dart';

/// 掃描畫面的純業務邏輯服務
///
/// 負責篩選、排序、資料轉換等業務邏輯，
/// 不持有狀態，不依賴 Riverpod，可獨立測試。
///
/// 注意：日期回退邏輯已移至 [IAnalysisRepository.findLatestAnalyses]，
/// 統一由 Repository 層處理日期正規化，避免重複實作與正規化遺漏。
class ScanFilterService {
  const ScanFilterService();

  // ==================================================
  // 篩選邏輯
  // ==================================================

  /// 套用全域篩選：根據 [filter] 與 [industrySymbols] 過濾分析結果
  ///
  /// 純函數，不修改輸入資料。
  List<DailyAnalysisEntry> applyFilter({
    required List<DailyAnalysisEntry> allAnalyses,
    required ScanFilter filter,
    required Map<String, List<DailyReasonEntry>> allReasons,
    Set<String>? industrySymbols,
  }) {
    if (filter == ScanFilter.all && industrySymbols == null) {
      return List.from(allAnalyses);
    }

    return allAnalyses.where((analysis) {
      // 產業篩選
      if (industrySymbols != null &&
          !industrySymbols.contains(analysis.symbol)) {
        return false;
      }

      // 規則篩選
      if (filter == ScanFilter.all) return true;

      // 須已載入詳細推薦理由
      final reasons = allReasons[analysis.symbol];
      if (reasons == null || reasons.isEmpty) return false;

      if (filter.reasonCode == null) return true;

      return reasons.any((r) => r.reasonType == filter.reasonCode);
    }).toList();
  }

  // ==================================================
  // 排序邏輯
  // ==================================================

  /// 套用全域排序：依 [sort] 對分析結果排序
  ///
  /// 就地排序（in-place），直接修改傳入的 list。
  /// [horizon] 決定排序欄位：long → scoreLong、否則 scoreShort（預設 short
  /// 保持向後相容）。
  void applySort(
    List<DailyAnalysisEntry> analyses,
    ScanSort sort, {
    Horizon horizon = Horizon.short,
    Map<String, double>? ret60,
    Map<String, double>? priceChanges,
  }) {
    double scoreOf(DailyAnalysisEntry a) =>
        horizon == Horizon.long ? a.scoreLong : a.scoreShort;
    switch (sort) {
      case ScanSort.rs60Desc:
        // 60D 相對強度 DESC（與 Mode B 同語意）：有值優先於無值、
        // 無值者以分數 DESC 再 symbol ASC tiebreak（deterministic）
        analyses.sort((a, b) {
          final ra = ret60?[a.symbol];
          final rb = ret60?[b.symbol];
          if (ra != null && rb == null) return -1;
          if (ra == null && rb != null) return 1;
          if (ra != null && rb != null) {
            final byRet = rb.compareTo(ra);
            if (byRet != 0) return byRet;
          }
          final byScore = scoreOf(b).compareTo(scoreOf(a));
          if (byScore != 0) return byScore;
          return a.symbol.compareTo(b.symbol);
        });
      case ScanSort.priceChangeDesc || ScanSort.priceChangeAsc:
        // 修復：這兩個選項原本落入 else 分支、實際仍按分數排（死選項）
        final sign = sort == ScanSort.priceChangeDesc ? -1 : 1;
        analyses.sort((a, b) {
          final ca = priceChanges?[a.symbol];
          final cb = priceChanges?[b.symbol];
          if (ca != null && cb == null) return -1;
          if (ca == null && cb != null) return 1;
          if (ca != null && cb != null) {
            final byChange = ca.compareTo(cb) * sign;
            if (byChange != 0) return byChange;
          }
          return a.symbol.compareTo(b.symbol);
        });
      // 同分以 symbol ASC 決勝（deterministic，與上面兩個分支一致）：
      // List.sort 無穩定性保證，而真實資料同分群很大——2026-08-28 的 422 檔
      // 主清單只有 63 個相異 scoreLong，其中 146 檔是雙 0 的風控可見層。
      // （那是移除候選股數門檻前的口徑；同日以新口徑重算是 534 檔 / 64 個 /
      //  182 檔同分——宇宙變寬讓同分群更大，這條決勝鍵更必要。）
      // 少了決勝鍵，desc→asc→desc 來回切會讓同分群每次落在不同位置。
      case ScanSort.scoreAsc:
        analyses.sort((a, b) {
          final byScore = scoreOf(a).compareTo(scoreOf(b));
          if (byScore != 0) return byScore;
          return a.symbol.compareTo(b.symbol);
        });
      case ScanSort.scoreDesc:
        analyses.sort((a, b) {
          final byScore = scoreOf(b).compareTo(scoreOf(a));
          if (byScore != 0) return byScore;
          return a.symbol.compareTo(b.symbol);
        });
    }
  }

  // ==================================================
  // 資料轉換邏輯
  // ==================================================

  /// 將分析結果批次轉換為 [ScanStockItem] 列表
  ///
  /// 從 [CachedDatabaseAccessor] 載入詳細資料並組裝為 UI 所需的物件。
  /// [horizon] 決定每張卡顯示的分數欄位：long → scoreLong、否則 scoreShort
  /// （預設 short 保持向後相容）。
  Future<List<ScanStockItem>> buildStockItems({
    required List<DailyAnalysisEntry> analyses,
    required DateContext dateCtx,
    required CachedDatabaseAccessor cachedDb,
    required Set<String> watchlistSymbols,
    Horizon horizon = Horizon.short,
  }) async {
    if (analyses.isEmpty) return [];

    final symbols = analyses.map((a) => a.symbol).toList();

    // Type-safe batch load using Dart 3 Records
    final data = await cachedDb.loadScanData(
      symbols: symbols,
      analysisDate: dateCtx.today,
      historyStart: dateCtx.historyStart,
    );

    // 解構 Record 欄位
    final stocksMap = data.stocks;
    final latestPricesMap = data.latestPrices;
    final reasonsMap = data.reasons;
    final priceHistoriesMap = data.priceHistories;

    // 使用工具計算漲跌幅
    final priceChanges = PriceCalculator.calculatePriceChangesBatch(
      priceHistoriesMap,
      latestPricesMap,
    );

    // 建構股票項目
    return analyses.map((analysis) {
      final latestPrice = latestPricesMap[analysis.symbol];
      final priceHistory = priceHistoriesMap[analysis.symbol];
      // 擷取最近 30 天收盤價供迷你走勢圖使用
      // priceHistory 按日期升序排列，需取最後 30 筆才是最近的資料
      List<double>? recentPrices;
      if (priceHistory != null && priceHistory.isNotEmpty) {
        final startIdx = priceHistory.length > 30
            ? priceHistory.length - 30
            : 0;
        recentPrices = priceHistory
            .sublist(startIdx)
            .map((p) => p.close)
            .whereType<double>()
            .toList();
      }
      return ScanStockItem(
        symbol: analysis.symbol,
        score: horizon == Horizon.long
            ? analysis.scoreLong
            : analysis.scoreShort,
        stockName: stocksMap[analysis.symbol]?.name,
        market: stocksMap[analysis.symbol]?.market,
        industry: stocksMap[analysis.symbol]?.industry,
        latestClose: latestPrice?.close,
        priceChange: priceChanges[analysis.symbol],
        volume: latestPrice?.volume,
        trendState: analysis.trendState,
        // MA 階段訊號前置(跌破>站回>回踩>蓄勢,2026-07-31 複審):
        // 卡片 ReasonTags 只顯示 1-2 個,預設 hardcoded 分數排序會把
        // BREAK(-8)擠出視窗——與自選頁同一排序,風控 tag 保證可見
        reasons: ((reasonsMap[analysis.symbol] ?? []).toList()
          ..sort(
            (a, b) => SignalName.maStagePriority(
              a.reasonType,
            ).compareTo(SignalName.maStagePriority(b.reasonType)),
          )),
        isInWatchlist: watchlistSymbols.contains(analysis.symbol),
        recentPrices: recentPrices,
      );
    }).toList();
  }
}
