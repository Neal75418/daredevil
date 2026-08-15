import 'dart:io';

/// launchd 的兩支 CLI 跑的是 **AOT 編譯產物**,不是 source——產物落後
/// source 時它照常執行、`update_run` 照記 SUCCESS、日誌無異常,跑的卻是
/// 舊邏輯(2026-08-15 實測落後 3 天)。這個字串印在每次執行的開頭,讓
/// 「它到底跑的是哪一版」在日誌裡有據可查,而不是事後靠檔案時間戳推。
///
/// 為什麼不用 `String.fromEnvironment`:`dart build cli` 不支援 `--define`
/// (2026-08-15 實測,只有 -o / -t / --verbosity),編譯期注入這條路不通。
/// 改由 `ops/launchd/install.sh` 在 bundle 根寫 `BUILD_INFO`。
///
/// **一律 fail-soft**:它的唯一用途是出事時能查,自己絕不能成為出事的
/// 原因。標記檔缺失就退回 binary 的 mtime——那不精確到 commit,但足以
/// 判斷新舊(今天正是靠 mtime 發現的)。兩者都拿不到才回 `unknown`。
String buildStamp({String? resolvedExecutable}) {
  final exePath = resolvedExecutable ?? Platform.resolvedExecutable;
  final parts = <String>[];

  try {
    // bundle 結構是 <root>/bin/<exe>,標記檔放 <root>/BUILD_INFO
    final marker = File('${File(exePath).parent.parent.path}/BUILD_INFO');
    if (marker.existsSync()) {
      final sha = marker.readAsStringSync().trim();
      if (sha.isNotEmpty) parts.add('build=$sha');
    }
  } catch (_) {
    // 讀不到就當沒有,交給下面的 mtime
  }

  try {
    final stat = File(exePath).statSync();
    if (stat.type != FileSystemEntityType.notFound) {
      final t = stat.modified.toLocal().toIso8601String();
      parts.add('compiled=${t.substring(0, 16)}');
    }
  } catch (_) {
    // 同上
  }

  return parts.isEmpty ? 'build=unknown' : parts.join(' ');
}
