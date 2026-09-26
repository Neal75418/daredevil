// InstitutionalSyncer — force 同步的非破壞式重建
//
// 原行為：force 先 clearAllData 再重抓 62 個交易日（1s/日節流 ~2-3 分鐘）。
// 中斷（rate limit / 斷網 / 關 app）會留下殘缺深度，且日常更新只回補
// 15 個日曆天，補不回 62 天——連續買賣超、surge baseline（60 日）、
// Z-score 全失真，需再一次成功的 force 才能復原。
//
// 新行為：
// - 全清改由 [InstitutionalRepository.ensureDataVersion] 的口徑版本檢核
//   承接（只在版本變更時清一次），每次同步入口都檢核（日常更新也會遷移）
// - force 只對「當日」繞快取；歷史回補日一律 force:false 走 per-day
//   完整性檢查——已完整的天直接跳過，中斷後重跑只補缺的天（斷點續傳）
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/domain/services/update/institutional_syncer.dart';

class MockInstitutionalRepository extends Mock
    implements InstitutionalRepository {}

void main() {
  late MockInstitutionalRepository mockRepo;
  late InstitutionalSyncer syncer;

  // 2026-07-14（二）；backfillDays=4 → 回補窗只含 7/13（一），
  // 7/12（日）、7/11（六）非交易日跳過
  final date = DateTime(2026, 7, 14);
  final backfillDate = DateTime(2026, 7, 13);

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    mockRepo = MockInstitutionalRepository();
    syncer = InstitutionalSyncer(institutionalRepository: mockRepo);

    when(() => mockRepo.ensureDataVersion()).thenAnswer((_) async => false);
    when(() => mockRepo.isDeepBackfillPending()).thenAnswer((_) async => false);
    // 預設全缺漏（既有測試的行為前提）
    when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => false);
    when(
      () => mockRepo.syncAllMarketInstitutional(
        any(),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => 1000);
  });

  test('force 不再無條件 clearAllData；口徑檢核每次入口都跑', () async {
    await syncer.syncInstitutionalData(
      date: date,
      force: true,
      backfillDays: 4,
    );

    verifyNever(() => mockRepo.clearAllData());
    verify(() => mockRepo.ensureDataVersion()).called(1);
  });

  test('日常更新（force:false）也跑口徑檢核（app 升級後自動遷移）', () async {
    await syncer.syncInstitutionalData(
      date: date,
      force: false,
      backfillDays: 4,
    );

    verify(() => mockRepo.ensureDataVersion()).called(1);
  });

  test('force 只對當日繞快取；歷史回補日 force:false（斷點續傳）', () async {
    await syncer.syncInstitutionalData(
      date: date,
      force: true,
      backfillDays: 4,
    );

    verify(
      () => mockRepo.syncAllMarketInstitutional(date, force: true),
    ).called(1);
    verify(
      () => mockRepo.syncAllMarketInstitutional(backfillDate, force: false),
    ).called(1);
  });

  test('口徑檢核失敗不中斷同步（下次入口重試遷移）', () async {
    when(
      () => mockRepo.ensureDataVersion(),
    ).thenAnswer((_) async => throw const DatabaseException('settings 讀取失敗'));

    final result = await syncer.syncInstitutionalData(
      date: date,
      force: true,
      backfillDays: 4,
    );

    expect(result.syncedDays, 2); // 當日 + 7/13 照常同步
  });

  group('已完整天跳過（不睡不打）', () {
    test('穩態全完整：回補日不打 API、syncedDays 只計實際抓取', () async {
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);

      final result = await syncer.syncInstitutionalData(
        date: date,
        force: true,
        backfillDays: 4,
      );

      // 當日 force 必抓；7/13 已完整 → 完全不打
      verify(
        () => mockRepo.syncAllMarketInstitutional(date, force: true),
      ).called(1);
      verifyNever(
        () => mockRepo.syncAllMarketInstitutional(
          backfillDate,
          force: any(named: 'force'),
        ),
      );
      expect(result.syncedDays, 1);
    });

    test('部分缺漏：完整天跳過、缺漏天照抓', () async {
      when(
        () => mockRepo.isDayComplete(backfillDate),
      ).thenAnswer((_) async => true);
      when(
        () => mockRepo.isDayComplete(DateTime(2026, 7, 9)),
      ).thenAnswer((_) async => false);

      // backfillDays=6 → 交易日 7/13（完整）、7/9（缺漏）
      final result = await syncer.syncInstitutionalData(
        date: date,
        force: false,
        backfillDays: 6,
      );

      verifyNever(
        () => mockRepo.syncAllMarketInstitutional(
          backfillDate,
          force: any(named: 'force'),
        ),
      );
      verify(
        () => mockRepo.syncAllMarketInstitutional(
          DateTime(2026, 7, 9),
          force: false,
        ),
      ).called(1);
      expect(result.syncedDays, 2); // 當日 + 7/9
    });

    test('日常更新（!force）當日已完整也跳過（同晚二次更新 0 抓取）', () async {
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);

      final result = await syncer.syncInstitutionalData(
        date: date,
        force: false,
        backfillDays: 4,
      );

      verifyNever(
        () => mockRepo.syncAllMarketInstitutional(
          any(),
          force: any(named: 'force'),
        ),
      );
      expect(result.syncedDays, 0);
    });

    test('isDayComplete 失敗 → 當缺漏處理照抓（fail-open 朝抓取）', () async {
      when(
        () => mockRepo.isDayComplete(any()),
      ).thenAnswer((_) async => throw const DatabaseException('count 失敗'));

      final result = await syncer.syncInstitutionalData(
        date: date,
        force: true,
        backfillDays: 4,
      );

      verify(
        () => mockRepo.syncAllMarketInstitutional(backfillDate, force: false),
      ).called(1);
      expect(result.syncedDays, 2);
    });

    test('跳過的天仍發 onProgress（掃描進度語意）', () async {
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);
      final messages = <String>[];

      await syncer.syncInstitutionalData(
        date: date,
        force: false,
        backfillDays: 6,
        onProgress: messages.add,
      );

      expect(messages, ['法人回補 1/2 天', '法人回補 2/2 天']);
    });
  });

  test('onProgress 逐回補交易日回報，非交易日與颱風停市不計入分母', () async {
    final messages = <String>[];

    // backfillDays=6 → 窗含 7/13(一)、7/12(日)、7/11(六)、7/10(颱風停市)、
    // 7/9(四)——只有 7/13、7/9 是交易日
    await syncer.syncInstitutionalData(
      date: date,
      force: false,
      backfillDays: 6,
      onProgress: messages.add,
    );

    expect(messages, ['法人回補 1/2 天', '法人回補 2/2 天']);
  });

  test('未提供 onProgress 不影響同步', () async {
    final result = await syncer.syncInstitutionalData(
      date: date,
      force: false,
      backfillDays: 4,
    );

    expect(result.syncedDays, 2);
  });

  test('回補日 RateLimit 往上拋（UpdateService 據此止血）', () async {
    when(
      () => mockRepo.syncAllMarketInstitutional(backfillDate, force: false),
    ).thenAnswer((_) async => throw const RateLimitException('quota'));

    // await expectLater：unawaited 的 expect+throwsA 會在斷言執行前結束
    // 測試 body，失敗可能歸因到別的測試（review 抓到，全套慣例即此式）
    await expectLater(
      syncer.syncInstitutionalData(date: date, force: true, backfillDays: 4),
      throwsA(isA<RateLimitException>()),
    );
  });

  // 口徑遷移清空後的自我修復
  //
  // 實測（2026-07-26 正式 DB）：daily_institutional 全表只有 17 個交易日
  // （2026-07-01 ~ 07-24，2,100 檔中 1,729 檔恰好都是 17 天——硬牆），
  // 而 daily_price 有 275 個交易日（2025-06-10 起）。起點 2026-07-01 正好
  // 是 07-16 往回推 institutionalDailyBackfillDays(15) 個日曆天。
  //
  // 成因：ensureDataVersion() 在口徑版本變更時清空全表，清完只靠**當次
  // 那一輪**的回補窗重建。那一輪若是日常更新就只有 15 個日曆天（≈10 個
  // 交易日）。ensureDataVersion 回傳「有沒有清空」這個 bool，但呼叫端
  // 直接 `await ...;` 丟掉——系統剛算出「我需要深回補」就把結論扔了。
  //
  // 後果是靜默的：連續買賣超（institutionalStreakLookbackDays 90 日曆天）、
  // surge baseline（institutionalSurgeLookbackDays 60 日）全部在淺資料上
  // 運作，畫面不會說。本檔開頭的註解早就寫著「需再一次成功的 force 才能
  // 復原」，但沒有任何機制促成那次 force。
  //
  // 修法：清空當輪自動改用深窗。已完整的天走 per-day 檢查跳過（不睡不打），
  // 所以穩態下這條路徑不會被觸發，日常更新仍維持淺回補。
  group('口徑遷移清空後自動深回補', () {
    /// 全部標記為已完整 → 迴圈只探測不抓取，避免 1s/日的節流拖慢測試。
    /// 探測到的日期範圍即為實際回補窗。
    List<DateTime> probedDates() => verify(
      () => mockRepo.isDayComplete(captureAny()),
    ).captured.cast<DateTime>();

    setUp(() {
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);
    });

    test('🚨 清空當輪即使呼叫端傳淺窗，也必須回補到深窗', () async {
      when(() => mockRepo.ensureDataVersion()).thenAnswer((_) async => true);

      await syncer.syncInstitutionalData(
        date: date,
        force: false,
        backfillDays: ApiConfig.institutionalDailyBackfillDays,
      );

      final earliest = probedDates().reduce((a, b) => a.isBefore(b) ? a : b);
      expect(
        date.difference(earliest).inDays,
        greaterThanOrEqualTo(ApiConfig.institutionalForceBackfillDays - 7),
        reason:
            '剛清空全表就只補 ${ApiConfig.institutionalDailyBackfillDays} 個日曆天，'
            'streak(90 日曆天) 與 surge baseline(60 日) 會在淺資料上靜默失真；'
            'ensureDataVersion 已經回報了「清空了」，這個資訊不該被丟掉',
      );
    });

    test('沒清空時維持呼叫端指定的淺窗（日常更新不得因此變慢）', () async {
      when(() => mockRepo.ensureDataVersion()).thenAnswer((_) async => false);

      await syncer.syncInstitutionalData(
        date: date,
        force: false,
        backfillDays: ApiConfig.institutionalDailyBackfillDays,
      );

      final earliest = probedDates().reduce((a, b) => a.isBefore(b) ? a : b);
      expect(
        date.difference(earliest).inDays,
        lessThan(ApiConfig.institutionalDailyBackfillDays),
        reason: '穩態下每輪都掃 62 天會讓日常更新無謂變慢',
      );
    });
  });

  // ====================================================================
  // 深回補中斷自癒(2026-08-01 複審)
  //
  // 舊行為:migrated flag 是一次性的——遷移輪清空全表後若深回補(62 天)
  // 中途撞限流,下一輪 ensureDataVersion 回 false、回補窗退回日常 15 天,
  // 第 16~62 天的深度**永久缺失**且無任何機制促成補救(代碼自承)。
  // 新行為:遷移時落 pending marker,深回補完整跑完(零錯誤)才蓋章;
  // 未蓋章前每一輪都用深窗,per-day 完整性檢查讓已補的天零成本跳過。
  // ====================================================================
  group('深回補中斷自癒', () {
    setUp(() {
      when(() => mockRepo.markDeepBackfillComplete()).thenAnswer((_) async {});
    });

    test('🚨 pending 未蓋章:非遷移輪也用深回補窗(限流中斷後自癒)', () async {
      when(
        () => mockRepo.isDeepBackfillPending(),
      ).thenAnswer((_) async => true);
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);

      await syncer.syncInstitutionalData(date: date, backfillDays: 4);

      // 淺窗 4 曆天只預檢 ~2 個交易日;深窗 62 曆天 >30 個。
      // 已完整的天不睡不打,深窗在穩態下零 API 成本。
      final preChecks = verify(() => mockRepo.isDayComplete(any())).callCount;
      expect(
        preChecks,
        greaterThan(15),
        reason: 'pending 未蓋章時必須維持深回補窗,否則深度缺口永久化',
      );
    });

    test('深回補完整跑完且零錯誤 → 蓋章 markDeepBackfillComplete', () async {
      when(
        () => mockRepo.isDeepBackfillPending(),
      ).thenAnswer((_) async => true);
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);

      await syncer.syncInstitutionalData(date: date, backfillDays: 4);

      verify(() => mockRepo.markDeepBackfillComplete()).called(1);
    });

    test('深回補再撞限流 → 不蓋章,下一輪重試', () async {
      when(
        () => mockRepo.isDeepBackfillPending(),
      ).thenAnswer((_) async => true);
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => false);
      when(
        () => mockRepo.syncAllMarketInstitutional(
          any(),
          force: any(named: 'force'),
        ),
      ).thenThrow(const RateLimitException('quota'));

      await expectLater(
        syncer.syncInstitutionalData(date: date, backfillDays: 4),
        throwsA(isA<RateLimitException>()),
      );
      verifyNever(() => mockRepo.markDeepBackfillComplete());
    });

    test('穩態 pending=false:維持淺窗、不蓋章', () async {
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);

      await syncer.syncInstitutionalData(date: date, backfillDays: 4);

      final preChecks = verify(() => mockRepo.isDayComplete(any())).callCount;
      expect(preChecks, lessThan(6));
      verifyNever(() => mockRepo.markDeepBackfillComplete());
    });
  });
}
