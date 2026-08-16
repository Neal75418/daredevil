import 'package:drift/drift.dart' show Value;
import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';

/// 均線階梯的一階：該掛什麼類型、什麼價位、備註寫什麼
typedef TrailingTier = ({String alertType, double target, String note});

/// 均線階梯提醒——讓提醒價位跟著均線走
///
/// **它解決什麼**：提醒價位是死的，均線是活的。手動設一次「跌破 5MA 通知」，
/// 過幾天那個價位就落在錯的地方。2026-08-16 重整 36 檔提醒時，舊設定全數
/// 落後於當時的 5MA——做成按鈕只是把失效間隔縮短、靠人記得按；掛進每日更新
/// 才是讓它永遠釘在狀態邊界上。
///
/// **階梯語意**（單向、每檔恰好一個提醒）：
///
/// | 現價位置        | 提醒          | 意圖             |
/// |:---------------|:-------------|:----------------|
/// | 站上 5MA        | `BELOW` 5MA  | 監控何時轉弱      |
/// | 破 5MA、守月線   | `BELOW` 20MA | 監控趨勢是否崩壞   |
/// | 破月線、守季線   | `ABOVE` 20MA | 等它何時轉強      |
/// | 破季線          | `ABOVE` 60MA | 等它真的回來      |
///
/// 越強用越近的線監控轉弱，越弱用越遠的線等待轉強。觸發即代表狀態真的變了，
/// 而下一次重算會自動把它移到新的那一階。
///
/// **不碰手動提醒**：只讀寫 `managed_by = TRAILING_MA` 的列。使用者特地設的
/// 關鍵價位（`managed_by IS NULL`）一列都不動——那是 `managed_by` 欄存在的
/// 唯一理由。
class TrailingMaAlertService {
  TrailingMaAlertService({
    required AppDatabase database,
    TechnicalIndicatorService? indicators,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _ta = indicators ?? TechnicalIndicatorService(),
       _clock = clock;

  final AppDatabase _db;
  final TechnicalIndicatorService _ta;
  final AppClock _clock;

  /// 要載入多少**日曆日**的價格才夠算 60 個**交易日**的均線。
  ///
  /// 60 交易日 ≈ 12 週 ≈ 84 日曆日；取 150 天留足連假、停牌與資料缺口的
  /// 餘裕。多載的部分只影響一次批次查詢，算 SMA 時取 `.last` 不受影響。
  static const int lookbackCalendarDays = 150;

  /// 由現價與三條均線決定該掛哪一階——純函數，階梯規則的單一事實來源
  ///
  /// 回傳 `null` = 資料不足以決定，呼叫端應跳過該檔而**不是**退而求其次。
  /// 硬掛一個已在線下的 `BELOW` 會立刻觸發，那是每天一則假通知，比沒有
  /// 提醒更糟。
  @visibleForTesting
  static TrailingTier? resolveTier({
    required double price,
    required double? ma5,
    required double? ma20,
    required double? ma60,
  }) {
    if (ma5 == null) return null;
    if (price >= ma5) {
      return (
        alertType: AlertParams.typeBelow,
        target: ma5,
        note: '站上5MA→跌破5MA示警',
      );
    }

    if (ma20 == null) return null;
    if (price >= ma20) {
      return (
        alertType: AlertParams.typeBelow,
        target: ma20,
        note: '已破5MA→跌破月線示警',
      );
    }

    if (ma60 == null) return null;
    // 這裡是階梯唯一的方向翻轉點：由「監控轉弱」改為「等待轉強」
    if (price >= ma60) {
      return (
        alertType: AlertParams.typeAbove,
        target: ma20,
        note: '月線之下→突破月線示警',
      );
    }

    return (
      alertType: AlertParams.typeAbove,
      target: ma60,
      note: '季線之下→突破季線示警',
    );
  }

  /// 重算全自選股的均線階梯提醒，回傳成功設定的檔數
  ///
  /// 就地更新（保留列 ID）而非刪除重建，否則每天都會多一筆。已觸發過的
  /// 自動提醒會**重新武裝**（`is_active` 復原、`triggered_at` 清空）——階梯
  /// 提醒的用途是持續追蹤狀態邊界，只響一次就失去意義。
  Future<int> refresh({DateTime? asOf}) async {
    final symbols = (await _db.getWatchlist()).map((w) => w.symbol).toSet();
    final existing = await _db.getManagedAlerts(
      AlertParams.managedByTrailingMa,
    );

    // 先收斂:已移出自選股的整組刪掉;仍是自選股的只留第一筆——其餘是
    // GUI 與 CLI 併發插入的重複,不清掉就會每天各自通知,而且因為清理迴圈
    // 只掃「已非自選股」的列而永遠碰不到它。
    //
    // 手動提醒因 managed_by IS NULL 根本不在這份 map 裡，不可能被誤刪。
    var removed = 0;
    var deduped = 0;
    for (final entry in existing.entries) {
      final stillWatched = symbols.contains(entry.key);
      for (final alert in entry.value.skip(stillWatched ? 1 : 0)) {
        await _db.deletePriceAlert(alert.id);
        stillWatched ? deduped++ : removed++;
      }
    }

    var written = 0;
    var skipped = 0;

    if (symbols.isNotEmpty) {
      final startDate = (asOf ?? _clock.now()).subtract(
        const Duration(days: lookbackCalendarDays),
      );
      final histories = await _db.getPriceHistoryBatch(
        symbols.toList(),
        startDate: startDate,
      );

      for (final symbol in symbols) {
        // close 可為 NULL：TWSE 對「無成交」回 0.00，落庫後由
        // `_ensureZeroPriceSanitized` 冪等 NULL 化（0 會污染均線）
        final closes = (histories[symbol] ?? const <DailyPriceEntry>[])
            .map((p) => p.close)
            .whereType<double>()
            .toList();
        if (closes.isEmpty) {
          skipped++;
          continue;
        }

        final tier = resolveTier(
          price: closes.last,
          ma5: _sma(closes, AlertParams.trailingMaShort),
          ma20: _sma(closes, AlertParams.trailingMaMedium),
          ma60: _sma(closes, AlertParams.trailingMaLong),
        );
        if (tier == null) {
          skipped++;
          continue;
        }

        final prior = existing[symbol]?.firstOrNull;
        if (prior == null) {
          await _db.createPriceAlert(
            symbol: symbol,
            alertType: tier.alertType,
            targetValue: tier.target,
            note: tier.note,
            managedBy: AlertParams.managedByTrailingMa,
          );
        } else {
          await _db.updatePriceAlert(
            prior.id,
            PriceAlertCompanion(
              alertType: Value(tier.alertType),
              targetValue: Value(tier.target),
              note: Value(tier.note),
              isActive: const Value(true),
              triggeredAt: const Value(null),
            ),
          );
        }
        written++;
      }
    }

    if (written > 0 || removed > 0 || deduped > 0 || skipped > 0) {
      AppLogger.info(
        'TrailingMaAlert',
        '均線階梯提醒: 設定 $written 檔'
            '${removed > 0 ? ', 移除 $removed 檔(已非自選)' : ''}'
            '${deduped > 0 ? ', 收斂 $deduped 筆重複' : ''}'
            '${skipped > 0 ? ', 跳過 $skipped 檔(價格不足)' : ''}',
      );
    }
    return written;
  }

  /// 最近一筆 SMA；資料不足回 `null`（[TechnicalIndicatorService.calculateSMA]
  /// 回傳與輸入等長、不足處為 null 的列表，故取 `.last`）
  double? _sma(List<double> closes, int period) =>
      _ta.calculateSMA(closes, period).last;
}
