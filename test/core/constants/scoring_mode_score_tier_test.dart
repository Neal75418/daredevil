import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';

void main() {
  // 回檔的四條主訊號擇一成立、幾乎每檔只觸發一條（12／15／18 分），強中弱
  // 在這個分頁分不出差別；其餘模式照常顯示
  test('只有回檔模式不顯示強中弱分級', () {
    expect(
      {for (final m in ScoringMode.userFacingModes) m: m.showsScoreTier},
      {
        ScoringMode.momentumEntry: true,
        ScoringMode.strengthObserve: true,
        ScoringMode.weaknessObserve: false,
      },
    );
  });
}
