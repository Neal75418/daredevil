// 定案規則：抓取時間的台北日期 > 資料日（spec §4.1）
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/market_day_finality.dart';

void main() {
  final day = DateTime(2026, 9, 24);

  test('同日 21:30 抓的不算定案（鉅額交易可能還沒併入）', () {
    expect(
      isFetchFinal(
        dataDate: day,
        fetchedAtTaipei: DateTime(2026, 9, 24, 21, 30),
      ),
      isFalse,
    );
  });

  test('同日 23:59:59 仍不算定案', () {
    expect(
      isFetchFinal(
        dataDate: day,
        fetchedAtTaipei: DateTime(2026, 9, 24, 23, 59, 59),
      ),
      isFalse,
    );
  });

  test('隔日 00:00 起算定案', () {
    expect(
      isFetchFinal(dataDate: day, fetchedAtTaipei: DateTime(2026, 9, 25)),
      isTrue,
    );
  });

  test('資料日帶時間成分時只看年月日', () {
    expect(
      isFetchFinal(
        dataDate: DateTime(2026, 9, 24, 8),
        fetchedAtTaipei: DateTime(2026, 9, 25, 0, 1),
      ),
      isTrue,
    );
  });

  test('抓取早於資料日（時鐘異常）不算定案', () {
    expect(
      isFetchFinal(dataDate: day, fetchedAtTaipei: DateTime(2026, 9, 23, 23)),
      isFalse,
    );
  });

  test('只比年月日欄位，不做時區換算（UTC 旗標的同一牆鐘值結果相同）', () {
    expect(
      isFetchFinal(
        dataDate: DateTime.utc(2026, 9, 24),
        fetchedAtTaipei: DateTime(2026, 9, 25, 0, 30),
      ),
      isTrue,
    );
    expect(
      isFetchFinal(
        dataDate: DateTime(2026, 9, 24),
        fetchedAtTaipei: DateTime.utc(2026, 9, 24, 23, 30),
      ),
      isFalse,
    );
  });
}
