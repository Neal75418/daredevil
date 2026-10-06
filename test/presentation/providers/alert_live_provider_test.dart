import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/alert_live_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';

PriceAlertEntry _alert(int id, String symbol) => PriceAlertEntry(
  id: id,
  symbol: symbol,
  alertType: 'BELOW',
  targetValue: 100,
  isActive: true,
  createdAt: DateTime(2026, 10, 1),
);

/// 全域提醒頁的登記規則(2026-10-06,路線圖第 2 項)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);

  test('🚨 「已有今天正式資料」看最新一筆的日期(收盤後據此決定要不要抓收盤報價)', () {
    final state = PriceAlertState(
      alerts: [_alert(1, '2330'), _alert(2, '2317')],
      stockMarkets: const {'2330': 'TWSE', '2317': 'TWSE'},
      latestPrices: {
        '2330': DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 10, 6),
          close: 880,
        ),
        '2317': DailyPriceEntry(
          symbol: '2317',
          date: DateTime(2026, 10, 5),
          close: 200,
        ),
      },
    );
    expect(alertRegistrations(state, morning), const [
      LiveQuoteRegistration(
        symbol: '2330',
        market: 'TWSE',
        hasOfficialToday: true,
      ),
      LiveQuoteRegistration(symbol: '2317', market: 'TWSE'),
    ]);
  });

  test('🚨 主檔已停用(下市)的不登記——提醒永遠不會觸發,抓了也沒有報價', () {
    final state = PriceAlertState(
      alerts: [_alert(1, '2330'), _alert(2, '1234')],
      stockMarkets: const {'2330': 'TWSE', '1234': 'TWSE'},
      unmonitorableSymbols: const {'1234'},
    );
    expect(alertWatchedSymbols(state), ['2330']);
  });
}
