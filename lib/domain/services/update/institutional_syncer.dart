import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';

/// 法人買賣超資料同步器
///
/// 負責同步外資、投信、自營商買賣超資料
class InstitutionalSyncer {
  const InstitutionalSyncer({
    required InstitutionalRepository institutionalRepository,
  }) : _institutionalRepo = institutionalRepository;

  final InstitutionalRepository _institutionalRepo;

  /// 同步法人資料
  ///
  /// 包含當日資料及近期回補
  /// [backfillDays] 指定回補天數，預設 [ApiConfig.institutionalDailyBackfillDays]
  /// （日常更新 15 天）；強制同步由 caller 傳深一點的
  /// [ApiConfig.institutionalForceBackfillDays] 以補足下游信號所需的歷史深度。
  ///
  /// **非破壞式**：force 只對「當日」繞快取；歷史回補日一律走 per-day
  /// 完整性檢查——已完整的天直接跳過，中斷（rate limit / 斷網）後重跑
  /// 只補缺的天。全清僅由口徑版本檢核（[InstitutionalRepository
  /// .ensureDataVersion]）在版本變更時觸發一次；原本 force 每次
  /// clearAllData 再重抓 62 天，中斷會留下日常 15 天回補補不回的深度殘缺。
  /// [onProgress] 逐回補交易日回報（如「法人回補 3/62 天」）——force 深回補
  /// 全缺時約 2-3 分鐘，無回報 UI 會像當機。
  Future<InstitutionalSyncResult> syncInstitutionalData({
    required DateTime date,
    bool force = false,
    int backfillDays = ApiConfig.institutionalDailyBackfillDays,
    void Function(String message)? onProgress,
  }) async {
    var syncedDays = 0;
    final errors = <String>[];

    // 口徑版本檢核（每次入口，日常更新也會遷移）；失敗不中斷同步，
    // 下次入口重試
    var migrated = false;
    try {
      migrated = await _institutionalRepo.ensureDataVersion();
    } catch (e) {
      AppLogger.warning('InstitutionalSyncer', '法人口徑版本檢核失敗', e);
    }

    // 遷移剛清空全表，這一輪必須自己補回深度——否則 streak（90 日曆天）與
    // surge baseline（60 日）會在 ~10 個交易日的資料上靜默失真。穩態下
    // per-day 完整性檢查會跳過已完整的天（不睡不打），日常更新仍是淺回補。
    //
    // 深窗的觸發不只看 migrated（一次性）——遷移輪的深回補若被限流打斷，
    // 下一輪 migrated=false 會退回淺窗、第 16~62 天永久缺失。改由
    // pending marker 承載「深回補還沒完整跑完」：未蓋章前每輪都用深窗，
    // 已補的天由完整性檢查零成本跳過，撞限流就下輪續傳。
    var deepPending = migrated;
    if (!deepPending) {
      try {
        deepPending = await _institutionalRepo.isDeepBackfillPending();
      } catch (e) {
        AppLogger.warning('InstitutionalSyncer', '深回補 pending 檢核失敗', e);
      }
    }
    final effectiveBackfillDays =
        deepPending && backfillDays < ApiConfig.institutionalForceBackfillDays
        ? ApiConfig.institutionalForceBackfillDays
        : backfillDays;
    if (effectiveBackfillDays != backfillDays) {
      AppLogger.info(
        'InstitutionalSyncer',
        '口徑遷移已清空資料，本輪回補窗由 $backfillDays 拉深至 '
            '$effectiveBackfillDays 個日曆天',
      );
    }

    // 1. 同步當日資料（force 必抓；日常路徑若當日已完整——同晚二次更新——
    //    預檢跳過，不打 API）
    if (force || !await _isComplete(date)) {
      try {
        await _institutionalRepo.syncAllMarketInstitutional(date, force: force);
        syncedDays++;
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        errors.add('當日法人資料同步失敗: $e');
        AppLogger.warning('InstitutionalSyncer', '當日法人資料同步失敗', e);
      }
    }

    // 2. 回補近期資料——每天先預檢完整性，已完整**不睡不打**（穩態下
    //    回補窗全完整，原本每輪白睡 ~10 秒、force 深回補 ~62 秒）；
    //    缺漏的天才節流 + 抓取，形成斷點續傳
    final backfillDates = [
      for (var i = 1; i < effectiveBackfillDays; i++)
        date.subtract(Duration(days: i)),
    ].where(TaiwanCalendar.isTradingDay).toList();

    var skippedDays = 0;
    for (var i = 0; i < backfillDates.length; i++) {
      final backDate = backfillDates[i];

      if (await _isComplete(backDate)) {
        skippedDays++;
        onProgress?.call('法人回補 ${i + 1}/${backfillDates.length} 天');
        continue;
      }

      await Future.delayed(
        const Duration(milliseconds: ApiConfig.retryDelayMs),
      );

      try {
        await _institutionalRepo.syncAllMarketInstitutional(
          backDate,
          force: false,
        );
        syncedDays++;
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        final dateStr = '${backDate.month}/${backDate.day}';
        errors.add('法人資料回補失敗 ($dateStr): $e');
        AppLogger.warning('InstitutionalSyncer', '法人資料回補失敗 ($dateStr)', e);
      }

      onProgress?.call('法人回補 ${i + 1}/${backfillDates.length} 天');
    }

    if (skippedDays > 0) {
      AppLogger.debug('InstitutionalSyncer', '法人回補: $skippedDays 天已完整跳過（不睡不打）');
    }

    // 深回補完整跑完（迴圈未被限流/斷網 rethrow 打斷、零錯誤）才蓋章；
    // 有錯誤代表某些天沒補到，marker 留著讓下一輪續補。蓋章失敗只記
    // warning——下一輪多跑一次零成本的深窗預檢而已。
    if (deepPending && errors.isEmpty) {
      try {
        await _institutionalRepo.markDeepBackfillComplete();
        AppLogger.info('InstitutionalSyncer', '深回補完整跑完，恢復日常淺回補窗');
      } catch (e) {
        AppLogger.warning('InstitutionalSyncer', '深回補蓋章失敗（下輪重試）', e);
      }
    }

    AppLogger.info('InstitutionalSyncer', '法人資料同步完成: $syncedDays 天');

    return InstitutionalSyncResult(syncedDays: syncedDays, errors: errors);
  }

  /// 完整性預檢；查詢失敗視為缺漏（fail-open 朝抓取——寧可多抓一次
  /// 免費 API，不因 DB 讀取異常漏補）
  Future<bool> _isComplete(DateTime date) async {
    try {
      return await _institutionalRepo.isDayComplete(date);
    } catch (e) {
      AppLogger.warning('InstitutionalSyncer', '法人完整性預檢失敗，視為缺漏', e);
      return false;
    }
  }
}

/// 法人資料同步結果
class InstitutionalSyncResult {
  const InstitutionalSyncResult({
    required this.syncedDays,
    this.errors = const [],
  });

  final int syncedDays;
  final List<String> errors;

  /// 估計同步的資料筆數（每天約 [DataFreshness.estimatedDailyInstitutionalRecords] 檔）
  ///
  /// syncedDays 只計實際抓取的天（已完整的天由預檢跳過、不入計）。
  int get estimatedCount =>
      syncedDays * DataFreshness.estimatedDailyInstitutionalRecords;

  bool get hasErrors => errors.isNotEmpty;
}
