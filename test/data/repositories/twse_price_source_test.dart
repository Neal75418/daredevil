// TwsePriceSource 逐月錯誤吞噬的回歸測試(2026-08-14 審查發現)
//
// 背景:fetchMonthlyPrices 對非 RateLimit/Network 錯誤逐月吞掉——單月失敗
// 換部分資料是對的,但「全部月份都失敗」也回空清單就危險:上游
// HistoricalPriceSyncer 會把空結果記成「成功但覆蓋無成長」蓋 30 天退避章。
// TWSE 格式變更/WAF 擋掉的一個晚上,就能讓整批上市股靜默凍結一個月
// (本專案 2026-06 STOCK_DAY_ALL 改 CSV 靜默失效有前科)。
//
// 政策:全滅 → 拋 DatabaseException(進 failedSymbols,不進退避記帳);
// 部分成功 → 維持現狀回部分資料。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/models/twse/twse_daily_price.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/twse_price_source.dart';

class MockTwseClient extends Mock implements TwseClient {}

void main() {
  late MockTwseClient client;
  late TwsePriceSource source;

  setUp(() {
    client = MockTwseClient();
    source = TwsePriceSource(client: client);
  });

  final months = [DateTime(2026, 6, 1), DateTime(2026, 7, 1)];
  final start = DateTime(2026, 6, 1);
  final end = DateTime(2026, 7, 31);

  TwseDailyPrice price(DateTime date) => TwseDailyPrice(
    date: date,
    code: '2330',
    name: 'TSMC',
    open: 1000,
    high: 1010,
    low: 990,
    close: 1005,
    volume: 30000,
    change: 5,
  );

  test('🚨 全部月份都拋錯 → 拋 DatabaseException 而非靜默回空清單', () async {
    when(
      () => client.getStockMonthlyPrices(
        code: any(named: 'code'),
        year: any(named: 'year'),
        month: any(named: 'month'),
      ),
    ).thenThrow(const ApiException('TWSE 格式變更', 500));

    await expectLater(
      source.fetchMonthlyPrices(
        symbol: '2330',
        months: months,
        startDate: start,
        endDate: end,
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('部分月份失敗 → 回成功月份的資料,不拋錯', () async {
    when(
      () => client.getStockMonthlyPrices(
        code: any(named: 'code'),
        year: any(named: 'year'),
        month: 6,
      ),
    ).thenThrow(const ApiException('單月故障', 500));
    when(
      () => client.getStockMonthlyPrices(
        code: any(named: 'code'),
        year: any(named: 'year'),
        month: 7,
      ),
    ).thenAnswer((_) async => [price(DateTime(2026, 7, 15))]);

    final result = await source.fetchMonthlyPrices(
      symbol: '2330',
      months: months,
      startDate: start,
      endDate: end,
    );
    expect(result, hasLength(1));
  });

  test('全部月份成功但無資料(上市前)→ 回空清單,不拋錯', () async {
    when(
      () => client.getStockMonthlyPrices(
        code: any(named: 'code'),
        year: any(named: 'year'),
        month: any(named: 'month'),
      ),
    ).thenAnswer((_) async => const []);

    final result = await source.fetchMonthlyPrices(
      symbol: '2330',
      months: months,
      startDate: start,
      endDate: end,
    );
    expect(result, isEmpty);
  });

  test('RateLimitException 直接 rethrow 不被全滅判定攔截', () async {
    when(
      () => client.getStockMonthlyPrices(
        code: any(named: 'code'),
        year: any(named: 'year'),
        month: any(named: 'month'),
      ),
    ).thenThrow(const RateLimitException('限流'));

    await expectLater(
      source.fetchMonthlyPrices(
        symbol: '2330',
        months: months,
        startDate: start,
        endDate: end,
      ),
      throwsA(isA<RateLimitException>()),
    );
  });
}
