// 注意股（ATTENTION）失效語意 — 逐日名單，不在最新名單即失效
//
// 2026-07-25 實測缺陷：`updateExpiredWarnings` 唯一失效條件是
// `disposal_end_date < now`，但 ATTENTION 的該欄恆為 NULL，SQL 三值邏輯下
// `NULL < ?` 永不為真 → 注意股一旦寫入就永久 is_active=1。使用者 DB 實測
// 437 筆 / 140 檔 active，當日真實名單只有 19 檔（121 檔幽靈），而
// `TRADING_WARNING_ATTENTION` 是 -15 分，直接把股票壓出推薦榜。
//
// ⚠️ 修法陷阱：表無 market 欄，若粗暴地「把舊日期全部失效」，在只同步上櫃
// 的情境（非交易日 TWSE 端點被跳過）會誤殺全部上市注意股。故失效必須
// **限定在本輪成功同步的市場**。以下測試釘住此不變量。
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  final d1 = DateTime(2026, 7, 23); // 舊名單日
  final d2 = DateTime(2026, 7, 24); // 新名單日

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(
        symbol: '2330',
        name: '台積電',
        market: MarketCode.twse,
      ),
      StockMasterCompanion.insert(
        symbol: '2317',
        name: '鴻海',
        market: MarketCode.twse,
      ),
      StockMasterCompanion.insert(
        symbol: '3088',
        name: '艾訊',
        market: MarketCode.tpex,
      ),
      StockMasterCompanion.insert(
        symbol: '8069',
        name: '元太',
        market: MarketCode.tpex,
      ),
    ]);
  });

  tearDown(() async => db.close());

  Future<void> seedAttention(List<String> symbols, DateTime date) async {
    await db.insertWarningData([
      for (final s in symbols)
        TradingWarningCompanion.insert(
          symbol: s,
          date: date,
          warningType: 'ATTENTION',
          isActive: const Value(true),
        ),
    ]);
  }

  Future<Set<String>> activeAttention() async {
    final rows = await db.getActiveWarningsByType('ATTENTION');
    return rows.map((r) => r.symbol).toSet();
  }

  group('注意股逐日名單失效', () {
    test('不在最新名單的注意股失效，名單內的維持生效', () async {
      await seedAttention(['2330', '2317', '3088'], d1);
      expect(await activeAttention(), {'2330', '2317', '3088'});

      // 7/24 名單只剩 2330（上市）與 3088（上櫃），兩市場都同步成功
      await seedAttention(['2330', '3088'], d2);
      await db.deactivateStaleAttentionWarnings(
        currentSymbols: {'2330', '3088'},
        syncedMarkets: {MarketCode.twse, MarketCode.tpex},
        syncDate: d2,
      );

      expect(await activeAttention(), {
        '2330',
        '3088',
      }, reason: '2317 已不在 7/24 名單，必須失效');
    });

    test('⚠️ 只同步上櫃時，上市注意股不得被誤殺', () async {
      await seedAttention(['2330', '2317', '3088'], d1);

      // 非交易日情境：TWSE 端點被跳過，只有 TPEx 拿到新名單（含 8069、不含 3088）
      await seedAttention(['8069'], d2);
      await db.deactivateStaleAttentionWarnings(
        currentSymbols: {'8069'},
        syncedMarkets: {MarketCode.tpex},
        syncDate: d2,
      );

      expect(
        await activeAttention(),
        {'2330', '2317', '8069'},
        reason: '上櫃 3088 不在新名單應失效；上市 2330/2317 未同步、必須原封不動',
      );
    });

    test('🚨 空名單一律不清（無法與「抓取失敗」區分）', () async {
      // TWSE/TPEx client 在解析失敗或 stat != 'OK' 時是 return [] 而非拋例外
      // （見 TwseClient.getTradingWarnings）→ 呼叫端收不到例外、誤判為同步成功。
      // 若把空清單當權威名單做 full-refresh，一次來源退化就清空整個市場的
      // 注意股旗標：-15 分整批消失、風險徽章不亮，而 run 仍是綠燈。
      await seedAttention(['3088', '8069'], d1);

      final n = await db.deactivateStaleAttentionWarnings(
        currentSymbols: const {},
        syncedMarkets: {MarketCode.tpex},
        syncDate: d2,
      );

      expect(n, 0);
      expect(await activeAttention(), {
        '3088',
        '8069',
      }, reason: '寧可舊旗標多留一天，也不能因來源退化清空整個市場');
    });

    test('不得誤傷 DISPOSAL（處置股走 disposalEndDate 期間語意）', () async {
      await db.insertWarningData([
        TradingWarningCompanion.insert(
          symbol: '2330',
          date: d1,
          warningType: 'DISPOSAL',
          disposalEndDate: Value(DateTime(2026, 8, 31)),
          isActive: const Value(true),
        ),
      ]);
      await seedAttention(['2317'], d1);
      await seedAttention(['3088'], d2);

      await db.deactivateStaleAttentionWarnings(
        currentSymbols: {'3088'},
        syncedMarkets: {MarketCode.twse, MarketCode.tpex},
        syncDate: d2,
      );

      final disposals = await db.getActiveWarningsByType('DISPOSAL');
      expect(disposals.map((r) => r.symbol), [
        '2330',
      ], reason: '處置股仍在處置期內，不得被注意股清理波及');
      expect(await activeAttention(), {'3088'});
    });

    test('同一檔連續多日上榜，只保留今日那列 active', () async {
      await seedAttention(['2330'], d1);
      await seedAttention(['2330'], d2);

      await db.deactivateStaleAttentionWarnings(
        currentSymbols: {'2330'},
        syncedMarkets: {MarketCode.twse},
        syncDate: d2,
      );

      final rows = await db.getActiveWarningsByType('ATTENTION');
      expect(
        rows.length,
        1,
        reason: '多筆 active 會讓讀取端 tie-break 取到過期的 reasonDescription',
      );
      expect(rows.single.date, d2);
    });

    test('🚨 DISPOSAL 的 NULL endDate 不得永久生效（同型 bug 掃除）', () async {
      // endDate 是 DateTime?：TWSE 改分隔符號、欄位位移或民國日期解析失敗都會
      // 讓它變 null（見 TwseClient._parseDisposalRow）。而 updateExpiredWarnings 的
      // `disposal_end_date < now` 對 NULL 恆不成立 → -50 分 + 三模式硬排除
      // **永久生效**，該股再也不會出現在任何推薦榜。
      await db.insertWarningData([
        TradingWarningCompanion.insert(
          symbol: '2330',
          date: DateTime(2026, 5, 1), // 遠早於容忍窗
          warningType: 'DISPOSAL',
          isActive: const Value(true),
        ),
        // 對照組：近期的 NULL endDate 仍保留（可能真的還在處置中）
        TradingWarningCompanion.insert(
          symbol: '2317',
          date: d2,
          warningType: 'DISPOSAL',
          isActive: const Value(true),
        ),
      ]);

      await db.updateExpiredWarnings(now: DateTime(2026, 7, 24));

      final active = (await db.getActiveWarningsByType(
        'DISPOSAL',
      )).map((r) => r.symbol).toSet();
      expect(active, {'2317'}, reason: '陳舊的 NULL endDate 處置必須失效，近期的保守保留');
    });

    test('🚨 同日名單縮減時，NOT IN 是唯一防線（date< 抓不到）', () async {
      // mutation testing 發現：把 `symbol NOT IN (...)` 拿掉後測試仍全綠——
      // 因為既有案例的舊列都是被 `date < syncDate` 順帶清掉。同日二次同步
      // （force 重整、6 小時視窗過期重跑）時當日列的 date == syncDate，
      // `date <` 為 false，只有 NOT IN 能讓已下架的股票失效。
      await seedAttention(['2330', '2317'], d2);

      // 同一天稍後重跑：2317 已從名單下架
      await db.deactivateStaleAttentionWarnings(
        currentSymbols: {'2330'},
        syncedMarkets: {MarketCode.twse},
        syncDate: d2,
      );

      expect(await activeAttention(), {
        '2330',
      }, reason: '同日重跑時 date< 無效，2317 必須靠 NOT IN 失效');
    });

    test('未同步任何市場時為 no-op', () async {
      await seedAttention(['2330', '3088'], d1);

      final n = await db.deactivateStaleAttentionWarnings(
        currentSymbols: const {},
        syncedMarkets: const {},
        syncDate: d2,
      );

      expect(n, 0);
      expect(await activeAttention(), {'2330', '3088'});
    });
  });
}
