// tool/regime_calibrate.dart 純邏輯測試（衍生分數 + 驗證指標）。
import 'package:flutter_test/flutter_test.dart';

import '../../tool/regime_calibrate.dart';
import '../../tool/regime_report.dart';

RegimeCell _cell(int n, double rel) => RegimeCell(
  n: n,
  expectancy: 0,
  winRate: 0,
  avgWin: 0,
  avgLoss: 0,
  relative: rel,
);

RuleYearCells _yc(int n, double rel) =>
    (short: _cell(n, rel), long: _cell(n, rel));

void main() {
  group('trainRelative', () {
    test('樣本數加權平均相對', () {
      final byYear = {2021: _yc(100, 2.0), 2023: _yc(300, 6.0)};
      // (2*100 + 6*300)/(100+300) = 2000/400 = 5.0
      expect(
        trainRelative(byYear, [2021, 2023], useShort: false),
        closeTo(5.0, 1e-9),
      );
    });
  });

  group('deriveScores', () {
    test('倖存者：n≥min 且 train相對>0；其餘 0', () {
      final data = {
        'GOOD': {2021: _yc(200, 8.0), 2023: _yc(200, 4.0)}, // rel>0, n足
        'BEAR_BAD': {2021: _yc(200, -3.0)}, // 相對<0 → 砍
        'THIN': {2021: _yc(10, 9.0)}, // 樣本不足 → 砍
      };
      final scores = deriveScores(
        data,
        [2021, 2023],
        useShort: false,
        minSamples: 100,
      );
      expect(scores['GOOD'], greaterThan(0), reason: '正相對 + 足樣本 → 留');
      expect(scores['BEAR_BAD'], 0, reason: '相對為負 → 砍');
      expect(scores['THIN'], 0, reason: '樣本不足 → 砍');
    });

    test('只有一個倖存者 → 給中點分（min==max）', () {
      final data = {
        'ONLY': {2021: _yc(200, 5.0)},
        'CUT': {2021: _yc(200, -1.0)},
      };
      final scores = deriveScores(data, [2021], useShort: false);
      expect(scores['ONLY'], inInclusiveRange(10, 35));
      expect(scores['CUT'], 0);
    });
  });

  group('scoreWeightedRelative', () {
    test('以分數×樣本數加權該年相對；score=0 不計', () {
      final data = {
        'A': {2022: _yc(100, 10.0)},
        'B': {2022: _yc(100, 2.0)},
      };
      // {A:30,B:10}: (30*100*10 + 10*100*2)/(30*100+10*100)=3200/4000... =3200/4000=0.8*...
      // = (30000+2000)/(3000+1000)=32000/4000=8.0
      expect(
        scoreWeightedRelative({'A': 30, 'B': 10}, data, 2022, useShort: false),
        closeTo(8.0, 1e-9),
      );
      // A 被砍(0) → 只剩 B → 2.0
      expect(
        scoreWeightedRelative({'A': 0, 'B': 10}, data, 2022, useShort: false),
        closeTo(2.0, 1e-9),
      );
    });
  });

  group('候選檔名隔離(2026-08-29 tool 稽核 #6)', () {
    test('🚨 不得與 recalibrate 的 production/candidate 檔名相撞', () {
      // 本工具每條規則只有 score + active,沒有 avg_return / t_stat。
      // parseJson 不會抱怨(drift guard 只在 backtest 存在時比對),於是
      // 檔案乾淨載入——但負證據歸零需要那兩個欄位才成立,promote 進
      // production 檔名等於把 28/44 條規則無聲彈回手調正分。
      for (final horizon in ['short', 'long']) {
        final path = regimeCandidatePath(horizon);
        expect(
          path,
          isNot('assets/rule_scores_calibrated_${horizon}_candidate.json'),
          reason: 'recalibrate 的 candidate 檔名',
        );
        expect(
          path,
          isNot('assets/rule_scores_calibrated_$horizon.json'),
          reason: 'production 檔名',
        );
        expect(path, contains('regime'), reason: '檔名要能一眼看出產出者');
      }
    });

    test('short/long 各自獨立檔名', () {
      expect(regimeCandidatePath('short'), isNot(regimeCandidatePath('long')));
    });
  });
}
