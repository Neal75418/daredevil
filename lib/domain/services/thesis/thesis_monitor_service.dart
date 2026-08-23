import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/thesis/thesis_invalidation_rules.dart';

/// 釘選論點監控服務（出場層 Phase 2）
///
/// 每日更新完成後由 `UpdateService` fail-safe 呼叫（比照
/// `RuleAccuracyService`：錯誤不中斷更新流程）。對每筆 ACTIVE 釘選
/// **從 pinnedDate 全量重算**失效條件（冪等、無增量狀態——App 跳幾天
/// 不更新也不會錯，spec §5）；已 INVALIDATED 者不在掃描範圍（凍結）。
class ThesisMonitorService {
  const ThesisMonitorService({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  /// 檢查所有 ACTIVE 釘選。回傳本次失效筆數。
  ///
  /// [asOf]：本次檢查時間（寫入 lastCheckedDate；staleness 顯示用）。
  Future<int> checkActiveTheses({required DateTime asOf}) async {
    final active = await _db.getActiveTheses();
    if (active.isEmpty) return 0;

    var invalidated = 0;
    var failed = 0;
    for (final thesis in active) {
      try {
        final prices = await _db.getPriceHistory(
          thesis.symbol,
          startDate: thesis.pinnedDate,
          endDate: asOf,
        );

        if (prices.isNotEmpty) {
          prices.sort((a, b) => a.date.compareTo(b.date));
          final result = ThesisInvalidationRules.evaluate(
            referencePrice: thesis.referencePrice,
            closesFromPinnedDate: [for (final p in prices) p.close],
          );
          if (result != null) {
            await _db.invalidateThesis(
              thesis.id,
              invalidatedDate: prices[result.triggerOffset].date,
              reason: result.reason.name,
            );
            invalidated++;
            AppLogger.info(
              'ThesisMonitor',
              '${thesis.symbol} 論點失效（${result.reason.name}，'
                  '釘選 ${thesis.pinnedDate} → 觸發 '
                  '${prices[result.triggerOffset].date}）',
            );
          }
        }

        // 蓋章放最後、逐筆進行：只有真的評估完才蓋。整批先蓋會讓中途拋錯
        // 時未評估的論點在 UI 上謊報「最後檢查：今天」。
        // `touchLastCheckedById` 不篩 status，所以剛失效那筆也蓋得到。
        await _db.touchLastCheckedById(thesis.id, asOf);
      } catch (e, st) {
        // 單筆失敗不中斷整輪；該筆不蓋章 → staleness 會如實顯示為過期。
        failed++;
        AppLogger.warning(
          'ThesisMonitor',
          '${thesis.symbol} 檢查失敗，該筆維持舊的最後檢查時間',
          e,
          st,
        );
      }
    }

    if (invalidated > 0) {
      AppLogger.info('ThesisMonitor', '本次失效 $invalidated / ${active.length} 筆');
    }

    // 逐筆 catch 只保證「一筆壞不中斷整輪」，**不代表這輪成功**。
    // 全部吞掉會讓 `_checkPinnedThesesFailSafe` 收不到例外 → 不會
    // `recordError` → update_run 標成 SUCCESS、Sentry 只剩 breadcrumb，
    // 於是「一筆都沒檢查到」與「一切正常」在 App 裡長得一模一樣。
    // 此處在全部處理完之後才拋，已完成的評估與蓋章都不會回滾。
    if (failed > 0) {
      throw StateError(
        '釘選論點檢查：${active.length} 筆中 $failed 筆失敗（逐筆原因見 warning log）',
      );
    }
    return invalidated;
  }
}
