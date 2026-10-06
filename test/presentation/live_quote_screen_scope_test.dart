import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 掃描、今日訊號的 StockCard 不帶即時報價(spec §7「其他使用 StockCard 的
/// 畫面」):即使報價中心已有該檔報價,仍顯示資料庫的值。今日頁大盤列的
/// 指數在第 3 段另行登記,不在此限。
void main() {
  test('🚨 掃描、今日訊號不使用自選的即時價格與卡片即時資料', () {
    final files = [
      for (final dir in [
        'lib/presentation/screens/scan',
        'lib/presentation/screens/today',
      ])
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ];
    expect(files.length, greaterThan(5), reason: 'sanity:目錄有檔案');
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final banned in [
        'StockCardLive',
        'watchlistLivePriceProvider',
        'WatchlistLiveView',
      ]) {
        expect(src.contains(banned), isFalse, reason: '${f.path} 用了 $banned');
      }
    }
  });
}
