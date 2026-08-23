// FinMind 當沖解析 — fixture 為**未加工的實際 API 回應**
//
// 手寫 fixture 曾讓上櫃當沖的表判別法看起來可行、7 條測試全綠卻永遠選錯表
// （見 tpex_day_trading_live_payload_test）。這裡直接存實際回應。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/finmind/models.dart';

void main() {
  late List<Map<String, dynamic>> rows;

  setUpAll(() {
    final raw = File(
      'test/data/remote/fixtures/finmind_day_trading_6104.json',
    ).readAsStringSync();
    final body = jsonDecode(raw) as Map<String, dynamic>;
    expect(body['msg'], 'success', reason: 'fixture 本身必須是成功回應');
    rows = (body['data'] as List).cast<Map<String, dynamic>>();
    expect(rows, isNotEmpty, reason: 'fixture 空的話整組測試等於沒測');
  });

  test('解析實際回應', () {
    final parsed = rows.map(FinMindDayTrading.tryFromJson).nonNulls.toList();

    expect(parsed.length, rows.length, reason: '實際回應不該有解析失敗');
    final d = parsed.firstWhere((e) => e.date == '2026-08-18');
    expect(d.stockId, '6104');
    expect(d.volume, 78000);
    expect(d.buyAmount, 7154300);
    expect(d.sellAmount, 7148300);
  });

  test('🚨 Volume 為 0 是合法值，不得當成缺值跳過', () {
    // 當沖語意下 0 = 當日無當沖，與價格欄位的 0（停牌 sentinel）相反
    final parsed = FinMindDayTrading.tryFromJson({
      'stock_id': '6104',
      'date': '2026-08-20',
      'Volume': 0,
      'BuyAmount': 0,
      'SellAmount': 0,
    });

    expect(parsed, isNotNull);
    expect(parsed!.volume, 0);
  });

  test('缺數值欄位 → null（不得落 0）', () {
    for (final missing in ['Volume', 'BuyAmount', 'SellAmount']) {
      final json = <String, dynamic>{
        'stock_id': '6104',
        'date': '2026-08-20',
        'Volume': 1,
        'BuyAmount': 2,
        'SellAmount': 3,
      }..remove(missing);

      expect(
        FinMindDayTrading.tryFromJson(json),
        isNull,
        reason: '缺 $missing 時落 0 會讓比例算出假的低當沖',
      );
    }
  });

  test('缺 stock_id / date → null', () {
    expect(
      FinMindDayTrading.tryFromJson({
        'date': '2026-08-20',
        'Volume': 1,
        'BuyAmount': 2,
        'SellAmount': 3,
      }),
      isNull,
    );
    expect(
      FinMindDayTrading.tryFromJson({
        'stock_id': '6104',
        'Volume': 1,
        'BuyAmount': 2,
        'SellAmount': 3,
      }),
      isNull,
    );
  });
}
