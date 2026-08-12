// splitByTrendGate — momentumEntry 顯示層分艙(2026-08-12)
//
// 動機:8/12 實況「起漲候選」11 檔裡 8 檔 trendState=DOWN、6 張掛
// 股價淨值比低——tab 承諾「上升趨勢中、順勢初升」,內容物卻是 value
// 主導的弱勢股(scoring_mode.dart 註解自認的「gate 與規則設計意圖的
// 已知張力」)。**不動評分**:分艙只是把「未確認上升趨勢」的卡收合
// 淡化,資料保留、可展開;要不要真的 hard-gate 留給 calibration 數據。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';

ModeRecommendation rec(String symbol, {String? trend}) => ModeRecommendation(
  symbol: symbol,
  rank: 1,
  modeScoreShort: 10,
  modeScoreLong: 10,
  reasons: const [],
  trendState: trend,
);

void main() {
  group('splitByTrendGate', () {
    test('🚨 UP/RANGE 進前艙,DOWN 進後艙(8/12 的 11 檔形狀)', () {
      final r = splitByTrendGate([
        rec('2376', trend: 'RANGE'),
        rec('1314', trend: 'DOWN'),
        rec('6155', trend: 'RANGE'),
        rec('2201', trend: 'DOWN'),
        rec('9999', trend: 'UP'),
      ]);

      expect(r.qualified.map((e) => e.symbol), ['2376', '6155', '9999']);
      expect(r.gated.map((e) => e.symbol), ['1314', '2201']);
    });

    test('🚨 trendState null(無分析資料)歸後艙——「未確認」而非「已確認」', () {
      final r = splitByTrendGate([rec('2330', trend: 'UP'), rec('4444')]);
      expect(r.qualified.map((e) => e.symbol), ['2330']);
      expect(r.gated.map((e) => e.symbol), ['4444']);
    });

    test('保留原始排序(排名邏輯不變,分艙不重排)', () {
      final r = splitByTrendGate([
        rec('C', trend: 'DOWN'),
        rec('A', trend: 'UP'),
        rec('B', trend: 'DOWN'),
        rec('D', trend: 'UP'),
      ]);
      expect(r.qualified.map((e) => e.symbol), ['A', 'D']);
      expect(r.gated.map((e) => e.symbol), ['C', 'B']);
    });

    test('全過/全不過的邊界', () {
      expect(splitByTrendGate([rec('A', trend: 'UP')]).gated, isEmpty);
      expect(splitByTrendGate([rec('A', trend: 'DOWN')]).qualified, isEmpty);
      expect(splitByTrendGate(const []).qualified, isEmpty);
    });
  });
}
