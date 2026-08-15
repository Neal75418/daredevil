// tool/daily_update.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 每日跑一次 UpdateService 累積 forward calibration 資料。給 macOS
// launchd 用（workmanager 在 macOS 不支援，導致 forward data 累積
// 完全靠 user 手動開 app）。
//
// **C 方案 refactor 2026-06-19 啟用**：runHeadlessUpdate 已純 Dart 化，
// AppDatabase 接收外部注入 executor，CalibratedScoresRegistry 接受
// asset loader override。本 CLI 在 startup 把這兩條路徑接成 dart:io
// 友善版本即可全鏈跑通。
//
// ## 使用方式
//
//   # 一次性手動跑（從 repo root 執行讓 assets/ 找得到）：
//   dart run tool/daily_update.dart
//
//   # launchd 自動排程（com.neo.daredevil.daily.plist）每天 15:30
//   # 跑同一條指令。
//
// ## 環境變數
//
//   FINMIND_TOKEN  必填（沒設只能跑免費 TWSE 資料、新聞 / EPS / 月營收
//                  / 股利等會 skip）。launchd 不讀 ~/.zshrc — plist 用
//                  zsh -lc wrapper source rc 拿 token。
//
// ## DB 路徑
//
// 直接讀寫 macOS Flutter app sandbox 的 DB：
//   ~/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite
//
// 確保 GUI app 跟 CLI 共用同一份資料，calibration 累積無分裂。
//
// ## 退出碼
//
//   0   更新成功 / 非交易日 skip
//   1   更新失敗（API error / DB write fail / 非預期 exception）

import 'dart:io';

import 'package:daredevil/core/utils/log_rotation.dart';
import 'package:daredevil/app/headless_update_runner.dart';
import 'package:daredevil/data/remote/file_api_budget_store.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/utils/build_stamp.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';

Future<void> main(List<String> args) async {
  AppLogger.forceOutput = true; // CLI:繞過 assert gate,否則日誌全滅
  // stderr 也要輪替:故障訊息落在那裡,而它曾長到 153 MB(見 intraday 註解)
  for (final name in [
    'daredevil-daily-update.stdout.log',
    'daredevil-daily-update.stderr.log',
  ]) {
    LogRotation.rotateIfNeeded(
      '${Platform.environment['HOME']}/Library/Logs/$name',
    );
  }
  final start = DateTime.now();
  // build stamp:launchd 跑的是 AOT 產物,落後 source 時三個訊號(exit
  // code、update_run、日誌)全部正常,跑的卻是舊邏輯。2026-08-15 實測
  // 落後 3 天,是靠檔案時間戳撞見的——這行讓日誌自己就能回答「跑的是
  // 哪一版」。
  print(
    '[daily_update] started at ${start.toIso8601String()} '
    '[${buildStamp()}]',
  );

  // CLI 跑在純 Dart context — 沒有 Flutter binding，rootBundle 不可用。
  // 用 dart:io 直接讀 assets 目錄（CLI 從 repo root 跑時 assets/ 就是
  // pubspec.yaml 旁邊那個目錄）。
  CalibratedScoresRegistry.instance.assetLoaderOverride = (path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException(
        'Asset not found at $path. '
        'Run from repo root so `assets/*.json` is resolvable.',
        path,
      );
    }
    return file.readAsString();
  };

  // 直接讀寫 GUI app sandbox 的 DB — 跟 GUI 共用資料、calibration 不分裂。
  final dbPath =
      '${Platform.environment['HOME']}'
      '/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite';
  print('[daily_update] DB: $dbPath (exists=${File(dbPath).existsSync()})');

  // FinMind token：直接讀 env var（與 SettingsRepository 的 fallback chain
  // priority 2 一致）。launchd plist 用 `zsh -lc` source ~/.zshrc 拿到。
  final finMindToken = Platform.environment['FINMIND_TOKEN'];
  print(
    '[daily_update] FINMIND_TOKEN '
    '${(finMindToken == null || finMindToken.isEmpty) ? "未設" : "已設 (${finMindToken.length} chars)"}',
  );

  AppDatabase? database;
  try {
    database = AppDatabase.forToolFile(dbPath);
    final result = await runHeadlessUpdate(
      database: database,
      // 純 Dart 檔案版(DB 同目錄):shared_preferences 是 flutter plugin,
      // 不可進本 CLI 的編譯鏈(守門測試把關)
      budgetStore: FileApiBudgetStore(
        '${File(dbPath).parent.path}/api_budget_cli.json',
      ),
      finMindToken: finMindToken,
    );
    final elapsed = DateTime.now().difference(start);
    print(
      '[daily_update] finished in ${elapsed.inSeconds}s — '
      'success=${result.success}, skipped=${result.skipped}, '
      'message=${result.message}',
    );
    print('[daily_update] summary: ${result.summary}');
    // 逐條印出失敗項(2026-08-15 稽核):過去只印 message 與 exit 0,
    // 20 個 recordError 的內容對維運完全不可見
    for (final err in result.errors) {
      stderr.writeln('[daily_update] ERROR: $err');
    }
    // exit code 看 hasErrors 而非 success——success 的語意是「主流程完成」,
    // 部分失敗時仍為 true,拿它當退出碼等於把故障報成成功
    exit(result.hasErrors ? 1 : 0);
  } catch (e, s) {
    AppLogger.error('daily_update', 'unhandled exception', e, s);
    print('[daily_update] FAILED: $e');
    print(s);
    exit(1);
  } finally {
    await database?.close();
  }
}
