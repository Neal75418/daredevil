// CLI 建置標記(2026-08-15)
//
// **為什麼需要**:launchd 跑的是 AOT 編譯產物,不是 source。產物落後
// source 時它照常執行、update_run 照記 SUCCESS、日誌無異常——三個訊號
// 全部正常,跑的卻是舊邏輯。2026-08-15 實測落後 3 天(binary 編於 8/12,
// 期間 lib/ 有 14 個 commit),是靠 `ls -la` 看檔案時間戳才撞見的。
//
// **為什麼不用 `String.fromEnvironment`**:`dart build cli` 不支援
// `--define`(只有 -o / -t / --verbosity,2026-08-15 實測),編譯期注入
// 這條路不通。改由 install.sh 在 bundle 根寫 BUILD_INFO,執行期讀。
//
// **fail-soft 是硬需求**:這東西的唯一用途是「出事時能查」,它自己絕不
// 能成為出事的原因。標記檔缺失/損毀一律降級,永遠回一個可印的字串。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/build_stamp.dart';

void main() {
  late Directory tmp;
  late File exe;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('build_stamp_test');
    // 重現 bundle 結構:<root>/bin/<exe> + <root>/BUILD_INFO
    Directory('${tmp.path}/bin').createSync();
    exe = File('${tmp.path}/bin/daily_update')..writeAsStringSync('x');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('讀得到 BUILD_INFO 時,輸出含其內容', () {
    File('${tmp.path}/BUILD_INFO').writeAsStringSync('c37fc131');
    expect(buildStamp(resolvedExecutable: exe.path), contains('c37fc131'));
  });

  test('內容前後空白/換行要 trim(腳本用 echo 寫入必帶換行)', () {
    File('${tmp.path}/BUILD_INFO').writeAsStringSync('  c37fc131\n');
    final s = buildStamp(resolvedExecutable: exe.path);
    expect(s, contains('c37fc131'));
    expect(s, isNot(contains('\n')), reason: '輸出是單行日誌,不得帶換行');
  });

  test('🚨 BUILD_INFO 不存在也必須回可印字串,不得拋例外', () {
    // 這是 fail-soft 的核心:標記檔遺失只該讓「查詢變難」,
    // 絕不能讓每日更新在 main() 開頭就死掉
    expect(() => buildStamp(resolvedExecutable: exe.path), returnsNormally);
    expect(buildStamp(resolvedExecutable: exe.path), isNotEmpty);
  });

  test('🚨 即使沒有 BUILD_INFO,也要帶出 binary 的建置時間', () {
    // mtime 是最後防線——它不告訴你是哪個 commit,但足以判斷
    // 「這個產物是不是舊的」,今天就是靠它發現落後 3 天的
    final s = buildStamp(resolvedExecutable: exe.path);
    final year = DateTime.now().year.toString();
    expect(s, contains(year), reason: '缺 BUILD_INFO 時至少要有 mtime 可判斷新舊');
  });

  test('executable 路徑本身無效也不得拋例外', () {
    expect(
      () => buildStamp(resolvedExecutable: '/nonexistent/bin/whatever'),
      returnsNormally,
    );
  });
}
