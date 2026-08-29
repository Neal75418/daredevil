import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/industry_names.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/core/constants/rule_params_institutional.dart';
export 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/models/market_overview_models.dart';
export 'package:daredevil/domain/models/market_overview_models.dart';
import 'package:daredevil/domain/services/chip_anomaly_service.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==================================================
// 廣度趨勢純函式
// ==================================================

/// 計算 AD 騰落線（Advance-Decline Line）的累積序列。
///
/// [dailyNet] 為每日 (上漲 − 下跌) 家數，順序須為 oldest→newest。
/// 回傳同長度的累積 running sum（oldest→newest），供 sparkline 繪製。
/// 空輸入回傳空列表。
///
/// 純函式、無 IO，便於單元測試。
List<double> cumulativeAdLine(List<double> dailyNet) {
  final result = <double>[];
  var running = 0.0;
  for (final net in dailyNet) {
    running += net;
    result.add(running);
  }
  return result;
}

// ==================================================
// 大盤總覽狀態
// ==================================================

/// 大盤總覽狀態
class MarketOverviewState {
  const MarketOverviewState({
    this.indices = const [],
    this.indexStaleNames = const {},
    this.indexHistory = const {},
    this.indexStageHistory = const {},
    // 依市場分組的統計（預設空 Map）
    this.advanceDeclineByMarket = const {},
    this.institutionalByMarket = const {},
    this.marginByMarket = const {},
    this.turnoverByMarket = const {},
    this.limitUpDownByMarket = const {},
    this.turnoverComparisonByMarket = const {},
    this.warningCountsByMarket = const {},
    this.institutionalStreakByMarket = const {},
    this.industrySummaryByMarket = const {},
    this.newHighLowByMarket = const {},
    this.adLineByMarket = const {},
    this.historyTrends = const HistoryTrends(),
    this.chipAnomaliesByMarket = const {},
    this.chipAnomalyFailedDetectors = const [],
    this.failedSections = const {},
    this.isLoading = false,
    this.error,
    this.dataDate,
    this.sectionDates = const {},
    this.marginIndexChangePercent = const {},
    this.advanceDeclineStaleDates = const {},
  });

  // Section key 常數（供 sectionDates 使用）
  static const kSectionInstitutional = 'institutional';
  static const kSectionMargin = 'margin';

  final List<TwseMarketIndex> indices;

  /// 由 DB 備援補值(非即時)的指數名(靜默稽核 #3)。Hero 卡據此掛
  /// 「非即時」角標——盤中 API 掛掉時不得把昨收當即時值
  final Set<String> indexStaleNames;

  /// 指數名稱 → 近 30 日收盤值列表（供走勢圖使用）
  final Map<String, List<double>> indexHistory;

  /// 指數名稱 → 較長窗口收盤值列表（供大盤位階 MA60 計算使用）
  ///
  /// 與 [indexHistory] 分離：sparkline 維持 30 點不變，位階計算需 ≥60
  /// 個交易日才能算出 MA60，因此另載入較長窗口（見 [_loadIndexStageHistory]）。
  final Map<String, List<double>> indexStageHistory;

  /// 漲跌家數（依市場分組）
  /// Key: 'TWSE' / 'TPEx'
  final Map<String, AdvanceDecline> advanceDeclineByMarket;

  /// 漲跌家數使用 fallback（前一交易日）的市場 → 該 fallback 實際日期。
  ///
  /// 當某市場當日 per-stock 資料未釋出，[MarketOverviewNotifier._loadAdvanceDeclineByMarket]
  /// 會回退到前一交易日補值。此 map 記錄哪些市場是回退來的、實際日期為何，供 UI 在
  /// 該市場漲跌家數標示「資料非當日」，避免把舊日廣度誤讀成今日。
  /// 僅包含「有回退」的市場；當日資料正常的市場不會出現在此 map。
  final Map<String, DateTime> advanceDeclineStaleDates;

  /// 法人買賣超（依市場分組）
  /// Key: 'TWSE' / 'TPEx'
  final Map<String, InstitutionalTotals> institutionalByMarket;

  /// 融資融券（依市場分組）
  /// Key: 'TWSE' / 'TPEx'
  final Map<String, MarginTradingTotals> marginByMarket;

  /// 成交額統計（依市場分組）
  /// Key: 'TWSE' / 'TPEx'
  final Map<String, TradingTurnover> turnoverByMarket;

  /// 漲停/跌停家數（依市場分組）
  final Map<String, LimitUpDown> limitUpDownByMarket;

  /// 成交額 vs 5 日均量比較（依市場分組）
  final Map<String, TurnoverComparison> turnoverComparisonByMarket;

  /// 注意/處置股家數（依市場分組）
  final Map<String, WarningCounts> warningCountsByMarket;

  /// 法人連續買賣超天數（依市場分組）
  final Map<String, InstitutionalStreak> institutionalStreakByMarket;

  /// 產業表現（依市場分組）
  final Map<String, List<IndustrySummary>> industrySummaryByMarket;

  /// 52 週新高/新低家數（依市場分組）— 廣度趨勢
  /// Key: 'TWSE' / 'TPEx'
  final Map<String, ({int newHighs, int newLows})> newHighLowByMarket;

  /// AD 騰落線累積值（依市場分組，oldest→newest，供 sparkline）— 廣度趨勢
  /// Key: 'TWSE' / 'TPEx'
  final Map<String, List<double>> adLineByMarket;

  /// 30 日歷史趨勢資料（法人、成交量、融資融券、漲跌比）
  final HistoryTrends historyTrends;

  /// 籌碼異動摘要（依市場分組）
  final Map<String, List<ChipAnomaly>> chipAnomaliesByMarket;

  /// 籌碼異動偵測的失敗類別 key(靜默稽核 #4)——非空時儀表板掛
  /// 「N 類未偵測」註記,「今天沒異動」與「偵測壞了」不再逐 pixel 相同
  final List<String> chipAnomalyFailedDetectors;

  /// 載入失敗的區塊 key(靜默稽核 #7)。16 個 `_load*` 原本一律 catch→
  /// 空 map,失敗區塊在畫面上與「今天很平靜」逐 pixel 相同(最尖銳的是
  /// 注意/處置家數:查詢失敗與零警示同樣渲染成安靜市場)。非空時儀表板
  /// 標題掛「N 個區塊載入失敗」,情緒儀表另標子指標缺席。
  final Set<String> failedSections;

  final bool isLoading;
  final String? error;

  /// 資料日期（用於 UI 顯示「資料更新日期」）
  final DateTime? dataDate;

  /// 各區塊實際資料日期
  ///
  /// Key: section 常數（[kSectionInstitutional]、[kSectionMargin]）
  /// Value: 該區塊資料的實際日期
  /// 僅在與 [dataDate] 不同時才有意義，UI 可據此顯示差異標示。
  final Map<String, DateTime> sectionDates;

  /// **融資資料那天**的大盤漲跌幅（%），key 為市場代碼。
  ///
  /// 籌碼槓桿判讀（`MarketReadingService.interpretMarginLeverage`）是一句
  /// 因果陳述——「指數跌、融資減：去槓桿中」——兩邊必須來自同一天。
  /// 融資融券由 TWSE 約 21:00 發布，傍晚更新時常落後 1~3 天（畫面也標著
  /// 該日期），若配最新指數會讓結論反轉：2026-07-27 實測櫃買 07-24 為
  /// **-3.69%**、07-27 為 +0.12%，取後者會把「去槓桿中」講成「籌碼洗清，
  /// 相對健康」。
  ///
  /// **查不到對應日就不放進 map**（caller 據此不顯示判讀），不得回退到
  /// 最新值——那正是這個 bug 本身。
  final Map<String, double> marginIndexChangePercent;

  /// 是否有任何有效資料
  bool get hasData =>
      indices.isNotEmpty ||
      advanceDeclineByMarket.values.any((a) => a.total > 0);

  MarketOverviewState copyWith({
    List<TwseMarketIndex>? indices,
    Set<String>? indexStaleNames,
    Map<String, List<double>>? indexHistory,
    Map<String, List<double>>? indexStageHistory,
    Map<String, AdvanceDecline>? advanceDeclineByMarket,
    Map<String, InstitutionalTotals>? institutionalByMarket,
    Map<String, MarginTradingTotals>? marginByMarket,
    Map<String, TradingTurnover>? turnoverByMarket,
    Map<String, LimitUpDown>? limitUpDownByMarket,
    Map<String, TurnoverComparison>? turnoverComparisonByMarket,
    Map<String, WarningCounts>? warningCountsByMarket,
    Map<String, InstitutionalStreak>? institutionalStreakByMarket,
    Map<String, List<IndustrySummary>>? industrySummaryByMarket,
    Map<String, ({int newHighs, int newLows})>? newHighLowByMarket,
    Map<String, List<double>>? adLineByMarket,
    HistoryTrends? historyTrends,
    Map<String, List<ChipAnomaly>>? chipAnomaliesByMarket,
    List<String>? chipAnomalyFailedDetectors,
    Set<String>? failedSections,
    bool? isLoading,
    Object? error = sentinel,
    DateTime? dataDate,
    Map<String, DateTime>? sectionDates,
    Map<String, double>? marginIndexChangePercent,
    Map<String, DateTime>? advanceDeclineStaleDates,
  }) {
    return MarketOverviewState(
      indices: indices ?? this.indices,
      indexStaleNames: indexStaleNames ?? this.indexStaleNames,
      indexHistory: indexHistory ?? this.indexHistory,
      indexStageHistory: indexStageHistory ?? this.indexStageHistory,
      advanceDeclineByMarket:
          advanceDeclineByMarket ?? this.advanceDeclineByMarket,
      institutionalByMarket:
          institutionalByMarket ?? this.institutionalByMarket,
      marginByMarket: marginByMarket ?? this.marginByMarket,
      turnoverByMarket: turnoverByMarket ?? this.turnoverByMarket,
      limitUpDownByMarket: limitUpDownByMarket ?? this.limitUpDownByMarket,
      turnoverComparisonByMarket:
          turnoverComparisonByMarket ?? this.turnoverComparisonByMarket,
      warningCountsByMarket:
          warningCountsByMarket ?? this.warningCountsByMarket,
      institutionalStreakByMarket:
          institutionalStreakByMarket ?? this.institutionalStreakByMarket,
      industrySummaryByMarket:
          industrySummaryByMarket ?? this.industrySummaryByMarket,
      newHighLowByMarket: newHighLowByMarket ?? this.newHighLowByMarket,
      adLineByMarket: adLineByMarket ?? this.adLineByMarket,
      historyTrends: historyTrends ?? this.historyTrends,
      chipAnomaliesByMarket:
          chipAnomaliesByMarket ?? this.chipAnomaliesByMarket,
      chipAnomalyFailedDetectors:
          chipAnomalyFailedDetectors ?? this.chipAnomalyFailedDetectors,
      failedSections: failedSections ?? this.failedSections,
      isLoading: isLoading ?? this.isLoading,
      error: error == sentinel ? this.error : error as String?,
      dataDate: dataDate ?? this.dataDate,
      sectionDates: sectionDates ?? this.sectionDates,
      marginIndexChangePercent:
          marginIndexChangePercent ?? this.marginIndexChangePercent,
      advanceDeclineStaleDates:
          advanceDeclineStaleDates ?? this.advanceDeclineStaleDates,
    );
  }
}

// ==================================================
// 大盤總覽 Notifier
// ==================================================

/// [MarketOverviewNotifier.loadData] 三組 typed record `.wait` 的結果快照。
///
/// 分組與 loadData 的載入順序一一對應（record wait 上限 9 元素故分三組）；
/// 新增載入項時同步改這裡——型別不合編譯器直接報錯，取代舊的
/// untyped `List<Object?>` + magic-index cast。
typedef _OverviewSnapshot = (
  (
    ({List<TwseMarketIndex> data, Set<String> staleNames}),
    Map<String, List<double>>,
    ({Map<String, AdvanceDecline> data, Map<String, DateTime> staleDates}),
    ({Map<String, InstitutionalTotals> data, DateTime dataDate}),
    ({
      Map<String, MarginTradingTotals> data,
      Map<String, DateTime> dataDates,
      DateTime? dataDate,
    }),
    Map<String, TradingTurnover>,
  ),
  (
    Map<String, LimitUpDown>,
    Map<String, TurnoverComparison>,
    Map<String, WarningCounts>,
    Map<String, InstitutionalStreak>,
    Map<String, List<IndustrySummary>>,
    Map<String, List<DatedValue>>,
    Map<String, List<DatedValue>>,
  ),
  (
    Map<String, ({List<DatedValue> margin, List<double> short})>,
    Map<String, List<DatedValue>>,
    ({Map<String, List<ChipAnomaly>> byMarket, List<String> failedDetectors}),
    Map<String, List<double>>,
    Map<String, ({int newHighs, int newLows})>,
    Map<String, List<double>>,
  ),
);

class MarketOverviewNotifier extends Notifier<MarketOverviewState> {
  var _active = true;
  var _loadGeneration = 0;

  @override
  MarketOverviewState build() {
    _active = true;
    _loadGeneration++;
    ref.onDispose(() => _active = false);
    return const MarketOverviewState();
  }

  AppDatabase get _db => ref.read(databaseProvider);
  TwseClient get _twse => ref.read(twseClientProvider);
  TpexClient get _tpex => ref.read(tpexClientProvider);

  /// 載入大盤總覽資料
  ///
  /// 平行執行 API 呼叫與 DB 彙總查詢，任一失敗不影響其他。
  /// 設有總超時機制：超過 [_loadTimeoutSec] 秒後先結束 loading 顯示 DB 資料，
  /// API 資料在背景繼續載入，完成後自動更新 UI。
  ///
  /// **注意：混合日期資料**
  /// [state.dataDate] 代表 daily_price 表的最新日期，但各區塊實際資料日期
  /// 可能不同：by-market 指標會回退到 [fallbackDate]，融資融券/警示等抓各市場
  /// 最新可用資料。UI 標頭以 [dataDate] 為近似值，不代表所有區塊精確日期。
  static const _loadTimeoutSec = ApiConfig.marketOverviewLoadTimeoutSec;

  Future<void> loadData() async {
    final myGen = ++_loadGeneration;
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 取得最新資料日期
      final dataDate = await _db.getLatestDataDate() ?? DateTime.now();

      // 回退日期：前一個交易日
      // 處理開工日盤後資料未釋出、DB 重置後部分同步等情境
      final fallbackDate = TaiwanCalendar.getPreviousTradingDay(
        dataDate.subtract(const Duration(days: 1)),
      );

      // 平行載入所有資料（各 _load* 方法內部已處理錯誤）。
      // by-market 方法在主要日期無資料時會自動回退到 fallbackDate。
      //
      // 用 typed record `.wait` 分三組（record wait 上限 9 元素）取代
      // untyped Future.wait + magic-index cast——重排/插入載入項時
      // 編譯器直接報錯，不再依賴註解對齊索引。
      // 靜默稽核 #7:各 _load* 失敗時把 section key 收進同一個集合——
      // 「區塊失敗渲染成今天很平靜」與「真的平靜」自此可分。集合為
      // 本次 load 的區域變數,timeout 背景延續路徑經 closure 捕捉同一
      // 顆,無跨代污染。
      final failedSections = <String>{};
      final allTasks = (
        (
          _loadIndices(failedSections: failedSections),
          _loadIndexHistory(failedSections: failedSections),
          _loadAdvanceDeclineByMarket(
            dataDate,
            fallbackDate: fallbackDate,
            failedSections: failedSections,
          ),
          _loadInstitutionalByMarket(
            dataDate,
            fallbackDate: fallbackDate,
            failedSections: failedSections,
          ),
          _loadMarginByMarket(
            dataDate,
            fallbackDate: fallbackDate,
            failedSections: failedSections,
          ),
          _loadTurnoverByMarket(
            dataDate,
            fallbackDate: fallbackDate,
            failedSections: failedSections,
          ),
        ).wait,
        (
          _loadLimitUpDownByMarket(
            dataDate,
            fallbackDate: fallbackDate,
            failedSections: failedSections,
          ),
          _loadTurnoverComparisonByMarket(
            dataDate,
            failedSections: failedSections,
          ),
          _loadWarningCountsByMarket(failedSections: failedSections),
          _loadInstitutionalStreakByMarket(
            dataDate,
            failedSections: failedSections,
          ),
          _loadIndustrySummaryByMarket(
            dataDate,
            fallbackDate: fallbackDate,
            failedSections: failedSections,
          ),
          _loadInstitutionalHistoryByMarket(
            dataDate,
            failedSections: failedSections,
          ),
          _loadTurnoverHistoryByMarket(
            dataDate,
            failedSections: failedSections,
          ),
        ).wait,
        (
          _loadMarginHistoryByMarket(dataDate, failedSections: failedSections),
          _loadAdvanceDeclineHistoryByMarket(
            dataDate,
            failedSections: failedSections,
          ),
          _loadChipAnomalies(dataDate),
          _loadIndexStageHistory(failedSections: failedSections),
          _loadNewHighLowByMarket(
            dataDate,
            fallbackDate: fallbackDate,
            failedSections: failedSections,
          ),
          _loadAdLineByMarket(dataDate, failedSections: failedSections),
        ).wait,
      ).wait;

      // 超時機制：最多等 _loadTimeoutSec 秒
      // 超時後先結束 loading 顯示 DB 資料，API 在背景繼續載入
      _OverviewSnapshot results;
      try {
        results = await allTasks.timeout(
          const Duration(seconds: _loadTimeoutSec),
        );
      } on TimeoutException {
        AppLogger.warning(
          'MarketOverviewNotifier',
          '大盤總覽載入超過 ${_loadTimeoutSec}s，先顯示可用資料',
        );
        // 結束 loading 指示器，讓 UI 可互動
        if (_active && _loadGeneration == myGen) {
          // 傳當輪快照:不傳的話 banner 在新一輪 in-flight 期間掛著
          // **上一輪**的數字(review 2026-08-29)。此刻 loader 尚未全數
          // 完成故為部分結果——複本避免 state 持有仍在變動的集合。
          state = state.copyWith(
            isLoading: false,
            dataDate: dataDate,
            failedSections: Set.of(failedSections),
          );
        }
        // 背景繼續等待 API 回應，完成後靜默更新
        unawaited(
          allTasks
              .then((r) async {
                if (_active && _loadGeneration == myGen) {
                  final next = await _buildState(r, dataDate, failedSections);
                  if (_active && _loadGeneration == myGen) state = next;
                }
              })
              .catchError((Object e) {
                AppLogger.warning(
                  'MarketOverviewNotifier',
                  '背景載入完成但建構 state 失敗',
                  e,
                );
              }),
        );
        return;
      }

      if (!_active || _loadGeneration != myGen) return;

      // 靜默稽核 #11:_buildState 內含 DB 查詢——guard 只在 await 之前的話,
      // 較舊 generation 可在新一輪寫入後才落地覆蓋。build 完**再驗一次**
      // 才寫,與上方 timeout 背景路徑同一樣板(那條有做對,證明這裡是
      // 遺漏非設計)。
      final next = await _buildState(results, dataDate, failedSections);
      if (!_active || _loadGeneration != myGen) return;
      state = next;
    } catch (e, s) {
      // getLatestDataDate() 可能拋出例外
      AppLogger.warning('MarketOverviewNotifier', '載入大盤總覽失敗', e, s);
      if (_active) {
        state = state.copyWith(
          isLoading: false,
          error: ErrorDisplay.message(e),
        );
      }
    }
  }

  /// 從載入結果建構 state
  /// 非同步：需查融資資料當天的指數漲跌幅（見 [_loadIndexChangeOn]），
  /// 該日期要等 marginResult 回來才知道，無法併進上游的平行載入。
  Future<MarketOverviewState> _buildState(
    _OverviewSnapshot results,
    DateTime dataDate,
    Set<String> failedSections,
  ) async {
    // typed record pattern destructuring——順序/型別對不上會直接編譯錯誤
    final (
      (
        indicesResult,
        rawHistory,
        advDecResult,
        instResult,
        marginResult,
        turnoverByMarket,
      ),
      (
        limitUpDownByMarket,
        turnoverCompByMarket,
        warningCountsByMarket,
        rawStreak,
        industrySummaryByMarket,
        instHistory,
        turnoverHist,
      ),
      (
        marginHistory,
        advRatioHistory,
        chipAnomalies,
        rawStageHistory,
        newHighLowByMarket,
        adLineByMarket,
      ),
    ) = results;
    final advDecByMarket = advDecResult.data;
    final instByMarket = instResult.data;
    final marginByMarket = marginResult.data;

    // 複製歷史資料，避免原地修改導致重複追加
    final indexHistory = <String, List<double>>{
      for (final e in rawHistory.entries) e.key: List<double>.from(e.value),
    };
    final indexStageHistory = <String, List<double>>{
      for (final e in rawStageHistory.entries)
        e.key: List<double>.from(e.value),
    };

    // 將即時 API 的今日收盤價追加到歷史資料，確保走勢圖與位階反映最新資料
    for (final idx in indicesResult.data) {
      final history = indexHistory[idx.name];
      if (history != null && history.isNotEmpty) {
        // 使用 epsilon 比較避免浮點數精度問題
        if ((history.last - idx.close).abs() > 0.001) {
          history.add(idx.close);
        }
      }
      final stageHistory = indexStageHistory[idx.name];
      if (stageHistory != null && stageHistory.isNotEmpty) {
        if ((stageHistory.last - idx.close).abs() > 0.001) {
          stageHistory.add(idx.close);
        }
      }
    }

    // Streak 來自 DB（per-stock 聚合），顯示金額來自 API（市場總計）。
    // 兩者資料來源不同，方向可能矛盾（API 含大宗交易等 per-stock 未涵蓋的項目）。
    // 當 streak 方向與 API 值矛盾時，重置為 ±1（不會顯示 badge，因門檻 ≥ 2）。
    final validatedStreak = _validateStreakConsistency(rawStreak, instByMarket);

    // 建構各區塊實際資料日期（僅在與 dataDate 不同時加入）
    final sectionDates = <String, DateTime>{};

    // 法人日期
    if (_isDifferentDay(instResult.dataDate, dataDate)) {
      sectionDates[MarketOverviewState.kSectionInstitutional] =
          instResult.dataDate;
    }

    // 融資融券日期
    final marginDate = marginResult.dataDate;
    if (marginDate != null && _isDifferentDay(marginDate, dataDate)) {
      sectionDates[MarketOverviewState.kSectionMargin] = marginDate;
    }

    // 籌碼槓桿判讀必須拿**融資那天**的指數，不能拿最新的（見
    // [MarketOverviewState.marginIndexChangePercent] 的說明）。
    final marginIndexChange = await _loadIndexChangeOn(
      marginResult.dataDates,
      failedSections: failedSections,
    );

    return MarketOverviewState(
      indices: indicesResult.data,
      indexStaleNames: indicesResult.staleNames,
      indexHistory: indexHistory,
      indexStageHistory: indexStageHistory,
      marginIndexChangePercent: marginIndexChange,
      advanceDeclineByMarket: advDecByMarket,
      advanceDeclineStaleDates: advDecResult.staleDates,
      institutionalByMarket: instByMarket,
      marginByMarket: marginByMarket,
      turnoverByMarket: turnoverByMarket,
      limitUpDownByMarket: limitUpDownByMarket,
      turnoverComparisonByMarket: turnoverCompByMarket,
      warningCountsByMarket: warningCountsByMarket,
      institutionalStreakByMarket: validatedStreak,
      industrySummaryByMarket: industrySummaryByMarket,
      newHighLowByMarket: newHighLowByMarket,
      adLineByMarket: adLineByMarket,
      historyTrends: HistoryTrends(
        institutionalTotalNet: instHistory,
        turnover: turnoverHist,
        marginBalance: {
          for (final e in marginHistory.entries) e.key: e.value.margin,
        },
        shortBalance: {
          for (final e in marginHistory.entries) e.key: e.value.short,
        },
        advanceRatio: advRatioHistory,
      ),
      chipAnomaliesByMarket: chipAnomalies.byMarket,
      chipAnomalyFailedDetectors: chipAnomalies.failedDetectors,
      failedSections: Set.unmodifiable(failedSections),
      dataDate: dataDate,
      sectionDates: sectionDates,
    );
  }

  /// 驗證 streak 方向與 API 顯示值的一致性
  ///
  /// Streak 資料來自 DB（per-stock 聚合），顯示金額來自 API（市場總計）。
  /// 當兩者方向矛盾時（例如 DB 顯示買超但 API 顯示賣超），
  /// 重置該法人的 streak 為 ±1，避免 UI 出現「連N日買超」但金額為負的矛盾。
  static Map<String, InstitutionalStreak> _validateStreakConsistency(
    Map<String, InstitutionalStreak> streaks,
    Map<String, InstitutionalTotals> totals,
  ) {
    final result = <String, InstitutionalStreak>{};
    for (final market in streaks.keys) {
      final streak = streaks[market]!;
      final inst = totals[market];
      if (inst == null) {
        result[market] = streak;
        continue;
      }
      result[market] = InstitutionalStreak(
        foreignStreak: _alignStreak(streak.foreignStreak, inst.foreignNet),
        trustStreak: _alignStreak(streak.trustStreak, inst.trustNet),
        // 自營 streak 由 dealer_self_net（自行買賣）算、顯示金額為含避險「合計」
        // (inst.dealerNet)。兩者因避險部位可能反號，若不對齊，badge 會出現「連N日
        // 買超」卻顯示負值的矛盾（散戶誤讀）。故與外資/投信一致對齊：方向不符即
        // 重置 ±1（|streak|<2 → badge 隱藏），只在 streak 與顯示金額同向時才呈現。
        dealerStreak: _alignStreak(streak.dealerStreak, inst.dealerNet),
      );
    }
    return result;
  }

  /// 判斷兩個日期是否為不同日（忽略時分秒）
  static bool _isDifferentDay(DateTime a, DateTime b) {
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  /// 若 streak 方向與 API 值矛盾，重置為 ±1（badge 門檻 ≥ 2，不會顯示）
  static int _alignStreak(int streak, double apiValue) {
    if (streak == 0 || apiValue == 0) return 0;
    final streakPositive = streak > 0;
    final apiPositive = apiValue > 0;
    if (streakPositive == apiPositive) return streak;
    // 方向矛盾：今日可能翻轉，重置為 day-1
    return apiPositive ? 1 : -1;
  }

  /// 載入大盤指數。staleNames = 由 DB 備援補的指數名(靜默稽核 #3):
  /// 盤中 API 掛掉時 Hero 卡原本把**昨收**當即時值顯示、混合失敗時同畫面
  /// 一半今天一半昨天——同檔的 advanceDeclineStaleDates 早就對漲跌家數做
  /// 了回退標記,指數這條漏掉,防護不對稱。
  Future<({List<TwseMarketIndex> data, Set<String> staleNames})> _loadIndices({
    required Set<String> failedSections,
  }) async {
    try {
      // 獨立呼叫 TWSE 和 TPEx API，避免一方失敗拖垮另一方
      List<TwseMarketIndex> twseIndices = [];
      List<TwseMarketIndex> tpexIndices = [];

      try {
        twseIndices = await _twse.getMarketIndices();
      } catch (e) {
        AppLogger.warning('MarketOverviewNotifier', '載入 TWSE 指數失敗', e);
      }

      try {
        tpexIndices = await _tpex.getTpexIndex();
      } catch (e) {
        AppLogger.warning('MarketOverviewNotifier', '載入 TPEx 指數失敗', e);
      }

      // API 全部失敗時，從 DB 取最新指數作為備援——全部標 stale
      if (twseIndices.isEmpty && tpexIndices.isEmpty) {
        final dbIndices = await _loadIndicesFromDb();
        // DB 備援也空 → staleNames 為空、error 未設、指數卡整張消失:
        // 三條揭露管道同時靜默(2026-08-29 review 實測)。補進
        // failedSections 讓標題 banner 至少說得出來。
        if (dbIndices.isEmpty) failedSections.add('indices');
        return (
          data: dbIndices,
          staleNames: {for (final i in dbIndices) i.name},
        );
      }

      // 精確名稱匹配，僅保留 Dashboard 需要的 TWSE 重點指數
      final targetNames = MarketIndexNames.dashboardIndices.toSet();
      final filtered = twseIndices
          .where((idx) => targetNames.contains(idx.name))
          .toList();

      // 需要從 DB 補資料時，只查一次（lazy cache）
      List<TwseMarketIndex>? dbCache;
      Future<List<TwseMarketIndex>> getDbCache() async =>
          dbCache ??= await _loadIndicesFromDb();

      final staleNames = <String>{};
      // TWSE API 失敗但 TPEx 成功時，從 DB 補 TWSE 指數
      if (filtered.isEmpty) {
        final dbIndices = await getDbCache();
        final patched = dbIndices
            .where((idx) => targetNames.contains(idx.name))
            .toList();
        filtered.addAll(patched);
        staleNames.addAll(patched.map((i) => i.name));
      }

      // 加入 TPEx 櫃買指數（取最新一筆作為即時資料）
      if (tpexIndices.isNotEmpty) {
        filtered.add(tpexIndices.last);
      } else {
        // TPEx API 失敗時，從 DB 補櫃買指數
        final dbIndices = await getDbCache();
        final dbTpex = dbIndices
            .where((idx) => idx.name == MarketIndexNames.tpexIndex)
            .toList();
        if (dbTpex.isNotEmpty) {
          filtered.add(dbTpex.last);
          staleNames.add(dbTpex.last.name);
        }
      }

      if (filtered.isEmpty) failedSections.add('indices');
      return (data: filtered, staleNames: staleNames);
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入大盤指數失敗', e);
      final dbIndices = await _loadIndicesFromDb();
      if (dbIndices.isEmpty) failedSections.add('indices');
      return (data: dbIndices, staleNames: {for (final i in dbIndices) i.name});
    }
  }

  /// 取 [date] 當天各市場大盤的漲跌幅（%），供籌碼槓桿判讀使用。
  ///
  /// **查不到該日就不放進回傳 map**——caller 會因此不顯示判讀行。刻意不回退
  /// 到最新值：融資融券常落後 1~3 天，用最新指數配舊融資會讓因果陳述反轉
  /// （2026-07-27 實測櫃買 07-24 為 -3.69%、07-27 為 +0.12%，取後者會把
  /// 「去槓桿中」講成「籌碼洗清，相對健康」）。
  Future<Map<String, double>> _loadIndexChangeOn(
    Map<String, DateTime> datesByMarket, {
    required Set<String> failedSections,
  }) async {
    if (datesByMarket.isEmpty) return const {};
    try {
      final byMarket = <String, String>{
        MarketCode.twse: MarketIndexNames.taiex,
        MarketCode.tpex: MarketIndexNames.tpexIndex,
      };
      final history = await _db.getIndexHistoryBatch(
        byMarket.values.toList(),
        days: 30,
      );
      final result = <String, double>{};
      for (final entry in byMarket.entries) {
        // 逐市場用**自己的**融資日配對(2026-08-01 複審)
        final date = datesByMarket[entry.key];
        if (date == null) continue;
        final rows = history[entry.value];
        if (rows == null) continue;
        for (final row in rows) {
          if (!_isDifferentDay(row.date, date)) {
            result[entry.key] = row.changePercent;
            break;
          }
        }
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入融資日指數漲跌失敗', e);
      failedSections.add('indexChangeOn');
      return const {};
    }
  }

  /// 從 DB 載入最新指數值（API 失敗時的備援）
  Future<List<TwseMarketIndex>> _loadIndicesFromDb() async {
    try {
      final indexNames = [
        ...MarketIndexNames.dashboardIndices,
        MarketIndexNames.tpexIndex,
        MarketIndexNames.totalReturnIndex,
      ];
      final historyMap = await _db.getIndexHistoryBatch(indexNames, days: 5);

      // 取每個指數的最新一筆
      return historyMap.entries.where((e) => e.value.isNotEmpty).map((e) {
        final latest = e.value.last;
        return TwseMarketIndex(
          date: latest.date,
          name: latest.name,
          close: latest.close,
          change: latest.change,
          changePercent: latest.changePercent,
        );
      }).toList();
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入 DB 指數備援失敗', e);
      return [];
    }
  }

  /// 從 DB 載入近 30 日指數歷史（供走勢圖使用）
  Future<Map<String, List<double>>> _loadIndexHistory({
    required Set<String> failedSections,
  }) async {
    try {
      // 查詢 TWSE 重點指數 + TPEx 櫃買指數的歷史
      final indexNames = [
        ...MarketIndexNames.dashboardIndices,
        MarketIndexNames.tpexIndex,
        MarketIndexNames.totalReturnIndex,
      ];

      final historyMap = await _db.getIndexHistoryBatch(indexNames, days: 30);

      // 轉換為 name → close 值列表
      final result = <String, List<double>>{};
      for (final entry in historyMap.entries) {
        result[entry.key] = entry.value.map((e) => e.close).toList();
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入指數歷史失敗', e);
      failedSections.add('indexHistory');
      return {};
    }
  }

  /// 從 DB 載入較長窗口的指數歷史（供大盤位階 MA60 計算）
  ///
  /// 與 [_loadIndexHistory]（30 點走勢圖）分離：位階需 ≥60 個交易日才能算
  /// MA60，因此使用 [DataFreshness.marketStageHistoryLookbackDays] 較長窗口，
  /// 僅查 Hero 指數（加權指數 + 櫃買指數）以避免拉長其他 sparkline。
  Future<Map<String, List<double>>> _loadIndexStageHistory({
    required Set<String> failedSections,
  }) async {
    try {
      final indexNames = [MarketIndexNames.taiex, MarketIndexNames.tpexIndex];

      final historyMap = await _db.getIndexHistoryBatch(
        indexNames,
        days: DataFreshness.marketStageHistoryLookbackDays,
      );

      final result = <String, List<double>>{};
      for (final entry in historyMap.entries) {
        result[entry.key] = entry.value.map((e) => e.close).toList();
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入指數位階歷史失敗', e);
      failedSections.add('indexStageHistory');
      return {};
    }
  }

  /// 載入漲跌家數（依市場分組）
  ///
  /// 若主要日期缺少某市場資料，自動用 [fallbackDate] 補齊。
  /// 回傳 [staleDates]：記錄哪些市場是回退來的（market → fallbackDate），供 UI 標示
  /// 「資料非當日」，避免把舊日廣度誤讀成今日。當日資料正常的市場不會出現在內。
  Future<({Map<String, AdvanceDecline> data, Map<String, DateTime> staleDates})>
  _loadAdvanceDeclineByMarket(
    DateTime date, {
    DateTime? fallbackDate,
    required Set<String> failedSections,
  }) async {
    final staleDates = <String, DateTime>{};
    try {
      final data = await _db.getAdvanceDeclineCountsByMarket(date);

      // 回退：若缺少某市場，嘗試前一交易日補齊（並記錄該市場為回退來源）
      if (fallbackDate != null && data.length < 2) {
        final fallbackData = await _db.getAdvanceDeclineCountsByMarket(
          fallbackDate,
        );
        for (final entry in fallbackData.entries) {
          if (!data.containsKey(entry.key)) {
            data[entry.key] = entry.value;
            staleDates[entry.key] = fallbackDate;
          }
        }
      }

      return (
        data: {
          for (final entry in data.entries)
            entry.key: AdvanceDecline(
              advance: entry.value.advance,
              decline: entry.value.decline,
              unchanged: entry.value.unchanged,
            ),
        },
        staleDates: staleDates,
      );
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入分市場漲跌家數失敗', e);
      failedSections.add('advanceDecline');
      return (data: <String, AdvanceDecline>{}, staleDates: staleDates);
    }
  }

  /// 載入法人買賣超金額（依市場分組）
  ///
  /// 使用 TWSE/TPEX 的法人買賣金額統計 API，直接取得市場總計金額（元）。
  /// TWSE 和 TPEX 獨立呼叫，避免一方失敗拖垮另一方。
  /// 若主要日期的 API 回傳 null，自動用 [fallbackDate] 重試。
  /// 回傳法人買賣超資料 + 實際使用的日期
  ///
  /// 若主日期有資料則 [dataDate] 為 [date]，
  /// 若任一市場回退到 [fallbackDate]，則以 fallbackDate 為代表日期。
  Future<({Map<String, InstitutionalTotals> data, DateTime dataDate})>
  _loadInstitutionalByMarket(
    DateTime date, {
    DateTime? fallbackDate,
    required Set<String> failedSections,
  }) async {
    var usedFallback = false;

    // 平行呼叫 TWSE 和 TPEX API，各自獨立 catch 避免互相拖垮
    final results = await Future.wait([
      () async {
        try {
          var data = await _twse.getInstitutionalAmounts(date: date);
          if (data == null && fallbackDate != null) {
            data = await _twse.getInstitutionalAmounts(date: fallbackDate);
            if (data != null) usedFallback = true;
          }
          return data != null
              ? MapEntry(
                  MarketCode.twse,
                  InstitutionalTotals(
                    foreignNet: data.foreignNet,
                    trustNet: data.trustNet,
                    dealerNet: data.dealerNet,
                    totalNet: data.totalNet,
                  ),
                )
              : null;
        } catch (e) {
          AppLogger.warning('MarketOverviewNotifier', '載入 TWSE 法人總額失敗', e);
          failedSections.add('institutional');
          return null;
        }
      }(),
      () async {
        try {
          var data = await _tpex.getInstitutionalAmounts(date: date);
          if (data == null && fallbackDate != null) {
            data = await _tpex.getInstitutionalAmounts(date: fallbackDate);
            if (data != null) usedFallback = true;
          }
          return data != null
              ? MapEntry(
                  MarketCode.tpex,
                  InstitutionalTotals(
                    foreignNet: data.foreignNet,
                    trustNet: data.trustNet,
                    dealerNet: data.dealerNet,
                    totalNet: data.totalNet,
                  ),
                )
              : null;
        } catch (e) {
          AppLogger.warning('MarketOverviewNotifier', '載入 TPEx 法人總額失敗', e);
          failedSections.add('institutional');
          return null;
        }
      }(),
    ]);

    return (
      data: {
        for (final entry in results)
          if (entry != null) entry.key: entry.value,
      },
      dataDate: usedFallback && fallbackDate != null ? fallbackDate : date,
    );
  }

  /// 載入融資融券（依市場分組）
  ///
  /// 融資融券資料日期可能與 daily_price 不同步（TPEx 有 T+1 延遲），
  /// 因此直接使用 [getLatestMarginTradingTotalsByMarket] 取得各市場最新資料，
  /// 不依賴 daily_price 的日期。
  /// 回傳融資融券資料 + per-market 資料日期 + 代表日期(各市場最早,僅供
  /// sectionDates 顯示)。
  ///
  /// **per-market 日期(2026-08-01 複審 Critical)**:TWSE/TPEx 融資日常態
  /// 不同步(TPEx T+1),初版把兩者壓成單一 earliest scalar 給指數配對用,
  /// TWSE 一側被迫用 TPEx 的舊日期配自己的融資值——要修的日期錯配換個
  /// 市場重現。指數配對必須逐市場用**自己的**融資日。
  Future<
    ({
      Map<String, MarginTradingTotals> data,
      Map<String, DateTime> dataDates,
      DateTime? dataDate,
    })
  >
  _loadMarginByMarket(
    DateTime date, {
    DateTime? fallbackDate,
    required Set<String> failedSections,
  }) async {
    try {
      // 直接查詢各市場最新融資融券資料，避免日期不同步問題
      final raw = await _db.getLatestMarginTradingTotalsByMarket();

      DateTime? earliestDate;
      final result = <String, MarginTradingTotals>{};
      final dates = <String, DateTime>{};
      for (final entry in raw.entries) {
        result[entry.key] = MarginTradingTotals(
          marginBalance: entry.value.marginBalance,
          marginChange: entry.value.marginChange,
          shortBalance: entry.value.shortBalance,
          shortChange: entry.value.shortChange,
        );
        final d = entry.value.dataDate;
        if (d != null) {
          dates[entry.key] = d;
          if (earliestDate == null || d.isBefore(earliestDate)) {
            earliestDate = d;
          }
        }
      }

      return (data: result, dataDates: dates, dataDate: earliestDate);
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入分市場融資融券總額失敗', e);
      failedSections.add('margin');
      return (
        data: <String, MarginTradingTotals>{},
        dataDates: <String, DateTime>{},
        dataDate: null,
      );
    }
  }

  /// 載入成交額統計（依市場分組）
  ///
  /// 若主要日期缺少某市場資料，自動用 [fallbackDate] 補齊。
  Future<Map<String, TradingTurnover>> _loadTurnoverByMarket(
    DateTime date, {
    DateTime? fallbackDate,
    required Set<String> failedSections,
  }) async {
    try {
      final data = await _db.getTurnoverSummaryByMarket(date);

      // 回退：若缺少某市場，嘗試前一交易日補齊
      if (fallbackDate != null && data.length < 2) {
        final fallbackData = await _db.getTurnoverSummaryByMarket(fallbackDate);
        for (final entry in fallbackData.entries) {
          data.putIfAbsent(entry.key, () => entry.value);
        }
      }

      return {
        for (final entry in data.entries)
          entry.key: TradingTurnover(totalTurnover: entry.value.totalTurnover),
      };
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入分市場成交額失敗', e);
      failedSections.add('turnover');
      return {};
    }
  }

  /// 載入漲停/跌停家數（依市場分組）
  Future<Map<String, LimitUpDown>> _loadLimitUpDownByMarket(
    DateTime date, {
    DateTime? fallbackDate,
    required Set<String> failedSections,
  }) async {
    try {
      final data = await _db.getLimitUpDownCountsByMarket(date);

      if (fallbackDate != null && data.length < 2) {
        final fallbackData = await _db.getLimitUpDownCountsByMarket(
          fallbackDate,
        );
        for (final entry in fallbackData.entries) {
          data.putIfAbsent(entry.key, () => entry.value);
        }
      }

      return {
        for (final entry in data.entries)
          entry.key: LimitUpDown(
            limitUp: entry.value.limitUp,
            limitDown: entry.value.limitDown,
          ),
      };
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入漲停跌停家數失敗', e);
      failedSections.add('limitUpDown');
      return {};
    }
  }

  /// 載入成交額 vs 5 日均量比較（依市場分組）
  Future<Map<String, TurnoverComparison>> _loadTurnoverComparisonByMarket(
    DateTime date, {
    required Set<String> failedSections,
  }) async {
    try {
      final data = await _db.getRecentTurnoverByMarket(date, days: 5);
      final result = <String, TurnoverComparison>{};

      for (final entry in data.entries) {
        final list = entry.value;
        if (list.length < 2) continue; // 至少要有今日 + 1 天歷史

        final todayTurnover = list.first.turnover;
        // 前 5 天平均（跳過第一筆今日資料）
        final historyDays = list.skip(1).take(5).toList();
        if (historyDays.isEmpty) continue;

        final avg5d =
            historyDays.fold<double>(0, (sum, e) => sum + e.turnover) /
            historyDays.length;

        result[entry.key] = TurnoverComparison(
          todayTurnover: todayTurnover,
          avg5dTurnover: avg5d,
        );
      }

      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入成交額均量比較失敗', e);
      failedSections.add('turnoverComparison');
      return {};
    }
  }

  /// 載入注意/處置股家數（依市場分組）
  Future<Map<String, WarningCounts>> _loadWarningCountsByMarket({
    required Set<String> failedSections,
  }) async {
    try {
      final data = await _db.getActiveWarningCountsByMarket();

      return {
        for (final entry in data.entries)
          entry.key: WarningCounts(
            attention: entry.value['ATTENTION'] ?? 0,
            disposal: entry.value['DISPOSAL'] ?? 0,
          ),
      };
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入注意處置股家數失敗', e);
      failedSections.add('warningCounts');
      return {};
    }
  }

  /// 載入法人連續買賣超天數（依市場分組）
  Future<Map<String, InstitutionalStreak>> _loadInstitutionalStreakByMarket(
    DateTime date, {
    required Set<String> failedSections,
  }) async {
    try {
      final data = await _db.getRecentInstitutionalDailyByMarket(
        date,
        days: InstitutionalParams.kStreakLookbackDays,
      );
      final result = <String, InstitutionalStreak>{};

      for (final entry in data.entries) {
        final dailyList = entry.value;
        if (dailyList.isEmpty) continue;

        result[entry.key] = InstitutionalStreak(
          foreignStreak: _calculateStreak(
            dailyList.map((e) => e.foreignNet).toList(),
          ),
          trustStreak: _calculateStreak(
            dailyList.map((e) => e.trustNet).toList(),
          ),
          // 自營 streak 改用「自行買賣」淨額（不含避險，反映真實主動方向）。
          // dealerSelfNet 為 nullable：重新同步前的歷史日為 NULL。
          dealerStreak: _calculateNullableStreak(
            dailyList.map((e) => e.dealerSelfNet).toList(),
          ),
        );
      }

      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入法人連續買賣超失敗', e);
      failedSections.add('institutionalStreak');
      return {};
    }
  }

  /// 計算連續同方向天數（純函式）
  ///
  /// [values] 按日期降序（最新在前）
  /// 回傳：正數 = 連續買超天數，負數 = 連續賣超天數，0 = 最新一天為零
  static int _calculateStreak(List<double> values) {
    if (values.isEmpty) return 0;

    final first = values.first;
    if (first == 0) return 0;

    final isPositive = first > 0;
    int count = 0;
    for (final v in values) {
      if ((isPositive && v > 0) || (!isPositive && v < 0)) {
        count++;
      } else {
        break;
      }
    }

    return isPositive ? count : -count;
  }

  /// 計算連續同方向天數，容忍 null（純函式）
  ///
  /// [values] 按日期降序（最新在前）。null 代表該日無「自行買賣」資料
  /// （重新同步前累積的歷史 row，dealer_self_net 全 NULL → 聚合後仍 NULL）。
  ///
  /// 規則：
  /// - 最新一天為 null（或空輸入）→ 回 0：badge 隱藏（門檻 ≥ 2），避免在
  ///   尚未重新同步的舊資料上顯示誤導性 streak。
  /// - 中段遇到 null → 中斷 streak（**不**視為 0/正負，直接 break）。
  static int _calculateNullableStreak(List<double?> values) {
    if (values.isEmpty) return 0;

    final first = values.first;
    // 最新一天無自行買賣資料 → 隱藏 badge
    if (first == null || first == 0) return 0;

    final isPositive = first > 0;
    int count = 0;
    for (final v in values) {
      // 中段 null 中斷 streak（既非同方向亦非反方向，保守 break）
      if (v == null) break;
      if ((isPositive && v > 0) || (!isPositive && v < 0)) {
        count++;
      } else {
        break;
      }
    }

    return isPositive ? count : -count;
  }

  /// 載入法人合計淨額 30 日歷史（供趨勢 bar chart + 情緒對齊）
  ///
  /// 複用既有 [getRecentInstitutionalDailyByMarket]，
  /// 提取 totalNet (foreign+trust+dealer)、保留日期並反轉為 oldest→newest。
  /// 保留日期供 [MarketSentimentService.calculateHistoricalScores] 依日期對齊。
  Future<Map<String, List<DatedValue>>> _loadInstitutionalHistoryByMarket(
    DateTime date, {
    required Set<String> failedSections,
  }) async {
    try {
      final raw = await _db.getRecentInstitutionalDailyByMarket(date);
      final result = <String, List<DatedValue>>{};
      for (final entry in raw.entries) {
        // ⚠️ 防呆：三大法人合計用 dealerNet（含避險合計），對齊 TWSE 官方口徑、
        // 餵情緒法人 Z-score。**勿改成 dealerSelfNet** —— 那是自營主動方向 streak
        // 的不同口徑（見 _validateStreakConsistency 對自營不跨源對齊的註解）。
        result[entry.key] = entry.value.reversed
            .map<DatedValue>(
              (e) => (
                date: e.date,
                value: e.foreignNet + e.trustNet + e.dealerNet,
              ),
            )
            .toList();
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入法人歷史趨勢失敗', e);
      failedSections.add('institutionalHistory');
      return {};
    }
  }

  /// 載入成交額 30 日歷史（供趨勢 bar chart + 情緒對齊）
  ///
  /// 傳入 days: 30 覆蓋預設的 5 天，保留日期並反轉為 oldest→newest。
  Future<Map<String, List<DatedValue>>> _loadTurnoverHistoryByMarket(
    DateTime date, {
    required Set<String> failedSections,
  }) async {
    try {
      final raw = await _db.getRecentTurnoverByMarket(date, days: 30);
      final result = <String, List<DatedValue>>{};
      for (final entry in raw.entries) {
        result[entry.key] = entry.value.reversed
            .map<DatedValue>((e) => (date: e.date, value: e.turnover))
            .toList();
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入成交額歷史趨勢失敗', e);
      failedSections.add('turnoverHistory');
      return {};
    }
  }

  /// 載入融資/融券餘額 30 日歷史（供趨勢 sparkline + 情緒對齊）
  ///
  /// 回傳同時包含 margin 和 short 兩組 List，避免查兩次。
  /// margin 攜帶日期供情緒對齊；short 僅供 sparkline，維持純 [double]。
  Future<Map<String, ({List<DatedValue> margin, List<double> short})>>
  _loadMarginHistoryByMarket(
    DateTime date, {
    required Set<String> failedSections,
  }) async {
    try {
      final raw = await _db.getRecentMarginTradingByMarket(date);
      final result =
          <String, ({List<DatedValue> margin, List<double> short})>{};
      for (final entry in raw.entries) {
        final reversed = entry.value.reversed.toList();
        result[entry.key] = (
          margin: reversed
              .map<DatedValue>((e) => (date: e.date, value: e.marginBalance))
              .toList(),
          short: reversed.map((e) => e.shortBalance).toList(),
        );
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入融資融券歷史趨勢失敗', e);
      failedSections.add('marginHistory');
      return {};
    }
  }

  /// 載入漲跌比 30 日歷史（供趨勢 sparkline + 情緒對齊）
  ///
  /// 計算 advance / (advance + decline + unchanged)，範圍 0~1。
  /// 保留日期供 [MarketSentimentService.calculateHistoricalScores] 依日期對齊。
  Future<Map<String, List<DatedValue>>> _loadAdvanceDeclineHistoryByMarket(
    DateTime date, {
    required Set<String> failedSections,
  }) async {
    try {
      final raw = await _db.getRecentAdvanceDeclineByMarket(date);
      final result = <String, List<DatedValue>>{};
      for (final entry in raw.entries) {
        result[entry.key] = entry.value.reversed.map<DatedValue>((e) {
          final total = e.advance + e.decline + e.unchanged;
          return (date: e.date, value: total > 0 ? e.advance / total : 0.5);
        }).toList();
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入漲跌比歷史趨勢失敗', e);
      failedSections.add('advanceRatioHistory');
      return {};
    }
  }

  /// 載入籌碼異動偵測結果（依市場分組 + per-detector 失敗列名）
  Future<
    ({Map<String, List<ChipAnomaly>> byMarket, List<String> failedDetectors})
  >
  _loadChipAnomalies(DateTime date) async {
    try {
      final service = ChipAnomalyService(database: _db);
      return await service.detectAnomaliesByMarket(date);
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入籌碼異動失敗', e);
      // 服務層連建構都失敗=六類全不可信(靜默稽核 #4)
      return (
        byMarket: <String, List<ChipAnomaly>>{},
        failedDetectors: const [
          'highPledge',
          'insiderTransfer',
          'foreignNearLimit',
          'shortSurge',
          'institutionalSurge',
          'etfFilter',
        ],
      );
    }
  }

  /// 載入 52 週新高/新低家數（依市場分組）— 廣度趨勢
  ///
  /// 若主要日期缺少某市場資料，自動用 [fallbackDate] 補齊。
  Future<Map<String, ({int newHighs, int newLows})>> _loadNewHighLowByMarket(
    DateTime date, {
    DateTime? fallbackDate,
    required Set<String> failedSections,
  }) async {
    try {
      final data = await _db.getNewHighLowCountsByMarket(date);

      // 回退：若缺少某市場，嘗試前一交易日補齊
      if (fallbackDate != null && data.length < 2) {
        final fallbackData = await _db.getNewHighLowCountsByMarket(
          fallbackDate,
        );
        for (final entry in fallbackData.entries) {
          data.putIfAbsent(entry.key, () => entry.value);
        }
      }

      return data;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入 52 週新高新低家數失敗', e);
      failedSections.add('newHighLow');
      return {};
    }
  }

  /// 載入 AD 騰落線（依市場分組，oldest→newest 累積值）— 廣度趨勢
  ///
  /// 複用 [getRecentAdvanceDeclineByMarket]（已 coverage-filter 完整日），
  /// 取每日 (advance − decline) 後由舊到新累加為騰落線。
  Future<Map<String, List<double>>> _loadAdLineByMarket(
    DateTime date, {
    required Set<String> failedSections,
  }) async {
    try {
      final raw = await _db.getRecentAdvanceDeclineByMarket(
        date,
        days: kAdLineLookbackDays,
      );
      final result = <String, List<double>>{};
      for (final entry in raw.entries) {
        // raw 為日期降序（最新在前），反轉為 oldest→newest 後累加
        final dailyNet = entry.value.reversed
            .map((e) => (e.advance - e.decline).toDouble())
            .toList();
        result[entry.key] = cumulativeAdLine(dailyNet);
      }
      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入 AD 騰落線失敗', e);
      failedSections.add('adLine');
      return {};
    }
  }

  /// 載入產業表現（依市場分組，TWSE + TPEx 各自查詢）
  Future<Map<String, List<IndustrySummary>>> _loadIndustrySummaryByMarket(
    DateTime date, {
    DateTime? fallbackDate,
    required Set<String> failedSections,
  }) async {
    try {
      final result = <String, List<IndustrySummary>>{};

      for (final market in [MarketCode.twse, MarketCode.tpex]) {
        var data = await _db.getIndustrySummaryByMarket(date, market);

        if (data.isEmpty && fallbackDate != null) {
          data = await _db.getIndustrySummaryByMarket(fallbackDate, market);
        }

        if (data.isNotEmpty) {
          result[market] = _mergeNormalizedIndustries(data);
        }
      }

      return result;
    } catch (e) {
      AppLogger.warning('MarketOverviewNotifier', '載入產業表現失敗', e);
      failedSections.add('industrySummary');
      return {};
    }
  }

  /// 正規化產業名稱並合併重複項（FinMind API 命名不一致）
  ///
  /// 例如「其他電子業」與「其他電子類」會被合併為同一筆。
  /// 合併後重新排序（avgChangePct DESC）。
  ///
  /// 2026-08-13:momentum5d 管線整條移除——唯一 UI 讀者(產業表現區塊)
  /// 已併入族群排行,而情緒綜合只讀 avgChangePct。原本每次刷新對兩市場
  /// 各跑一趟 ROW_NUMBER() OVER 全市場掃描,白做。
  static List<IndustrySummary> _mergeNormalizedIndustries(
    List<
      ({
        String industry,
        int stockCount,
        double avgChangePct,
        int advance,
        int decline,
      })
    >
    rows,
  ) {
    final merged = <String, _MutableIndustry>{};

    for (final row in rows) {
      final canonical = IndustryNames.normalize(row.industry);
      final entry = merged.putIfAbsent(canonical, _MutableIndustry.new);
      entry.addRow(row);
    }

    final list = merged.entries.map((e) => e.value.toSummary(e.key)).toList()
      ..sort((a, b) => b.avgChangePct.compareTo(a.avgChangePct));
    return list;
  }
}

/// 可變的產業聚合器（用於合併重複命名的產業）
class _MutableIndustry {
  int stockCount = 0;
  double _changePctSum = 0;
  int _changePctCount = 0;
  int advance = 0;
  int decline = 0;

  void addRow(
    ({
      String industry,
      int stockCount,
      double avgChangePct,
      int advance,
      int decline,
    })
    row,
  ) {
    stockCount += row.stockCount;
    _changePctSum += row.avgChangePct * row.stockCount;
    _changePctCount += row.stockCount;
    advance += row.advance;
    decline += row.decline;
  }

  /// 加權平均漲跌幅
  double get avgChangePct =>
      _changePctCount > 0 ? _changePctSum / _changePctCount : 0;

  IndustrySummary toSummary(String industry) => IndustrySummary(
    industry: industry,
    stockCount: stockCount,
    avgChangePct: avgChangePct,
    advance: advance,
    decline: decline,
  );
}

// ==================================================
// Provider
// ==================================================

final marketOverviewProvider =
    NotifierProvider<MarketOverviewNotifier, MarketOverviewState>(
      MarketOverviewNotifier.new,
    );
