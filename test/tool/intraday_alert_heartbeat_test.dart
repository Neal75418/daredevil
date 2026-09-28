import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 盤中提醒 CLI 的心跳(2026-08-08 三次審查 M-1)。
///
/// **為什麼需要端到端跑一次**:心跳(`beat()`)是 commit `31b54e03` 的全部
/// 價值——它讓「正常跳過」與「啟動就炸」在日誌上長得不一樣。但在此之前
/// **沒有任何測試斷言它**:把 `beat(...)` 改回 `return;`,全套測試照樣綠,
/// 而非交易時段會靜靜地變回無聲。
///
/// 這條同時擋住另一個更貴的失效:**編譯失敗導致自動更新靜默斷線**
/// (本專案 2026-07 為此斷了 13 天)。`dart run` 若編譯不過,這裡會拿到
/// 空的 stdout 與非零 exit code。
///
/// **安全性**:刻意把 `HOME` 指到一個空的暫存目錄,讓 CLI 走「DB 不存在」
/// 的早退路徑——不連網、不碰真的資料庫、不會認領或通知任何提醒。
void main() {
  test('🚨 CLI 一定會發心跳——即使是早退路徑', () async {
    final fakeHome = Directory.systemTemp.createTempSync('dd_hb_home');
    addTearDown(() => fakeHome.deleteSync(recursive: true));

    final result = await Process.run(
      'dart',
      ['run', 'tool/intraday_alert_check.dart'],
      environment: {'HOME': fakeHome.path},
      workingDirectory: Directory.current.path,
    );

    final out = '${result.stdout}';
    expect(
      out,
      contains('[intraday_alert]'),
      reason:
          '心跳不見了。若 stdout 全空,先確認是不是編譯失敗——'
          '那正是 2026-07 自動更新靜默斷 13 天的形狀。stderr: ${result.stderr}',
    );
    // ⚠️ 不可斷言特定分支:非交易時段的 skip 早退在 DB 檢查**之前**,
    // 所以走哪條取決於跑測試的當下(平日盤中 vs 週末)。第一版就是這樣
    // 寫死成「FAIL(DB 不存在)」,週六跑立刻紅——測試自己抓到了自己的
    // 日期依賴。這裡改為斷言「屬於已知狀態之一」,與時間無關。
    const knownStates = [
      'skip(非交易時段)',
      'FAIL(DB 不存在)',
      'FAIL(通知管道不可用)',
      'FAIL(報價全滅)',
      'FAILED',
      '無觸價',
      '觸價',
    ];
    expect(
      knownStates.any(out.contains),
      isTrue,
      reason:
          '心跳內容不是任何已知狀態,可能有人新增分支卻忘了發心跳。'
          '實際輸出:$out',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('🚨 時區與台北不符時,心跳必須自己講出來', () async {
    // launchd 的 StartCalendarInterval 依**系統本地時間**喚醒,盤中判定
    // 卻用台北時間。macOS 的「自動依位置設定時區」預設開啟,出差時會自己
    // 改掉,使用者不會做任何動作。實測有效覆蓋:東京/曼谷 78%、倫敦 0%。
    //
    // 不修喚醒時段,但**症狀必須可辨識**:漏接提醒長得跟「今天沒股票
    // 觸價」一模一樣,使用者會得出錯誤結論。這正是本專案反覆吃虧的形狀。
    final fakeHome = Directory.systemTemp.createTempSync('dd_tz_home');
    addTearDown(() => fakeHome.deleteSync(recursive: true));

    final result = await Process.run(
      'dart',
      ['run', 'tool/intraday_alert_check.dart'],
      environment: {'HOME': fakeHome.path, 'TZ': 'Asia/Kolkata'},
      workingDirectory: Directory.current.path,
    );

    expect(
      '${result.stdout}',
      contains('⚠️TZ'),
      reason: '本地與台北 UTC+8 不符,心跳必須帶警告',
    );
    // ⚠️ 用半小時時區(印度 +5:30)而非東京(+9)(2026-08-08 五次審查 I-6):
    // 整點時區走不到 _offsetLabel 的半小時分支,那段一行都沒被執行過;
    // 而只斷言 contains('⚠️TZ') 的話,offset 字串印錯也不會紅。
    expect(
      '${result.stdout}',
      contains('UTC+5:30'),
      reason: 'inHours 會把 +5:30 截斷成 +5,診斷值必須精確',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
