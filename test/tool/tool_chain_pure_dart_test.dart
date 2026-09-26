import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/daily_update.dart 的純 Dart 守門(2026-07-30)。
///
/// launchd 每天 15:30 以 `dart run tool/daily_update.dart` 跑盤後更新——
/// `dart run` 沒有 dart:ui,import 閉包裡只要混進 flutter/easy_localization
/// 就會編譯失敗。**而且是靜默失敗**:GUI 手動更新照常,只有 launchd 的
/// stderr log 在累積錯誤。2026-07-18 `9a280c6a` 把 AppNumberFormat 用進
/// rule_accuracy_service(其檔案 import easy_localization → dart:ui),
/// 自動更新從此斷了 13 天才被發現(7/30 對帳 7/30 資料缺失時)。
///
/// 此測試靜態走 import/export graph,斷言 tool 入口的閉包不可達任何
/// 需要 dart:ui 的套件——在 CI/flutter test 就把回歸擋下來,不用等
/// 隔天 launchd 陣亡。
void main() {
  // 2026-08-08:新增 tool/intraday_alert_check.dart(launchd 每 5 分鐘的
  // 盤中提醒檢查)後,守門改為涵蓋整條 tool 鏈——同一個失效模式
  // (混進 flutter → 編譯失敗 → 排程靜默斷)對兩支同等致命。
  for (final entry in [
    'tool/daily_update.dart',
    'tool/intraday_alert_check.dart',
  ]) {
    test('$entry 的 import 閉包不得含 flutter/easy_localization/dart:ui', () {
      const banned = [
        'package:flutter/',
        'package:easy_localization/',
        'dart:ui',
        // flutter plugins(自身 import flutter → dart:ui)——第三方套件的
        // 源碼不在本 graph 展開範圍,顯式列名把關(2026-07-27 shared_preferences
        // 混進 runner 即第二波斷更;kernel compile 是終極真理,此清單擋已知毒)
        'package:shared_preferences/',
        'package:path_provider/',
        'package:flutter_secure_storage/',
        'package:package_info_plus/',
        'package:workmanager/',
        'package:flutter_local_notifications/',
      ];

      final importRe = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
      final visited = <String>{};
      final parentOf = <String, String>{};
      final queue = [entry];
      final violations = <String>[];

      String? toLocalPath(String uri) {
        if (uri.startsWith('package:daredevil/')) {
          return 'lib/${uri.substring('package:daredevil/'.length)}';
        }
        if (!uri.contains(':')) return null; // 相對 import 由呼叫端組
        return null; // 其他 package / dart: 不展開
      }

      while (queue.isNotEmpty) {
        final path = queue.removeLast();
        if (!visited.add(path)) continue;
        final file = File(path);
        if (!file.existsSync()) continue;
        for (final m in importRe.allMatches(file.readAsStringSync())) {
          final uri = m.group(1)!;
          for (final bad in banned) {
            if (uri.startsWith(bad)) {
              // 重建鏈條讓失敗訊息直接可讀
              final chain = <String>[path];
              var cur = path;
              while (parentOf.containsKey(cur)) {
                cur = parentOf[cur]!;
                chain.add(cur);
              }
              violations.add('$uri\n  於 ${chain.reversed.join('\n  → ')}');
            }
          }
          var next = toLocalPath(uri);
          if (next == null && !uri.contains(':')) {
            // 相對路徑 import
            final dir = path.substring(0, path.lastIndexOf('/'));
            next = Uri.parse('$dir/$uri').normalizePath().toString();
          }
          if (next != null && !visited.contains(next)) {
            parentOf[next] = path;
            queue.add(next);
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'tool 依賴鏈染上需要 dart:ui 的 import,launchd 的 dart run 會'
            '編譯失敗且靜默斷更新:\n${violations.join('\n')}',
      );
      // sanity:確實走到了深層(防 regex/路徑解析壞掉造成假綠)。
      // 錨點各自不同——daily_update 走 update chain、intraday 走 alert chain。
      final anchor = entry == 'tool/daily_update.dart'
          ? 'lib/domain/services/update_service.dart'
          : 'lib/domain/services/alert/intraday_alert_monitor.dart';
      expect(visited, contains(anchor));
      expect(visited.length, greaterThan(5));
    });
  }
}
