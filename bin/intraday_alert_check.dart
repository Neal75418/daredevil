/// `dart build cli` 的入口——它只認 `bin/` 底下的目標。
///
/// **為什麼要預先編譯**(2026-08-10 實機事故):launchd 原本跑
/// `dart run tool/intraday_alert_check.dart`,而 `dart run` **每次**都會
/// 執行 build hooks;`package:sqlite3` 的 hook 會去 github.com 抓預編譯
/// 二進位檔。開盤當下機器剛喚醒、Wi-Fi 還沒接上 → DNS 失敗 → 整個
/// process 在 `main()` 之前就死掉,**連心跳都發不出來**。
///
/// 後果:2026-08-10 開盤前 7 輪(09:00–09:30)完全沒有檢查任何提醒——
/// 而那正是波動最大的時段。編譯成獨立執行檔後,執行期不再有 build hook,
/// 也就不再依賴網路才能啟動。
///
/// 這支刻意只做轉呼叫,實作留在 `tool/`:那裡有「純 Dart 鐵律」的守門
/// 測試(`test/tool/tool_chain_pure_dart_test.dart`)在看著 import 閉包。
library;

import '../tool/intraday_alert_check.dart' as cli;

Future<void> main(List<String> args) => cli.main(args);
