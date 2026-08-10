// IndustryRankingService.rankRotation — 族群「轉向」偵測(2026-08-11)
//
// **為什麼需要**:既有排行只有 20日/5日 兩個**水準值**,而資金轉向是
// **變化率**。2026-08-10 實測:半導體 20日排第 34(−13.6%)、5日排第 1
// (+7.2%)——單看任一個窗口都看不出它正在變成主流。躍升 +33 名才是訊號。
//
// **為什麼要分類**:排名躍升在崩跌後會系統性地把「跌最深」的族群排到最
// 前面。半導體是**跌深反彈**,不是**持續強勢**——兩者對應 v3.4 的結構 A
// 與結構 B,進場邏輯完全不同,不能混為一談。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/industry_ranking.dart';
import 'package:daredevil/domain/services/analysis/industry_ranking_service.dart';

import '../../../helpers/price_data_generators.dart';

void main() {
  final service = IndustryRankingService();

  /// 造一組 21 筆日線,可分別指定 20 日與 5 日報酬。
  ///
  /// 索引 0 最舊、20 最新。5 日報酬 = 最新 / 倒數第 6。
  List<DailyPriceEntry> history(
    String symbol, {
    required double ret20,
    required double ret5,
    double dailyVolume = 5_000_000, // 5,000 張
  }) {
    final start = DateTime(2026, 6, 1);
    const base = 100.0;
    final last = base * (1 + ret20 / 100);
    final sixthFromLast = last / (1 + ret5 / 100);
    return List.generate(21, (i) {
      final close = switch (i) {
        20 => last,
        15 => sixthFromLast,
        _ => i > 15 ? sixthFromLast : base,
      };
      return createTestPrice(
        symbol: symbol,
        date: start.add(Duration(days: i)),
        close: close,
        volume: dailyVolume,
      );
    });
  }

  group('排名躍升', () {
    test('🚨 20日弱、5日強 → 正躍升;20日強、5日弱 → 負躍升', () {
      // 甲族群:20日 −13%、5日 +7%(半導體今日的形狀)
      // 乙族群:20日 +1%、5日 −2%(金融保險今日的形狀)
      final result = service.rankRotation(
        priceHistories: {
          for (var i = 0; i < 5; i++)
            'A$i': history('A$i', ret20: -13, ret5: 7),
          for (var i = 0; i < 5; i++) 'B$i': history('B$i', ret20: 1, ret5: -2),
        },
        industries: {
          for (var i = 0; i < 5; i++) 'A$i': '甲',
          for (var i = 0; i < 5; i++) 'B$i': '乙',
        },
        names: const {},
      );

      final a = result.firstWhere((r) => r.industry == '甲');
      final b = result.firstWhere((r) => r.industry == '乙');
      expect(a.rankJump, greaterThan(0), reason: '20日墊底、5日居首 → 正躍升');
      expect(b.rankJump, lessThan(0), reason: '20日居首、5日墊底 → 負躍升');
      expect(result.first.industry, '甲', reason: '依躍升由大到小排序');
    });
  });

  group('分類', () {
    test('🚨 5日強 + 20日弱 = 跌深反彈(不是持續強勢)', () {
      final result = service.rankRotation(
        priceHistories: {
          for (var i = 0; i < 5; i++)
            'A$i': history('A$i', ret20: -13, ret5: 7),
          for (var i = 0; i < 5; i++) 'B$i': history('B$i', ret20: 1, ret5: -2),
          for (var i = 0; i < 5; i++) 'C$i': history('C$i', ret20: -5, ret5: 0),
        },
        industries: {
          for (var i = 0; i < 5; i++) 'A$i': '甲',
          for (var i = 0; i < 5; i++) 'B$i': '乙',
          for (var i = 0; i < 5; i++) 'C$i': '丙',
        },
        names: const {},
      );
      expect(
        result.firstWhere((r) => r.industry == '甲').category,
        RotationCategory.reboundFromDeep,
        reason:
            '5日第一但 20日墊底 → 跌深反彈。若標成「持續強勢」會讓使用者'
            '以為它符合強者榜(月漲>15%),實際完全相反',
      );
    });

    test('🚨 兩個窗口都強 = 持續強勢', () {
      final result = service.rankRotation(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'A$i': history('A$i', ret20: 25, ret5: 8),
          for (var i = 0; i < 5; i++)
            'B$i': history('B$i', ret20: -10, ret5: -3),
          for (var i = 0; i < 5; i++) 'C$i': history('C$i', ret20: 0, ret5: 0),
        },
        industries: {
          for (var i = 0; i < 5; i++) 'A$i': '甲',
          for (var i = 0; i < 5; i++) 'B$i': '乙',
          for (var i = 0; i < 5; i++) 'C$i': '丙',
        },
        names: const {},
      );
      expect(
        result.firstWhere((r) => r.industry == '甲').category,
        RotationCategory.sustained,
      );
    });

    test('20日強、5日弱 = 退燒', () {
      final result = service.rankRotation(
        priceHistories: {
          for (var i = 0; i < 5; i++)
            'A$i': history('A$i', ret20: 20, ret5: -5),
          for (var i = 0; i < 5; i++)
            'B$i': history('B$i', ret20: -10, ret5: 8),
          for (var i = 0; i < 5; i++) 'C$i': history('C$i', ret20: 0, ret5: 0),
        },
        industries: {
          for (var i = 0; i < 5; i++) 'A$i': '甲',
          for (var i = 0; i < 5; i++) 'B$i': '乙',
          for (var i = 0; i < 5; i++) 'C$i': '丙',
        },
        names: const {},
      );
      expect(
        result.firstWhere((r) => r.industry == '甲').category,
        RotationCategory.cooling,
      );
    });
  });

  group('強者榜成員數(決定卡片要不要淡化)', () {
    test('🚨 月漲>15% + 日均量>3000張 才算數', () {
      final result = service.rankRotation(
        priceHistories: {
          // 過:月漲 20%、量 5,000 張
          'P1': history('P1', ret20: 20, ret5: 3),
          // 不過:月漲 20% 但量只有 1,000 張
          'P2': history('P2', ret20: 20, ret5: 3, dailyVolume: 1_000_000),
          // 不過:量夠但月漲只有 10%
          'P3': history('P3', ret20: 10, ret5: 3),
          'P4': history('P4', ret20: 10, ret5: 3),
          'P5': history('P5', ret20: 10, ret5: 3),
        },
        industries: {for (var i = 1; i <= 5; i++) 'P$i': '甲'},
        names: const {},
      );
      expect(
        result.single.strongListCount,
        1,
        reason: '只有 P1 同時滿足月漲>15% 與日均量>3000張',
      );
    });

    test('強者榜 0 檔仍要回報(UI 靠它決定淡化,不可直接濾掉)', () {
      final result = service.rankRotation(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'A$i': history('A$i', ret20: 2, ret5: 1),
        },
        industries: {for (var i = 0; i < 5; i++) 'A$i': '甲'},
        names: const {},
      );
      expect(result.single.strongListCount, 0);
      expect(result.length, 1, reason: '0 檔不代表要從清單移除——躍升本身仍是資訊');
    });
  });

  test('🚨 族群數超過 rank() 的前 N 上限時,不可只比對前 N', () {
    // 2026-08-11 實機事故:`rank()` 最後 `.take(rankingTopN)` 砍到 12 名,
    // 而 rankRotation 拿兩個「前 12」去比對 → **交集只剩 1 個族群**。
    // 真實資料下 20日 前 12 全是傳產、5日 前 12 全是電子,幾乎不重疊。
    //
    // 這個 bug 單元測試抓不到:先前的測試只有 2~3 個族群,永遠碰不到上限。
    // 是拿真實 DB 跑一次才現形的——所以這條刻意造 20 個族群。
    const n = 20;
    final histories = <String, List<DailyPriceEntry>>{};
    final inds = <String, String>{};
    for (var g = 0; g < n; g++) {
      // 20日報酬遞減、5日報酬遞增 → 兩個排名幾乎完全相反
      for (var m = 0; m < 5; m++) {
        final sym = 'G${g}_$m';
        histories[sym] = history(sym, ret20: 20.0 - g, ret5: g.toDouble());
        inds[sym] = '族群$g';
      }
    }
    final result = service.rankRotation(
      priceHistories: histories,
      industries: inds,
      names: const {},
    );
    expect(result.length, n, reason: '$n 個族群全部都要在,不可被 rank() 的前 12 名上限截斷');
  });

  test('成員數不足門檻的族群不列入(與 rank() 同口徑)', () {
    final result = service.rankRotation(
      priceHistories: {'A1': history('A1', ret20: 20, ret5: 5)},
      industries: const {'A1': '甲'},
      names: const {},
    );
    expect(result, isEmpty);
  });

  test('ETF 排除(與 rank() 同口徑)', () {
    final result = service.rankRotation(
      priceHistories: {
        for (var i = 0; i < 5; i++) 'E$i': history('E$i', ret20: 20, ret5: 5),
      },
      industries: {for (var i = 0; i < 5; i++) 'E$i': 'ETF'},
      names: const {},
    );
    expect(result, isEmpty);
  });
}
