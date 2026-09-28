import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/screens/institutional/institutional_ranking_screen.dart';

void main() {
  const zh = Locale('zh', 'TW');
  const en = Locale('en');

  group('formatRankingAmount（法人排行金額欄，顯示絕對值）', () {
    test('中文固定以億、一位小數（未滿 1 億也不降級）', () {
      expect(formatRankingAmount(153_000_000, zh), '1.5億');
      expect(formatRankingAmount(-50_000_000, zh), '0.5億');
    });

    test('英文走 K/M/B：1.53 億 = 153 million，不是 1.5 billion', () {
      expect(formatRankingAmount(153_000_000, en), '153.0M');
      expect(formatRankingAmount(-2_500_000_000, en), '2.5B');
    });
  });
}
