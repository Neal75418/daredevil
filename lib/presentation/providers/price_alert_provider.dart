import 'dart:async';
import 'package:drift/drift.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/alert/trailing_ma_alert_service.dart';
import 'package:daredevil/domain/services/alert_evaluation_service.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 警示類型列舉
enum AlertType {
  // 價格類警示
  above('ABOVE'),
  below('BELOW'),
  changePct('CHANGE_PCT'),

  // 成交量警示
  volumeSpike('VOLUME_SPIKE'),
  volumeAbove('VOLUME_ABOVE'),

  // RSI 警示
  rsiOverbought('RSI_OVERBOUGHT'),
  rsiOversold('RSI_OVERSOLD'),

  // KD 警示
  kdGoldenCross('KD_GOLDEN_CROSS'),
  kdDeathCross('KD_DEATH_CROSS'),

  // 支撐/壓力警示
  breakResistance('BREAK_RESISTANCE'),
  breakSupport('BREAK_SUPPORT'),

  // 52 週警示
  week52High('WEEK_52_HIGH'),
  week52Low('WEEK_52_LOW'),

  // 均線警示
  crossAboveMa('CROSS_ABOVE_MA'),
  crossBelowMa('CROSS_BELOW_MA'),

  // 基本面警示
  revenueYoySurge('REVENUE_YOY_SURGE'),
  highDividendYield('HIGH_DIVIDEND_YIELD'),
  peUndervalued('PE_UNDERVALUED'),

  // 交易警示
  tradingWarning('TRADING_WARNING'),
  tradingDisposal('TRADING_DISPOSAL'),

  // 內部人警示
  insiderSelling('INSIDER_SELLING'),
  insiderBuying('INSIDER_BUYING'),
  highPledgeRatio('HIGH_PLEDGE_RATIO');

  const AlertType(this.value);
  final String value;

  /// 翻譯後的顯示標籤（i18n）
  String get label => 'alert.alertType.$name'.tr();

  /// 檢查此警示類型是否需要目標值
  bool get requiresTargetValue => switch (this) {
    AlertType.above ||
    AlertType.below ||
    AlertType.changePct ||
    AlertType.volumeAbove ||
    AlertType.rsiOverbought ||
    AlertType.rsiOversold ||
    AlertType.breakResistance ||
    AlertType.breakSupport ||
    AlertType.crossAboveMa ||
    AlertType.crossBelowMa ||
    AlertType.revenueYoySurge ||
    AlertType.highDividendYield ||
    AlertType.peUndervalued => true,
    // 以下類型不需明確目標值（自動觸發）
    AlertType.volumeSpike ||
    AlertType.kdGoldenCross ||
    AlertType.kdDeathCross ||
    AlertType.week52High ||
    AlertType.week52Low ||
    // Killer Features：自動觸發，無需目標值
    AlertType.tradingWarning ||
    AlertType.tradingDisposal ||
    AlertType.insiderSelling ||
    AlertType.insiderBuying ||
    AlertType.highPledgeRatio => false,
  };

  /// 取得此警示類型的預設目標值（常數集中於 AlertParams）
  double? get defaultTargetValue => switch (this) {
    AlertType.rsiOverbought => AlertParams.defaultRsiOverbought,
    AlertType.rsiOversold => AlertParams.defaultRsiOversold,
    AlertType.crossAboveMa ||
    AlertType.crossBelowMa => AlertParams.defaultMaCrossDays,
    AlertType.volumeSpike => AlertParams.defaultVolumeSpikeMultiplier,
    AlertType.revenueYoySurge => AlertParams.defaultRevenueYoySurgePct,
    AlertType.highDividendYield => AlertParams.defaultHighDividendYieldPct,
    AlertType.peUndervalued => AlertParams.defaultPeUndervalued,
    _ => null,
  };

  /// 檢查此警示類型是否已實作觸發邏輯
  ///
  /// 僅已實作的類型可供使用者在 UI 中建立。
  /// 回傳 true 的警示類型在 user_dao.dart 中有觸發邏輯。
  // 已實作的 AlertType:
  // - above, below, changePct (基本價格)
  // - volumeSpike, volumeAbove (成交量)
  // - week52High, week52Low (52 週)
  // - rsiOverbought, rsiOversold, kdGoldenCross, kdDeathCross (技術指標)
  // - crossAboveMa, crossBelowMa, tradingWarning, tradingDisposal (均線/警示)
  bool get isImplemented => switch (this) {
    AlertType.above ||
    AlertType.below ||
    AlertType.changePct ||
    AlertType.volumeSpike ||
    AlertType.volumeAbove ||
    AlertType.week52High ||
    AlertType.week52Low ||
    AlertType.rsiOverbought ||
    AlertType.rsiOversold ||
    AlertType.kdGoldenCross ||
    AlertType.kdDeathCross ||
    AlertType.crossAboveMa ||
    AlertType.crossBelowMa ||
    AlertType.tradingWarning ||
    AlertType.tradingDisposal ||
    AlertType.breakResistance ||
    AlertType.breakSupport ||
    AlertType.revenueYoySurge ||
    AlertType.highDividendYield ||
    AlertType.peUndervalued ||
    AlertType.insiderSelling ||
    AlertType.insiderBuying ||
    AlertType.highPledgeRatio => true,
  };

  /// 從字串值解析 AlertType。
  ///
  /// 若值不是有效的 AlertType，拋出 [ArgumentError]。
  static AlertType fromValue(String value) {
    return tryFromValue(value) ??
        (throw ArgumentError.value(
          value,
          'value',
          'Invalid AlertType value. Valid values: ${AlertType.values.map((e) => e.value).join(", ")}',
        ));
  }

  /// 嘗試從字串值解析 AlertType。
  ///
  /// 若值不是有效的 AlertType，回傳 null。
  static AlertType? tryFromValue(String value) {
    for (final type in AlertType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// 取得 AlertType 的 i18n 描述（用於 UI 顯示）
///
/// 共用函式，避免 alerts_screen.dart 和 alerts_tab.dart 各自重複維護。
String getAlertDescription(PriceAlertEntry alert, AlertType type) {
  return switch (type) {
    AlertType.above => 'alert.priceAbove'.tr(
      namedArgs: {'price': alert.targetValue.toStringAsFixed(2)},
    ),
    AlertType.below => 'alert.priceBelow'.tr(
      namedArgs: {'price': alert.targetValue.toStringAsFixed(2)},
    ),
    AlertType.changePct => 'alert.changeAbove'.tr(
      namedArgs: {'percent': alert.targetValue.toStringAsFixed(1)},
    ),
    AlertType.volumeSpike => 'alert.desc.volumeSpike'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(0)},
    ),
    AlertType.volumeAbove => 'alert.desc.volumeAbove'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(0)},
    ),
    AlertType.rsiOverbought => 'alert.desc.rsiOverbought'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(0)},
    ),
    AlertType.rsiOversold => 'alert.desc.rsiOversold'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(0)},
    ),
    AlertType.kdGoldenCross => 'alert.desc.kdGoldenCross'.tr(),
    AlertType.kdDeathCross => 'alert.desc.kdDeathCross'.tr(),
    AlertType.breakResistance => 'alert.desc.breakResistance'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(2)},
    ),
    AlertType.breakSupport => 'alert.desc.breakSupport'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(2)},
    ),
    AlertType.week52High => 'alert.desc.week52High'.tr(),
    AlertType.week52Low => 'alert.desc.week52Low'.tr(),
    AlertType.crossAboveMa => 'alert.desc.crossAboveMa'.tr(
      namedArgs: {'value': alert.targetValue.toInt().toString()},
    ),
    AlertType.crossBelowMa => 'alert.desc.crossBelowMa'.tr(
      namedArgs: {'value': alert.targetValue.toInt().toString()},
    ),
    AlertType.revenueYoySurge => 'alert.desc.revenueYoySurge'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(1)},
    ),
    AlertType.highDividendYield => 'alert.desc.highDividendYield'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(1)},
    ),
    AlertType.peUndervalued => 'alert.desc.peUndervalued'.tr(
      namedArgs: {'value': alert.targetValue.toStringAsFixed(1)},
    ),
    AlertType.tradingWarning => 'alert.desc.tradingWarning'.tr(),
    AlertType.tradingDisposal => 'alert.desc.tradingDisposal'.tr(),
    AlertType.insiderSelling => 'alert.desc.insiderSelling'.tr(),
    AlertType.insiderBuying => 'alert.desc.insiderBuying'.tr(),
    AlertType.highPledgeRatio => 'alert.desc.highPledgeRatio'.tr(),
  };
}

/// 價格警示狀態
class PriceAlertState {
  const PriceAlertState({
    this.alerts = const [],
    this.stockNames = const {},
    this.unmonitorableSymbols = const {},
    this.isLoading = false,
    this.error,
  });

  final List<PriceAlertEntry> alerts;

  /// 代碼 → 名稱。`price_alert` 只存代碼,名稱在 `stock_master`——清單只顯示
  /// 「3231」而不是「緯創」,提醒一多就認不出來(2026-08-08 實機回報)。
  final Map<String, String> stockNames;

  /// 主檔查不到(或已非上市中)的代碼——盤中/盤後監控都以主檔為準,這些
  /// 提醒**永遠不會觸發**。監控端只在日誌裡 warning,而 release build 的
  /// AppLogger 對所有等級都靜默(2026-08-29 review):GUI 使用者掛在下市
  /// 代號上的提醒會無聲卡死。唯一能修的人是使用者(刪掉或改代號),所以
  /// 訊號放在提醒清單上,不放日誌。判準與 monitor 的 getAllActiveStocks
  /// 等價:無 row 或 isActive=false。
  final Set<String> unmonitorableSymbols;
  final bool isLoading;
  final String? error;

  PriceAlertState copyWith({
    List<PriceAlertEntry>? alerts,
    Map<String, String>? stockNames,
    Set<String>? unmonitorableSymbols,
    bool? isLoading,
    Object? error = sentinel,
  }) {
    return PriceAlertState(
      alerts: alerts ?? this.alerts,
      stockNames: stockNames ?? this.stockNames,
      unmonitorableSymbols: unmonitorableSymbols ?? this.unmonitorableSymbols,
      isLoading: isLoading ?? this.isLoading,
      error: error == sentinel ? this.error : error as String?,
    );
  }
}

/// 價格警示 Notifier
/// 已認領的提醒 + 本次認領寫入的時戳。
///
/// 兩者必須成對傳遞:釋放認領時要比對 stamp,否則會抹掉別人剛寫進去的
/// 認領 → 同一次觸價被通知兩次(2026-08-08 四次審查)。
typedef ClaimedAlert = ({PriceAlertEntry alert, DateTime claimStamp});

class PriceAlertNotifier extends Notifier<PriceAlertState> {
  late final AppDatabase _db;

  /// 同一 alert 的 in-flight toggle Future（序列化執行，last wins）
  Map<int, Future<void>> _pendingToggles = {};

  @override
  PriceAlertState build() {
    _db = ref.watch(databaseProvider);
    _pendingToggles = {};
    return const PriceAlertState();
  }

  /// 載入所有警示（啟用與停用）
  Future<void> loadAlerts() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final alerts = await _db.getAllAlerts();
      // 名稱是**純裝飾**:查不到就不顯示,絕不可讓它拖垮主功能。
      // 第一版沒包 try,mock DB 沒實作 getStock 就讓整個 loadAlerts 進
      // catch、清單變空——一個顯示用的加值把核心功能弄壞,正是這個專案
      // 反覆吃虧的形狀(2026-08-08)。
      final names = <String, String>{};
      // 同一趟迴圈順帶判定監控性:無 row 或 isActive=false ⟺ monitor 的
      // getAllActiveStocks 查不到 ⟺ 這檔的提醒永遠不會觸發。兩個判準必須
      // 同源,否則 UI 說可監控、monitor 說查無此檔會漂移。
      final unmonitorable = <String>{};
      try {
        for (final sym in alerts.map((a) => a.symbol).toSet()) {
          final stock = await _db.getStock(sym);
          if (stock != null) names[sym] = stock.name;
          if (stock == null || !stock.isActive) unmonitorable.add(sym);
        }
      } catch (e) {
        // 查詢失敗時 unmonitorable 只有失敗前已判定的部分——寧可少標
        // 不誤標(標了使用者會去刪提醒,誤標的代價比漏標高)
        AppLogger.warning('PriceAlertNotifier', '查詢股票名稱失敗,清單只顯示代碼', e);
      }
      state = state.copyWith(
        alerts: alerts,
        stockNames: names,
        unmonitorableSymbols: unmonitorable,
        isLoading: false,
      );
    } catch (e) {
      AppLogger.warning('PriceAlertNotifier', '載入警示失敗', e);
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
    }
  }

  /// 依均線階梯重算所有自選股的自動提醒，回傳成功設定的檔數
  ///
  /// **手動設定的提醒（`managed_by IS NULL`）一列都不動**——保證在
  /// [TrailingMaAlertService] 內，不在這層。
  ///
  /// 每日更新已會自動做這件事（`UpdateService._refreshTrailingAlertsFailSafe`），
  /// 這裡只是手動觸發入口：剛加完自選股、或想立刻看到結果時用。
  Future<int> refreshTrailingAlerts() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final count = await TrailingMaAlertService(database: _db).refresh();
      await loadAlerts();
      return count;
    } catch (e) {
      AppLogger.warning('PriceAlertNotifier', '均線階梯提醒重算失敗', e);
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
      return 0;
    }
  }

  /// 清除錯誤狀態
  void clearError() => state = state.copyWith(error: null);

  /// 建立新的價格警示
  Future<bool> createAlert({
    required String symbol,
    required AlertType alertType,
    required double targetValue,
    String? note,
  }) async {
    try {
      final id = await _db.createPriceAlert(
        symbol: symbol,
        alertType: alertType.value,
        targetValue: targetValue,
        note: note,
      );

      // 增量更新：新增至 state 而非全量重載
      // 插入開頭以維持建立時間降冪
      final newAlert = await _db.getAlertById(id);
      if (newAlert != null) {
        state = state.copyWith(alerts: [newAlert, ...state.alerts]);
      }
      return true;
    } catch (e) {
      AppLogger.warning('PriceAlertNotifier', '建立警示失敗: $symbol', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
      return false;
    }
  }

  /// 編輯警示目標值與備註
  Future<bool> editAlert({
    required int id,
    required double targetValue,
    String? note,
  }) async {
    final previousAlerts = state.alerts;

    // 樂觀更新
    state = state.copyWith(
      alerts: state.alerts.map((a) {
        if (a.id == id) {
          return PriceAlertEntry(
            id: a.id,
            symbol: a.symbol,
            alertType: a.alertType,
            targetValue: targetValue,
            isActive: true, // 編輯後自動重新啟用
            triggeredAt: null, // 清除觸發紀錄
            note: note,
            createdAt: a.createdAt,
          );
        }
        return a;
      }).toList(),
    );

    try {
      await _db.updatePriceAlert(
        id,
        PriceAlertCompanion(
          targetValue: Value(targetValue),
          note: Value(note),
          isActive: const Value(true),
          triggeredAt: const Value(null),
        ),
      );
      return true;
    } catch (e) {
      AppLogger.warning('PriceAlertNotifier', '編輯警示失敗: $id', e);
      state = state.copyWith(
        alerts: previousAlerts,
        error: ErrorDisplay.message(e),
      );
      return false;
    }
  }

  /// 刪除警示
  Future<void> deleteAlert(int id) async {
    // 樂觀更新：立即從 state 移除，並清除先前錯誤
    final previousAlerts = state.alerts;
    state = state.copyWith(
      alerts: state.alerts.where((a) => a.id != id).toList(),
      error: null,
    );

    try {
      await _db.deletePriceAlert(id);
    } catch (e) {
      // 錯誤時回滾
      AppLogger.warning('PriceAlertNotifier', '刪除警示失敗: $id', e);
      state = state.copyWith(
        alerts: previousAlerts,
        error: ErrorDisplay.message(e),
      );
    }
  }

  /// 切換警示啟用狀態
  ///
  /// 序列化同一 alert 的操作：若前一次 toggle 仍在執行，會等它完成後
  /// 再執行本次操作，確保最後一次使用者意圖落庫（last wins）。
  Future<void> toggleAlert(int id, bool isActive) async {
    // 捕獲前一次 in-flight Future（若有）
    final pending = _pendingToggles[id];

    Future<void> doToggle() async {
      // 等待前一次完成後再執行，確保序列化
      // try-catch: 前一次的錯誤不應阻擋本次操作
      if (pending != null) {
        try {
          await pending;
        } catch (_) {
          // 前一次已自行處理錯誤（rollback + state.error），忽略即可
        }
      }
      await _doToggleAlert(id, isActive);
    }

    final future = doToggle();
    _pendingToggles[id] = future;
    try {
      await future;
    } finally {
      // 僅清除自己的 Future，避免移除後續排隊的操作
      if (_pendingToggles[id] == future) {
        _pendingToggles.remove(id);
      }
    }
  }

  Future<void> _doToggleAlert(int id, bool isActive) async {
    // 樂觀更新：立即切換 state，並清除先前錯誤
    final previousAlerts = state.alerts;
    state = state.copyWith(
      error: null,
      alerts: state.alerts.map((a) {
        if (a.id == id) {
          return PriceAlertEntry(
            id: a.id,
            symbol: a.symbol,
            alertType: a.alertType,
            targetValue: a.targetValue,
            isActive: isActive,
            triggeredAt: a.triggeredAt,
            note: a.note,
            createdAt: a.createdAt,
          );
        }
        return a;
      }).toList(),
    );

    try {
      await _db.updatePriceAlert(
        id,
        PriceAlertCompanion(
          isActive: Value(isActive),
          // 重新啟用 = 重新開始等(2026-08-08 code review):不清 triggeredAt
          // 的話,盤中監控的 `triggeredAt == null` 過濾會**永久跳過**這筆,
          // 使用者以為在盯盤、實際只有收盤那條路徑會叫。
          triggeredAt: isActive ? const Value(null) : const Value.absent(),
        ),
      );
    } catch (e) {
      // 錯誤時回滾
      AppLogger.warning('PriceAlertNotifier', '切換警示狀態失敗: $id', e);
      state = state.copyWith(
        alerts: previousAlerts,
        error: ErrorDisplay.message(e),
      );
    }
  }

  /// 已實作的警示類型字串集合（與 evaluator switch 一致，用於偵測需停用的類型）
  static final _knownAlertTypes = AlertType.values
      .where((e) => e.isImplemented)
      .map((e) => e.value)
      .toSet();

  /// 根據當前價格檢查警示觸發條件。
  ///
  /// 回傳「本次真的搶到認領」的提醒,**連同認領時戳**——釋放時必須帶著
  /// 它比對(見 `UserDaoMixin.releaseAlertClaim`)。
  Future<List<ClaimedAlert>> checkAndTriggerAlerts(
    Map<String, double> currentPrices,
    Map<String, double> priceChanges,
  ) async {
    try {
      final triggered = await _db.checkAlerts(
        currentPrices,
        priceChanges,
        evaluationService: AlertEvaluationService(),
      );
      final triggeredIds = <int>{};
      final now = DateTime.now();

      // 只保留「本次真的搶到」的——呼叫端(today_provider)會為回傳清單
      // 的每一筆發通知,回傳未過濾的等於沒去重(2026-08-08 三次審查 F-1:
      // 上一輪只跳過 triggeredIds.add,卻仍回傳原清單,宣稱修好但沒修)。
      // 帶著本次認領的 stamp 一起回傳:釋放時必須比對它,否則會抹掉
      // 別人剛寫進去的認領(2026-08-08 四次審查)。不可用 alert.triggeredAt
      // ——那是認領**之前**讀到的值,必為 null。
      final claimedAlerts = <ClaimedAlert>[];
      for (final alert in triggered) {
        final claimed = await _db.claimAlertTrigger(alert.id, now: now);
        if (!claimed) continue;
        claimedAlerts.add((alert: alert, claimStamp: now));
        triggeredIds.add(alert.id);
      }

      // 增量更新：同步 triggered 與 DAO 自動停用的舊版 alert 至 state
      state = state.copyWith(
        alerts: state.alerts.map((a) {
          if (triggeredIds.contains(a.id)) {
            return PriceAlertEntry(
              id: a.id,
              symbol: a.symbol,
              alertType: a.alertType,
              targetValue: a.targetValue,
              isActive: false,
              triggeredAt: now,
              note: a.note,
              createdAt: a.createdAt,
            );
          }
          // DAO checkAlerts 已自動停用未實作類型，同步至 state
          if (a.isActive && !_knownAlertTypes.contains(a.alertType)) {
            return PriceAlertEntry(
              id: a.id,
              symbol: a.symbol,
              alertType: a.alertType,
              targetValue: a.targetValue,
              isActive: false,
              triggeredAt: a.triggeredAt,
              note: a.note,
              createdAt: a.createdAt,
            );
          }
          return a;
        }).toList(),
      );

      // F-2:沒搶到的那些,DB 已被別的 process 標成觸發,但本地 state
      // 仍顯示「啟用中」——重載一次讓清單與 DB 一致。
      if (claimedAlerts.length != triggered.length) {
        unawaited(loadAlerts());
      }
      return claimedAlerts;
    } catch (e) {
      AppLogger.warning('PriceAlertNotifier', '檢查警示觸發失敗', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
      return [];
    }
  }
}

/// 價格警示 Provider
final priceAlertProvider =
    NotifierProvider<PriceAlertNotifier, PriceAlertState>(
      PriceAlertNotifier.new,
    );
