// 均線階梯提醒(2026-08-16)
//
// **它解決什麼**:提醒價位是死的,均線是活的。手動設的「跌破 5MA 通知」
// 過幾天就落在錯的位置——2026-08-16 重整 36 檔提醒時,舊設定全數落後於
// 當時的 5MA。做成按鈕只是把失效間隔縮短、靠人記得按;掛進每日更新才是
// 讓它永遠釘在狀態邊界上。
//
// **階梯語意**(單向、每檔恰好一個提醒):
//   站上 5MA  → BELOW 5MA   監控何時轉弱
//   破 5MA    → BELOW 20MA  監控趨勢是否崩壞
//   破 20MA   → ABOVE 20MA  等它何時轉強
//   破 60MA   → ABOVE 60MA  等它真的回來
//
// **最重要的不變量**:`managed_by IS NULL` 是使用者手動設的,自動流程
// 一列都不准動。那是加 `managed_by` 欄的唯一理由。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/alert/trailing_ma_alert_service.dart';

void main() {
  group('resolveTier(純函數):四階狀態機', () {
    test('站上 5MA → 跌破 5MA 示警', () {
      final tier = TrailingMaAlertService.resolveTier(
        price: 110,
        ma5: 105,
        ma20: 100,
        ma60: 95,
      );
      expect(tier!.alertType, AlertParams.typeBelow);
      expect(tier.target, 105);
    });

    test('恰好等於 5MA 仍算「站上」(邊界)', () {
      final tier = TrailingMaAlertService.resolveTier(
        price: 105,
        ma5: 105,
        ma20: 100,
        ma60: 95,
      );
      expect(tier!.target, 105, reason: '>= 為站上,與 2026-08-16 手動重整同語意');
    });

    test('破 5MA、守住月線 → 跌破月線示警', () {
      final tier = TrailingMaAlertService.resolveTier(
        price: 102,
        ma5: 105,
        ma20: 100,
        ma60: 95,
      );
      expect(tier!.alertType, AlertParams.typeBelow);
      expect(tier.target, 100);
    });

    test('破月線、守住季線 → 突破月線示警(方向翻轉)', () {
      final tier = TrailingMaAlertService.resolveTier(
        price: 97,
        ma5: 105,
        ma20: 100,
        ma60: 95,
      );
      expect(
        tier!.alertType,
        AlertParams.typeAbove,
        reason: '轉弱後改為等它轉強——這是階梯唯一的方向翻轉點',
      );
      expect(tier.target, 100);
    });

    test('破季線 → 突破季線示警', () {
      final tier = TrailingMaAlertService.resolveTier(
        price: 90,
        ma5: 105,
        ma20: 100,
        ma60: 95,
      );
      expect(tier!.alertType, AlertParams.typeAbove);
      expect(tier.target, 95);
    });

    test('🚨 均線資料不足時回 null,不得亂設提醒', () {
      // 破 5MA 但沒有 20MA:硬掛 BELOW 5MA 會立刻觸發(價格早就在線下),
      // 那是每天一則假通知,比沒有提醒更糟
      expect(
        TrailingMaAlertService.resolveTier(
          price: 102,
          ma5: 105,
          ma20: null,
          ma60: null,
        ),
        isNull,
      );
      expect(
        TrailingMaAlertService.resolveTier(
          price: 97,
          ma5: 105,
          ma20: 100,
          ma60: null,
        ),
        isNull,
        reason: '破月線卻不知道季線在哪,無法決定該等哪條線',
      );
    });

    test('只有 5MA 但站在線上仍可設(新股上市不必等 60 天)', () {
      final tier = TrailingMaAlertService.resolveTier(
        price: 110,
        ma5: 105,
        ma20: null,
        ma60: null,
      );
      expect(tier!.target, 105, reason: '第一階用不到 20/60MA');
    });
  });

  group('refresh():落庫行為', () {
    late AppDatabase db;
    late TrailingMaAlertService service;

    setUp(() async {
      db = AppDatabase.forTesting();
      service = TrailingMaAlertService(database: db);
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
        StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      ]);
    });
    tearDown(() async => db.close());

    /// 種 60 天價格:前 59 天都是 [base],最後一天是 [last]
    Future<void> seedPrices(
      String symbol, {
      double base = 100,
      required double last,
    }) async {
      for (var i = 0; i < 60; i++) {
        await db
            .into(db.dailyPrice)
            .insert(
              DailyPriceCompanion.insert(
                symbol: symbol,
                date: DateTime.utc(2026, 6, 1).add(Duration(days: i)),
                close: Value(i == 59 ? last : base),
                volume: const Value(1000),
              ),
            );
      }
    }

    Future<List<PriceAlertEntry>> alertsOf(String symbol) async {
      return (db.select(
        db.priceAlert,
      )..where((t) => t.symbol.equals(symbol))).get();
    }

    test('自選股站上均線 → 建立一筆 BELOW 5MA 的自動提醒', () async {
      await db.addToWatchlist('2330');
      await seedPrices('2330', last: 100); // 全平盤:ma5=ma20=ma60=100

      expect(await service.refresh(), 1);

      final alerts = await alertsOf('2330');
      expect(alerts, hasLength(1));
      expect(alerts.single.alertType, AlertParams.typeBelow);
      expect(alerts.single.targetValue, closeTo(100, 0.01));
      expect(alerts.single.managedBy, AlertParams.managedByTrailingMa);
      expect(alerts.single.isActive, isTrue);
    });

    test('🚨 手動提醒一列都不准動(加 managed_by 欄的唯一理由)', () async {
      await db.addToWatchlist('2330');
      await seedPrices('2330', last: 100);
      final manualId = await db
          .into(db.priceAlert)
          .insert(
            PriceAlertCompanion.insert(
              symbol: '2330',
              alertType: AlertParams.typeAbove,
              targetValue: 1234.5,
              note: const Value('手動設的關鍵壓力'),
              // managedBy 留空 = 手動
            ),
          );

      await service.refresh();

      final manual = await db.getAlertById(manualId);
      expect(manual, isNotNull, reason: '手動提醒不得被刪除');
      expect(manual!.targetValue, 1234.5, reason: '價位不得被改寫');
      expect(manual.note, '手動設的關鍵壓力');
      expect(await alertsOf('2330'), hasLength(2), reason: '自動提醒與手動提醒並存,互不干擾');
    });

    test('🚨 重跑是就地更新而非疊加(否則每天多一筆)', () async {
      await db.addToWatchlist('2330');
      await seedPrices('2330', last: 100);
      await service.refresh();
      final firstId = (await alertsOf('2330')).single.id;

      await service.refresh();
      await service.refresh();

      final alerts = await alertsOf('2330');
      expect(alerts, hasLength(1), reason: '每檔恰好一個自動提醒');
      expect(alerts.single.id, firstId, reason: '就地更新,保留同一列');
    });

    test('🚨 觸發過的自動提醒會在下次重算時重新武裝', () async {
      // consumeAlertClaim 觸發後把 is_active 設為 false。階梯提醒若不重新
      // 武裝就只會響一次——而它的用途正是持續追蹤狀態邊界。
      await db.addToWatchlist('2330');
      await seedPrices('2330', last: 100);
      await service.refresh();
      final id = (await alertsOf('2330')).single.id;
      await (db.update(db.priceAlert)..where((t) => t.id.equals(id))).write(
        PriceAlertCompanion(
          isActive: const Value(false),
          triggeredAt: Value(DateTime.utc(2026, 8, 15)),
        ),
      );

      await service.refresh();

      final alert = (await alertsOf('2330')).single;
      expect(alert.isActive, isTrue);
      expect(alert.triggeredAt, isNull, reason: '重新武裝後不應殘留舊觸發戳記');
    });

    test('狀態改變時提醒跟著換階(跌破後改監控月線)', () async {
      await db.addToWatchlist('2330');
      await seedPrices('2330', last: 100);
      await service.refresh();
      expect((await alertsOf('2330')).single.targetValue, closeTo(100, 0.01));

      // 隔天大跌到 80:ma5=(80+400)/5=96、ma20=(80+1900)/20=99、
      // ma60=(80+5900)/60≈99.67 → 三條線全破 → 等它突破季線
      await (db.delete(
        db.dailyPrice,
      )..where((t) => t.date.equals(DateTime.utc(2026, 7, 30)))).go();
      await db
          .into(db.dailyPrice)
          .insert(
            DailyPriceCompanion.insert(
              symbol: '2330',
              date: DateTime.utc(2026, 7, 30),
              close: const Value(80),
              volume: const Value(1000),
            ),
          );

      await service.refresh();

      final alert = (await alertsOf('2330')).single;
      expect(alert.alertType, AlertParams.typeAbove, reason: '方向翻轉為等轉強');
      expect(alert.targetValue, closeTo(99.67, 0.05), reason: '目標是季線');
    });

    test('移出自選股後自動提醒被清掉(手動的仍留著)', () async {
      await db.addToWatchlist('2330');
      await seedPrices('2330', last: 100);
      final manualId = await db
          .into(db.priceAlert)
          .insert(
            PriceAlertCompanion.insert(
              symbol: '2330',
              alertType: AlertParams.typeAbove,
              targetValue: 1234.5,
            ),
          );
      await service.refresh();
      expect(await alertsOf('2330'), hasLength(2));

      await db.removeFromWatchlist('2330');
      await service.refresh();

      final remaining = await alertsOf('2330');
      expect(remaining, hasLength(1));
      expect(remaining.single.id, manualId, reason: '只清自己標記過的');
    });

    test('價格資料不足的自選股被跳過,不影響其他檔', () async {
      await db.addToWatchlist('2330');
      await db.addToWatchlist('2317');
      await seedPrices('2330', last: 100);
      // 2317 只有 3 天,連 5MA 都算不出來
      for (var i = 0; i < 3; i++) {
        await db
            .into(db.dailyPrice)
            .insert(
              DailyPriceCompanion.insert(
                symbol: '2317',
                date: DateTime.utc(2026, 7, 1).add(Duration(days: i)),
                close: const Value(50),
                volume: const Value(1000),
              ),
            );
      }

      expect(await service.refresh(), 1, reason: '只有 2330 設得成');
      expect(await alertsOf('2317'), isEmpty);
    });

    test('自選股為空時安全 no-op', () async {
      expect(await service.refresh(), 0);
    });

    test('🚨 同一檔的重複自動提醒會被收斂成一筆', () async {
      // GUI 按鈕與 launchd CLI 跑在**兩個 process、同一個 SQLite**(本專案
      // 既有事實)。兩邊同時 refresh 時可能都讀到「還沒有」而各插一筆,之後
      // 每天各自更新、各自通知——而清理迴圈只掃「已非自選股」的列,永遠碰
      // 不到它。重複提醒會靜默留存,那正是這個專案反覆吃虧的形狀。
      await db.addToWatchlist('2330');
      await seedPrices('2330', last: 100);
      for (var i = 0; i < 3; i++) {
        await db.createPriceAlert(
          symbol: '2330',
          alertType: AlertParams.typeBelow,
          targetValue: 1.0 + i,
          managedBy: AlertParams.managedByTrailingMa,
        );
      }
      expect(await alertsOf('2330'), hasLength(3), reason: '前提:確實有重複');

      await service.refresh();

      final alerts = await alertsOf('2330');
      expect(alerts, hasLength(1), reason: '收斂成一筆');
      expect(
        alerts.single.targetValue,
        closeTo(100, 0.01),
        reason: '留下的那筆是新算的',
      );
    });
  });
}
