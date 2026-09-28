import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/core/constants/chip_strength.dart';
import 'package:daredevil/domain/models/stock_summary.dart';

// ==================================================
// 子狀態類別
// ==================================================

/// 價格相關狀態：股票資訊、價格、歷史、分析
class StockPriceState {
  const StockPriceState({
    this.stock,
    this.latestPrice,
    this.priceHistory = const [],
    this.analysis,
  });

  final StockMasterEntry? stock;
  final DailyPriceEntry? latestPrice;
  final List<DailyPriceEntry> priceHistory;
  final DailyAnalysisEntry? analysis;

  /// 漲跌幅百分比
  ///
  /// 委託給 PriceCalculator，優先使用 API 漲跌價差，回退到歷史收盤價
  double? get priceChange {
    return PriceCalculator.calculatePriceChange(priceHistory, latestPrice);
  }

  StockPriceState copyWith({
    StockMasterEntry? stock,
    DailyPriceEntry? latestPrice,
    List<DailyPriceEntry>? priceHistory,
    DailyAnalysisEntry? analysis,
  }) {
    return StockPriceState(
      stock: stock ?? this.stock,
      latestPrice: latestPrice ?? this.latestPrice,
      priceHistory: priceHistory ?? this.priceHistory,
      analysis: analysis ?? this.analysis,
    );
  }
}

/// 基本面狀態：營收、股利、本益比、EPS、季度指標
class FundamentalsState {
  const FundamentalsState({
    this.revenueHistory = const [],
    this.dividendHistory = const [],
    this.latestPER,
    this.latestQuarterMetrics = const {},
    this.epsHistory = const [],
  });

  final List<FinMindRevenue> revenueHistory;
  final List<FinMindDividend> dividendHistory;
  final FinMindPER? latestPER;
  final Map<String, double> latestQuarterMetrics;
  final List<FinancialDataEntry> epsHistory;

  FundamentalsState copyWith({
    List<FinMindRevenue>? revenueHistory,
    List<FinMindDividend>? dividendHistory,
    FinMindPER? latestPER,
    Map<String, double>? latestQuarterMetrics,
    List<FinancialDataEntry>? epsHistory,
  }) {
    return FundamentalsState(
      revenueHistory: revenueHistory ?? this.revenueHistory,
      dividendHistory: dividendHistory ?? this.dividendHistory,
      latestPER: latestPER ?? this.latestPER,
      latestQuarterMetrics: latestQuarterMetrics ?? this.latestQuarterMetrics,
      epsHistory: epsHistory ?? this.epsHistory,
    );
  }
}

/// 籌碼分析狀態：法人進出、融資融券、當沖、持股比例等
class ChipAnalysisState {
  const ChipAnalysisState({
    this.institutionalHistory = const [],
    this.marginTradingHistory = const [],
    this.dayTradingHistory = const [],
    this.shareholdingHistory = const [],
    this.holdingDistribution = const [],
    this.insiderHistory = const [],
    this.insiderTransfers = const [],
    this.chipStrength,
  });

  final List<DailyInstitutionalEntry> institutionalHistory;
  final List<MarginTradingEntry> marginTradingHistory;
  final List<DayTradingEntry> dayTradingHistory;
  final List<ShareholdingEntry> shareholdingHistory;
  final List<HoldingDistributionEntry> holdingDistribution;
  final List<InsiderHoldingEntry> insiderHistory;
  final List<InsiderTransferEntry> insiderTransfers;
  final ChipStrengthResult? chipStrength;

  ChipAnalysisState copyWith({
    List<DailyInstitutionalEntry>? institutionalHistory,
    List<MarginTradingEntry>? marginTradingHistory,
    List<DayTradingEntry>? dayTradingHistory,
    List<ShareholdingEntry>? shareholdingHistory,
    List<HoldingDistributionEntry>? holdingDistribution,
    List<InsiderHoldingEntry>? insiderHistory,
    List<InsiderTransferEntry>? insiderTransfers,
    ChipStrengthResult? chipStrength,
  }) {
    return ChipAnalysisState(
      institutionalHistory: institutionalHistory ?? this.institutionalHistory,
      marginTradingHistory: marginTradingHistory ?? this.marginTradingHistory,
      dayTradingHistory: dayTradingHistory ?? this.dayTradingHistory,
      shareholdingHistory: shareholdingHistory ?? this.shareholdingHistory,
      holdingDistribution: holdingDistribution ?? this.holdingDistribution,
      insiderHistory: insiderHistory ?? this.insiderHistory,
      insiderTransfers: insiderTransfers ?? this.insiderTransfers,
      chipStrength: chipStrength ?? this.chipStrength,
    );
  }
}

/// 各區塊載入狀態旗標
class LoadingState {
  const LoadingState({
    this.isLoading = false,
    this.isLoadingFundamentals = false,
    this.isLoadingInsider = false,
    this.isLoadingChip = false,
  });

  final bool isLoading;
  final bool isLoadingFundamentals;
  final bool isLoadingInsider;
  final bool isLoadingChip;

  LoadingState copyWith({
    bool? isLoading,
    bool? isLoadingFundamentals,
    bool? isLoadingInsider,
    bool? isLoadingChip,
  }) {
    return LoadingState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingFundamentals:
          isLoadingFundamentals ?? this.isLoadingFundamentals,
      isLoadingInsider: isLoadingInsider ?? this.isLoadingInsider,
      isLoadingChip: isLoadingChip ?? this.isLoadingChip,
    );
  }
}

// ==================================================
// 股票詳情狀態
// ==================================================

/// 股票詳情頁面狀態
class StockDetailState {
  const StockDetailState({
    this.price = const StockPriceState(),
    this.fundamentals = const FundamentalsState(),
    this.chip = const ChipAnalysisState(),
    this.loading = const LoadingState(),
    this.isInWatchlist = false,
    this.error,
    this.fundamentalsError,
    this.chipError,
    this.insiderError,
    this.dataDate,
    this.hasDataMismatch = false,
    this.reasons = const [],
    this.aiSummary,
    this.recentNews = const [],
  });

  final StockPriceState price;
  final FundamentalsState fundamentals;
  final ChipAnalysisState chip;
  final LoadingState loading;

  // 其他直接欄位
  final bool isInWatchlist;
  final String? error;
  final String? fundamentalsError;
  final String? chipError;
  final String? insiderError;

  /// 同步後的資料日期 — 所有顯示資料應來自此日期
  final DateTime? dataDate;

  /// 價格與法人資料日期不一致時為 true
  final bool hasDataMismatch;

  final List<DailyReasonEntry> reasons;
  final StockSummary? aiSummary;
  final List<NewsItemEntry> recentNews;

  // 便捷存取 — 減少 header / tab 的鏈式存取

  double? get priceChange => price.priceChange;

  /// 頁首有可顯示的內容（股名或價格）。重載期間與重載失敗時，有內容就
  /// 保留畫面、不切成整頁 shimmer／錯誤頁（與掃描、自選、今日頁一致）。
  bool get hasContent => price.stock != null || price.latestPrice != null;
  String? get stockName => price.stock?.name;
  String? get stockMarket => price.stock?.market;
  String? get stockIndustry => price.stock?.industry;
  double? get latestClose => price.latestPrice?.close;
  StockDetailState copyWith({
    // 價格欄位
    StockMasterEntry? stock,
    DailyPriceEntry? latestPrice,
    List<DailyPriceEntry>? priceHistory,
    DailyAnalysisEntry? analysis,
    // 基本面欄位
    List<FinMindRevenue>? revenueHistory,
    List<FinMindDividend>? dividendHistory,
    FinMindPER? latestPER,
    Map<String, double>? latestQuarterMetrics,
    List<FinancialDataEntry>? epsHistory,
    // 籌碼欄位
    List<DailyInstitutionalEntry>? institutionalHistory,
    List<MarginTradingEntry>? marginTradingHistory,
    List<DayTradingEntry>? dayTradingHistory,
    List<ShareholdingEntry>? shareholdingHistory,
    List<HoldingDistributionEntry>? holdingDistribution,
    List<InsiderHoldingEntry>? insiderHistory,
    List<InsiderTransferEntry>? insiderTransfers,
    ChipStrengthResult? chipStrength,
    // 載入狀態欄位
    bool? isLoading,
    bool? isLoadingFundamentals,
    bool? isLoadingInsider,
    bool? isLoadingChip,
    // 直接欄位
    bool? isInWatchlist,
    Object? error = sentinel,
    Object? fundamentalsError = sentinel,
    Object? chipError = sentinel,
    Object? insiderError = sentinel,
    DateTime? dataDate,
    bool? hasDataMismatch,
    List<DailyReasonEntry>? reasons,
    StockSummary? aiSummary,
    List<NewsItemEntry>? recentNews,
  }) {
    // 僅在子狀態欄位有更新時才建立新物件
    final needsPriceUpdate =
        stock != null ||
        latestPrice != null ||
        priceHistory != null ||
        analysis != null;

    final needsFundamentalsUpdate =
        revenueHistory != null ||
        dividendHistory != null ||
        latestPER != null ||
        latestQuarterMetrics != null ||
        epsHistory != null;

    final needsChipUpdate =
        institutionalHistory != null ||
        marginTradingHistory != null ||
        dayTradingHistory != null ||
        shareholdingHistory != null ||
        holdingDistribution != null ||
        insiderHistory != null ||
        insiderTransfers != null ||
        chipStrength != null;

    final needsLoadingUpdate =
        isLoading != null ||
        isLoadingFundamentals != null ||
        isLoadingInsider != null ||
        isLoadingChip != null;

    return StockDetailState(
      price: needsPriceUpdate
          ? price.copyWith(
              stock: stock,
              latestPrice: latestPrice,
              priceHistory: priceHistory,
              analysis: analysis,
            )
          : price,
      fundamentals: needsFundamentalsUpdate
          ? fundamentals.copyWith(
              revenueHistory: revenueHistory,
              dividendHistory: dividendHistory,
              latestPER: latestPER,
              latestQuarterMetrics: latestQuarterMetrics,
              epsHistory: epsHistory,
            )
          : fundamentals,
      chip: needsChipUpdate
          ? chip.copyWith(
              institutionalHistory: institutionalHistory,
              marginTradingHistory: marginTradingHistory,
              dayTradingHistory: dayTradingHistory,
              shareholdingHistory: shareholdingHistory,
              holdingDistribution: holdingDistribution,
              insiderHistory: insiderHistory,
              insiderTransfers: insiderTransfers,
              chipStrength: chipStrength,
            )
          : chip,
      loading: needsLoadingUpdate
          ? loading.copyWith(
              isLoading: isLoading,
              isLoadingFundamentals: isLoadingFundamentals,
              isLoadingInsider: isLoadingInsider,
              isLoadingChip: isLoadingChip,
            )
          : loading,
      isInWatchlist: isInWatchlist ?? this.isInWatchlist,
      error: error == sentinel ? this.error : error as String?,
      fundamentalsError: fundamentalsError == sentinel
          ? this.fundamentalsError
          : fundamentalsError as String?,
      chipError: chipError == sentinel ? this.chipError : chipError as String?,
      insiderError: insiderError == sentinel
          ? this.insiderError
          : insiderError as String?,
      dataDate: dataDate ?? this.dataDate,
      hasDataMismatch: hasDataMismatch ?? this.hasDataMismatch,
      reasons: reasons ?? this.reasons,
      aiSummary: aiSummary ?? this.aiSummary,
      recentNews: recentNews ?? this.recentNews,
    );
  }
}
