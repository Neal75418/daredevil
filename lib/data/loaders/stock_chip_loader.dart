import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/core/constants/chip_strength.dart';
import 'package:daredevil/domain/services/chip_analysis_service.dart';

/// 完整籌碼資料載入結果
typedef ChipDataResult = ({
  List<DayTradingEntry> dayTrading,
  List<ShareholdingEntry> shareholding,
  List<MarginTradingEntry> marginTrading,
  List<HoldingDistributionEntry> holdingDist,
  List<InsiderHoldingEntry> insider,
  ChipStrengthResult strength,
});

/// 籌碼資料載入器
///
/// 負責從 DB 和 FinMind API 載入法人進出、融資融券、當沖、
/// 持股分布、董監持股等籌碼資料。純資料取得邏輯，不管理 UI 狀態。
class StockChipLoader {
  StockChipLoader({
    required AppDatabase db,
    required FinMindClient finMind,
    required InsiderRepository insiderRepo,
    AppClock clock = const SystemClock(),
  }) : _db = db,
       _finMind = finMind,
       _insiderRepo = insiderRepo,
       _clock = clock;

  final AppDatabase _db;
  final FinMindClient _finMind;
  final InsiderRepository _insiderRepo;
  final AppClock _clock;

  /// 從 DB 載入董監持股歷史資料
  Future<List<InsiderHoldingEntry>> loadInsiderFromDb(
    String symbol, {
    int months = 12,
  }) async {
    final history = await _insiderRepo.getInsiderHoldingHistory(
      symbol,
      months: months,
    );

    // 依日期降序排列（最新在前）
    history.sort((a, b) => b.date.compareTo(a.date));
    return history;
    // 🚨 刻意不 catch(2026-08-29 DAO 稽核 H3):消費端
    // (stock_detail_provider 的 loadInsiderData)有一個專屬的
    // `insiderError` 欄位在等這個例外,而這裡先吃掉的話 DB 故障會以
    // 「空清單」抵達——insiderError 永遠是 null,畫面顯示「沒有內部人
    // 資料」。同檔的 loadAllChipData 本來就不 catch,兩個方法原本是相反
    // 的契約而且沒有註解說明。
    // 這個值還會餵進 ChipAnalysisService 的籌碼強度分數。
  }

  /// 載入完整籌碼分析資料並計算籌碼強度
  ///
  /// 包含當沖、持股比例、融資融券（DB）、持股集中度、董監持股。
  /// [existingInstitutional] — 已載入的法人歷史（用於籌碼強度計算）
  /// [existingInsider] — 已載入的董監持股（避免重複查詢）
  Future<ChipDataResult> loadAllChipData(
    String symbol, {
    required List<DailyInstitutionalEntry> existingInstitutional,
    List<InsiderHoldingEntry> existingInsider = const [],
  }) async {
    final today = _clock.now();
    final startDate10d = today.subtract(
      const Duration(days: DataFreshness.chipTradingLookbackDays),
    );
    final startDate60d = today.subtract(
      const Duration(days: DataFreshness.chipShareholdingLookbackDays),
    );

    // 使用 Records 平行載入所有資料
    final (
      dayTrading,
      shareholding,
      marginTrading,
      holdingDist,
      insider,
    ) = await (
      _db.getDayTradingHistory(symbol, startDate: startDate10d),
      _db.getShareholdingHistory(symbol, startDate: startDate60d),
      _db.getMarginTradingHistory(symbol, startDate: startDate10d),
      _db.getLatestHoldingDistribution(symbol),
      existingInsider.isNotEmpty
          ? Future.value(existingInsider)
          : _db.getRecentInsiderHoldings(
              symbol,
              months: DataFreshness.insiderRecentMonths,
            ),
    ).wait;

    // 計算籌碼強度
    const service = ChipAnalysisService();
    final strength = service.compute(
      institutionalHistory: existingInstitutional,
      shareholdingHistory: shareholding,
      marginHistory: marginTrading,
      dayTradingHistory: dayTrading,
      holdingDistribution: holdingDist,
      insiderHistory: insider,
    );

    return (
      dayTrading: dayTrading,
      shareholding: shareholding,
      marginTrading: marginTrading,
      holdingDist: holdingDist,
      insider: insider,
      strength: strength,
    );
  }

  /// 直接從 FinMind API 取得法人資料
  ///
  /// 返回 record 包含資料與錯誤狀態，讓呼叫端能區分「API 失敗」與「真的沒資料」。
  Future<({List<DailyInstitutionalEntry> data, bool hasError})>
  fetchInstitutionalFromApi(String symbol) async {
    try {
      final today = _clock.now();
      final startDate = today.subtract(
        const Duration(days: DataFreshness.chipDataLookbackDays),
      );

      final data = await _finMind.getInstitutionalData(
        stockId: symbol,
        startDate: DateContext.formatYmd(startDate),
        endDate: DateContext.formatYmd(today),
      );

      // 轉換為 DailyInstitutionalEntry 格式
      final entries = data.map((item) {
        return DailyInstitutionalEntry(
          symbol: item.stockId,
          date: DateTime.parse(item.date),
          foreignNet: item.foreignNet,
          investmentTrustNet: item.investmentTrustNet,
          dealerNet: item.dealerNet,
        );
      }).toList();

      return (data: entries, hasError: false);
    } on RateLimitException {
      // 限流是**全域狀態**,不是這一檔的資料問題:吞掉會讓 UI 顯示
      // 「這檔沒有法人資料」,而使用者換一檔還是一樣(2026-08-29 DAO
      // 稽核 H2;同專案的 StockFundamentalsLoader 四處都是這個寫法,
      // 也是 CLAUDE.md 錯誤處理段的明文要求)。
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('StockChipLoader', '$symbol: 取得法人資料失敗', e);
      return (data: <DailyInstitutionalEntry>[], hasError: true);
    }
  }
}
