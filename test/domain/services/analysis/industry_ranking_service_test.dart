// IndustryRankingService — 族群排行（使用者選股法則 L1 的自動化）
//
// L1「族群決定 80%」：輪動前段＋法人買超。本服務由個股 20D 報酬聚合各
// 產業動能（中位數，與 computeIndustryMomentum 同口徑）、加上外資+投信
// 近 3 交易日合計淨買賣，輸出排行供今日頁族群 section 顯示。
// 純顯示/發現層，不進評分（sector tilt 已因全期 IC≈0 dormant，見
// SectorParams.tiltWeight doc——那是評分因子的結論，不影響資訊呈現）。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/industry_ranking.dart';
import 'package:daredevil/domain/services/analysis/industry_ranking_service.dart';

import '../../../helpers/price_data_generators.dart';

void main() {
  final service = IndustryRankingService();

  /// [ret20Pct]% 的 21 筆日線（首筆 100、尾筆 100*(1+ret/100)，中間持平首值）
  List<DailyPriceEntry> historyWithRet20(String symbol, double ret20Pct) {
    final start = DateTime(2026, 6, 1);
    return List.generate(21, (i) {
      final isLast = i == 20;
      return createTestPrice(
        symbol: symbol,
        date: start.add(Duration(days: i)),
        close: isLast ? 100 * (1 + ret20Pct / 100) : 100.0,
      );
    });
  }

  DailyInstitutionalEntry inst(
    String symbol,
    DateTime date, {
    double? foreign,
    double? trust,
  }) {
    return DailyInstitutionalEntry(
      symbol: symbol,
      date: date,
      foreignNet: foreign,
      investmentTrustNet: trust,
    );
  }

  test('🚨 上市「金融保險」與上櫃「金融業」必須合併為同一族群', () {
    // 2026-08-13「今日」tab 首日實測:全部產業裡唯一的跨市場異名對,
    // 兩組分開排竟包辦第 1、2 名——同一個板塊被標籤拆成兩行。
    // 更陰險的是 min-5 門檻:各自不足 5 檔時**兩邊都整組隱形**。
    final result = service.rank(
      priceHistories: {
        for (var i = 0; i < 3; i++) 'F$i': historyWithRet20('F$i', 5),
        for (var i = 0; i < 2; i++) 'G$i': historyWithRet20('G$i', 5),
      },
      industries: {
        for (var i = 0; i < 3; i++) 'F$i': '金融保險',
        for (var i = 0; i < 2; i++) 'G$i': '金融業',
      },
      names: const {},
      institutionalHistories: const {},
    );
    expect(result, hasLength(1), reason: '3+2 合併=5 檔過門檻;分裂則兩組都 <5 全隱形');
    expect(result.single.memberCount, 5);
  });

  test('🚨 RankingWindow.minHistoryRows:大盤同窗報酬取第 N 筆前收盤,差一格=超額系統性偏移', () {
    expect(RankingWindow.d20.minHistoryRows, 21);
    expect(RankingWindow.d5.minHistoryRows, 6);
    expect(RankingWindow.d1.minHistoryRows, 2);
  });

  group('RankingWindow.d1 今日視窗(2026-08-13 產業表現區塊合併進族群排行)', () {
    // 造 2 筆:昨收 100、今收依 ret1 指定
    List<DailyPriceEntry> historyWithRet1(String symbol, double ret1Pct) => [
      createTestPrice(
        symbol: symbol,
        date: DateTime(2026, 8, 11),
        close: 100.0,
      ),
      createTestPrice(
        symbol: symbol,
        date: DateTime(2026, 8, 12),
        close: 100 * (1 + ret1Pct / 100),
      ),
    ];

    test('🚨 d1 用當日報酬的中位數排序(口徑與 20日/5日 一致)', () {
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'A$i': historyWithRet1('A$i', 3.0),
          for (var i = 0; i < 5; i++) 'B$i': historyWithRet1('B$i', -1.0),
        },
        industries: {
          for (var i = 0; i < 5; i++) 'A$i': '甲',
          for (var i = 0; i < 5; i++) 'B$i': '乙',
        },
        names: const {},
        institutionalHistories: const {},
        window: RankingWindow.d1,
      );

      expect(rankings.first.industry, '甲');
      expect(rankings.first.momentumPct, closeTo(3.0, 0.001));
      expect(rankings.last.industry, '乙');
      expect(rankings.last.momentumPct, closeTo(-1.0, 0.001));
    });

    test('僅 1 筆歷史(算不出當日報酬)的成員不列入', () {
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'A$i': historyWithRet1('A$i', 2.0),
          'X1': [
            createTestPrice(
              symbol: 'X1',
              date: DateTime(2026, 8, 12),
              close: 50,
            ),
          ],
        },
        industries: {for (var i = 0; i < 5; i++) 'A$i': '甲', 'X1': '甲'},
        names: const {},
        institutionalHistories: const {},
        window: RankingWindow.d1,
      );

      expect(rankings.single.memberCount, 5, reason: 'X1 無昨收,不進分母');
    });

    test('成員數門檻與 ETF 排除跟其他視窗同口徑', () {
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 4; i++) 'A$i': historyWithRet1('A$i', 2.0),
          for (var i = 0; i < 5; i++) 'E$i': historyWithRet1('E$i', 9.0),
        },
        industries: {
          for (var i = 0; i < 4; i++) 'A$i': '甲',
          for (var i = 0; i < 5; i++) 'E$i': 'ETF',
        },
        names: const {},
        institutionalHistories: const {},
        window: RankingWindow.d1,
      );

      expect(rankings, isEmpty, reason: '甲只有 4 檔不足門檻,ETF 整組排除');
    });
  });

  group('IndustryRankingService.rank', () {
    test('依產業動能中位數 DESC 排序；成員 20D 報酬與名稱正確', () {
      final rankings = service.rank(
        priceHistories: {
          'A1': historyWithRet20('A1', 10),
          'A2': historyWithRet20('A2', 15),
          'A3': historyWithRet20('A3', 20),
          'A4': historyWithRet20('A4', 25),
          'A5': historyWithRet20('A5', 30),
          'B1': historyWithRet20('B1', 1.0),
          'B2': historyWithRet20('B2', 1.5),
          'B3': historyWithRet20('B3', 2.0),
          'B4': historyWithRet20('B4', 2.5),
          'B5': historyWithRet20('B5', 3.0),
        },
        industries: {
          'A1': '半導體業',
          'A2': '半導體業',
          'A3': '半導體業',
          'A4': '半導體業',
          'A5': '半導體業',
          'B1': '紡織業',
          'B2': '紡織業',
          'B3': '紡織業',
          'B4': '紡織業',
          'B5': '紡織業',
        },
        names: {'A5': '甲五'},
        institutionalHistories: const {},
      );

      expect(rankings, hasLength(2));
      expect(rankings[0].industry, '半導體業');
      expect(rankings[0].momentumPct, closeTo(20.0, 1e-6)); // 中位數
      expect(rankings[0].memberCount, 5);
      expect(rankings[1].industry, '紡織業');
      expect(rankings[1].momentumPct, closeTo(2.0, 1e-6));
      // topMembers 依 20D 報酬 DESC
      expect(rankings[0].topMembers.map((m) => m.symbol).toList(), [
        'A5',
        'A4',
        'A3',
        'A2',
        'A1',
      ]);
      expect(rankings[0].topMembers.first.name, '甲五');
      expect(rankings[0].topMembers.first.retPct, closeTo(30.0, 1e-6));
    });

    test('ETF 產業（含「ETF」字樣）與無產業股票不進排行', () {
      final rankings = service.rank(
        priceHistories: {
          'E1': historyWithRet20('E1', 50),
          'E2': historyWithRet20('E2', 50),
          'E3': historyWithRet20('E3', 50),
          'F1': historyWithRet20('F1', 50),
          'N1': historyWithRet20('N1', 50),
        },
        industries: {
          'E1': 'ETF',
          'E2': 'ETF',
          'E3': 'ETF',
          'F1': '上櫃ETF',
          'N1': null,
        },
        names: const {},
        institutionalHistories: const {},
      );

      expect(rankings, isEmpty);
    });

    test('成員不足 rankingMinMembers 的產業不進排行（實例：農業科技業 4 檔小樣本）', () {
      // 比門檻少 1 檔——2026-07-22 實機看到 4 檔小樣本（兩漲兩跌拼出的
      // 中位數無代表性）後，門檻從 3 調到 5
      const memberCount = SectorParams.rankingMinMembers - 1;
      final rankings = service.rank(
        priceHistories: {
          for (var m = 0; m < memberCount; m++)
            'A$m': historyWithRet20('A$m', 10.0 * m),
        },
        industries: {for (var m = 0; m < memberCount; m++) 'A$m': '農業科技業'},
        names: const {},
        institutionalHistories: const {},
      );

      expect(rankings, isEmpty);
    });

    test('歷史不足 21 筆的成員不計入動能與成員數', () {
      final short = historyWithRet20('A6', 99).sublist(0, 10);
      final rankings = service.rank(
        priceHistories: {
          'A1': historyWithRet20('A1', 10),
          'A2': historyWithRet20('A2', 15),
          'A3': historyWithRet20('A3', 20),
          'A4': historyWithRet20('A4', 25),
          'A5': historyWithRet20('A5', 30),
          'A6': short,
        },
        industries: {
          'A1': '半導體業',
          'A2': '半導體業',
          'A3': '半導體業',
          'A4': '半導體業',
          'A5': '半導體業',
          'A6': '半導體業',
        },
        names: const {},
        institutionalHistories: const {},
      );

      expect(rankings, hasLength(1));
      expect(rankings[0].memberCount, 5);
      expect(rankings[0].momentumPct, closeTo(20.0, 1e-6));
    });

    test('法人合計 = 外資+投信、只取近 rankingInstitutionalDays 個交易日', () {
      final d = DateTime(2026, 7, 20);
      final rankings = service.rank(
        priceHistories: {
          'A1': historyWithRet20('A1', 10),
          'A2': historyWithRet20('A2', 15),
          'A3': historyWithRet20('A3', 20),
          'A4': historyWithRet20('A4', 25),
          'A5': historyWithRet20('A5', 30),
        },
        industries: {
          'A1': '半導體業',
          'A2': '半導體業',
          'A3': '半導體業',
          'A4': '半導體業',
          'A5': '半導體業',
        },
        names: const {},
        institutionalHistories: {
          'A1': [
            // 第 4 個交易日（最舊）不得計入
            inst('A1', d.subtract(const Duration(days: 3)), foreign: 999999),
            inst('A1', d.subtract(const Duration(days: 2)), foreign: 1000),
            inst(
              'A1',
              d.subtract(const Duration(days: 1)),
              foreign: 2000,
              trust: 500,
            ),
            inst('A1', d, foreign: 3000),
          ],
          'A2': [
            inst('A2', d, foreign: null, trust: null), // null 視為 0
          ],
        },
      );

      expect(SectorParams.rankingInstitutionalDays, 3);
      expect(rankings.single.institutionalNetShares, closeTo(6500.0, 1e-6));
    });

    test('產業數超過 rankingTopN → 只取前 N', () {
      final priceHistories = <String, List<DailyPriceEntry>>{};
      final industries = <String, String?>{};
      for (var g = 0; g < SectorParams.rankingTopN + 2; g++) {
        for (var m = 0; m < SectorParams.rankingMinMembers; m++) {
          final symbol = 'G${g}M$m';
          priceHistories[symbol] = historyWithRet20(symbol, g.toDouble());
          industries[symbol] = '產業$g';
        }
      }
      final rankings = service.rank(
        priceHistories: priceHistories,
        industries: industries,
        names: const {},
        institutionalHistories: const {},
      );

      expect(rankings, hasLength(SectorParams.rankingTopN));
      expect(rankings.first.industry, '產業${SectorParams.rankingTopN + 1}');
    });

    test('topMembers 上限 rankingTopMembersCount', () {
      final priceHistories = <String, List<DailyPriceEntry>>{};
      final industries = <String, String?>{};
      for (var m = 0; m < SectorParams.rankingTopMembersCount + 3; m++) {
        final symbol = 'M$m';
        priceHistories[symbol] = historyWithRet20(symbol, m.toDouble());
        industries[symbol] = '半導體業';
      }
      final rankings = service.rank(
        priceHistories: priceHistories,
        industries: industries,
        names: const {},
        institutionalHistories: const {},
      );

      expect(
        rankings.single.topMembers,
        hasLength(SectorParams.rankingTopMembersCount),
      );
    });

    test('空輸入 → 空排行', () {
      expect(
        service.rank(
          priceHistories: const {},
          industries: const {},
          names: const {},
          institutionalHistories: const {},
        ),
        isEmpty,
      );
    });

    test('window=d5 → 用 5 日報酬排序（轉折族群視角）', () {
      // 半導體：20日跌但近5日翻強；紡織：20日漲但近5日走平
      // 收盤序列（21 筆）：半導體 前 16 筆 100→尾 5 筆拉到 108（20日 +8%、
      // 5日 +8%）...直接構造兩組序列驗證兩種 window 排序互換。
      List<DailyPriceEntry> seq(String symbol, List<double> closes) {
        final start = DateTime(2026, 6, 1);
        return [
          for (var i = 0; i < closes.length; i++)
            createTestPrice(
              symbol: symbol,
              date: start.add(Duration(days: i)),
              close: closes[i],
            ),
        ];
      }

      // 電子型：起點 120 一路跌到 100、最後 5 根反彈到 110
      // → 20日 = (110-120)/120 = -8.3%、5日 = (110-100)/100 = +10%
      final bounce = [
        120.0,
        ...List.filled(14, 105.0),
        100.0,
        102.0,
        104.0,
        106.0,
        108.0,
        110.0,
      ];
      // 防守型：起點 100 緩漲到 105、近 5 日持平
      // → 20日 = +5%、5日 = 0%
      final steady = [
        100.0,
        ...List.filled(14, 103.0),
        105.0,
        105.0,
        105.0,
        105.0,
        105.0,
        105.0,
      ];

      final priceHistories = {
        for (var m = 0; m < 5; m++) 'E$m': seq('E$m', bounce),
        for (var m = 0; m < 5; m++) 'F$m': seq('F$m', steady),
      };
      final industries = {
        for (var m = 0; m < 5; m++) 'E$m': '半導體業',
        for (var m = 0; m < 5; m++) 'F$m': '金融保險業',
      };

      final by20 = service.rank(
        priceHistories: priceHistories,
        industries: industries,
        names: const {},
        institutionalHistories: const {},
      );
      final by5 = service.rank(
        priceHistories: priceHistories,
        industries: industries,
        names: const {},
        institutionalHistories: const {},
        window: RankingWindow.d5,
      );

      // 20日視角：金融在前（半導體仍為負）
      expect(by20.first.industry, '金融保險業');
      expect(by20.last.industry, '半導體業');
      expect(by20.last.momentumPct, lessThan(0));
      // 5日視角：半導體反彈居首
      expect(by5.first.industry, '半導體業');
      expect(by5.first.momentumPct, closeTo(10.0, 1e-6));
      expect(by5.first.topMembers.first.retPct, closeTo(10.0, 1e-6));
      expect(by5.last.momentumPct, closeTo(0.0, 1e-6));
    });
  });
  // 三個指標都是「未正規化」的版本，讀法會被誤導（2026-07-27 實測）
  //
  // 【1】絕對報酬 vs 超額報酬
  //   大盤 20 日 = -2.10%，但榜上 12 個族群顯示的是絕對報酬。
  //   居家生活類 +0.23% 讀起來像「幾乎沒動」，實際是 **超額 +2.34%**
  //   ——在一個跌 2.1% 的市場裡屬強勢。輪動要問「誰比大盤強」而非「誰漲了」。
  //
  // 【2】法人張數 vs 佔成交量比
  //   依張數：金融保險 +18.9萬 > 電腦週邊 +16.1萬 > 鋼鐵 +9.8萬
  //   依佔比：**鋼鐵 32.6% > 水泥 25.7% > 紡織 16.2% > 金融保險 12.4%**
  //   排序完全不同。張數榜實際在量「哪個族群大」——法人吃掉鋼鐵三日成交量
  //   的三分之一，才是真正主導的族群。
  //
  // 【3】中位數缺廣度
  //   橡膠 中位+3.5% 上漲佔比 73%（整族在動）
  //   其他  中位+0.7% 上漲佔比 52%（一半漲一半跌，中位數由少數成員撐）
  //   同一個中位數排序下，訊號品質天差地遠。
  group('正規化指標', () {
    test('🚨 超額報酬＝族群中位數 − 同窗大盤報酬', () {
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 5; i++)
            'A$i': historyWithRet20('A$i', 0.2), // 中位數 +0.2%
        },
        industries: {for (var i = 0; i < 5; i++) 'A$i': '居家生活類'},
        names: const {},
        institutionalHistories: const {},
        marketReturnPct: -2.10,
      );

      expect(rankings.single.momentumPct, closeTo(0.2, 0.001));
      expect(
        rankings.single.excessPct,
        closeTo(2.30, 0.001),
        reason: '大盤 -2.10% 時，+0.2% 是跑贏 2.3pp，不是「幾乎沒動」',
      );
    });

    test('對照組：未提供大盤報酬時 excessPct 為 null，不得當成 0', () {
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'A$i': historyWithRet20('A$i', 1.0),
        },
        industries: {for (var i = 0; i < 5; i++) 'A$i': '居家生活類'},
        names: const {},
        institutionalHistories: const {},
      );

      expect(
        rankings.single.excessPct,
        isNull,
        reason: '當成 0 等於宣稱「大盤沒漲跌」——把缺資料講成一個事實',
      );
    });

    test('🚨 法人佔成交量比：小族群大比例不得被大族群的絕對張數蓋過', () {
      final date = DateTime(2026, 7, 27);
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'S$i': historyWithRet20('S$i', 5.0),
          for (var i = 0; i < 5; i++) 'F$i': historyWithRet20('F$i', 5.0),
        },
        industries: {
          for (var i = 0; i < 5; i++) 'S$i': '鋼鐵工業',
          for (var i = 0; i < 5; i++) 'F$i': '金融保險',
        },
        names: const {},
        institutionalHistories: {
          // 鋼鐵：法人 2,000 股／成交 10,000 股 → 20%
          for (var i = 0; i < 5; i++) 'S$i': [inst('S$i', date, foreign: 2000)],
          // 金融：法人 10,000 股／成交 1,000,000 股 → 1%
          for (var i = 0; i < 5; i++)
            'F$i': [inst('F$i', date, foreign: 10000)],
        },
        volumeBySymbol: {
          for (var i = 0; i < 5; i++) 'S$i': 10000,
          for (var i = 0; i < 5; i++) 'F$i': 1000000,
        },
        marketReturnPct: 0,
      );

      final steel = rankings.firstWhere((r) => r.industry == '鋼鐵工業');
      final fin = rankings.firstWhere((r) => r.industry == '金融保險');

      expect(steel.institutionalNetShares, 10000); // 絕對張數：金融較大
      expect(fin.institutionalNetShares, 50000);
      expect(
        steel.institutionalVolumeRatio,
        closeTo(0.20, 0.001),
        reason: '法人吃掉鋼鐵兩成成交量',
      );
      expect(fin.institutionalVolumeRatio, closeTo(0.01, 0.001));
      expect(
        steel.institutionalVolumeRatio! > fin.institutionalVolumeRatio!,
        isTrue,
        reason: '絕對張數金融贏 5 倍，但佔比鋼鐵贏 20 倍——後者才是「法人主導」',
      );
    });

    test('對照組：成交量缺資料時佔比為 null，不得除以零或當 0', () {
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'A$i': historyWithRet20('A$i', 1.0),
        },
        industries: {for (var i = 0; i < 5; i++) 'A$i': '鋼鐵工業'},
        names: const {},
        institutionalHistories: {
          for (var i = 0; i < 5; i++)
            'A$i': [inst('A$i', DateTime(2026, 7, 27), foreign: 100)],
        },
      );

      expect(rankings.single.institutionalVolumeRatio, isNull);
    });

    test('🚨 族群內任一成員缺成交量 → 整組不算比例（分母偏小會讓比例虛高）', () {
      final date = DateTime(2026, 7, 27);
      final rankings = service.rank(
        priceHistories: {
          for (var i = 0; i < 5; i++) 'A$i': historyWithRet20('A$i', 1.0),
        },
        industries: {for (var i = 0; i < 5; i++) 'A$i': '鋼鐵工業'},
        names: const {},
        institutionalHistories: {
          for (var i = 0; i < 5; i++) 'A$i': [inst('A$i', date, foreign: 1000)],
        },
        // A4 缺成交量：若仍以 4 檔的量當分母，比例會被高估 25%
        volumeBySymbol: {for (var i = 0; i < 4; i++) 'A$i': 10000},
      );

      expect(
        rankings.single.institutionalVolumeRatio,
        isNull,
        reason:
            '分子含 5 檔法人、分母只有 4 檔成交量 → 比例虛高。'
            '寧可不顯示也不要給一個系統性偏高的數',
      );
    });

    test('🚨 上漲佔比：中位數相同但廣度不同的兩族群要能分辨', () {
      // 甲：5 檔全漲小幅 → 中位 +1.0%、廣度 100%
      // 乙：2 檔大漲 + 3 檔下跌，中位數同為 +1.0% 由排序決定 → 廣度 40%
      final rankings = service.rank(
        priceHistories: {
          'X1': historyWithRet20('X1', 1.0),
          'X2': historyWithRet20('X2', 1.0),
          'X3': historyWithRet20('X3', 1.0),
          'X4': historyWithRet20('X4', 1.0),
          'X5': historyWithRet20('X5', 1.0),
          'Y1': historyWithRet20('Y1', 20.0),
          'Y2': historyWithRet20('Y2', 10.0),
          'Y3': historyWithRet20('Y3', 1.0),
          'Y4': historyWithRet20('Y4', -5.0),
          'Y5': historyWithRet20('Y5', -8.0),
        },
        industries: {
          for (var i = 1; i <= 5; i++) 'X$i': '甲族群',
          for (var i = 1; i <= 5; i++) 'Y$i': '乙族群',
        },
        names: const {},
        institutionalHistories: const {},
        marketReturnPct: 0,
      );

      final x = rankings.firstWhere((r) => r.industry == '甲族群');
      final y = rankings.firstWhere((r) => r.industry == '乙族群');

      expect(x.momentumPct, closeTo(1.0, 0.001));
      expect(y.momentumPct, closeTo(1.0, 0.001));
      expect(x.advancingRatio, closeTo(1.0, 0.001), reason: '5/5 上漲');
      expect(
        y.advancingRatio,
        closeTo(0.6, 0.001),
        reason: '3/5 上漲（Y1/Y2/Y3）——同樣的中位數，訊號品質完全不同',
      );
    });
  });
}
