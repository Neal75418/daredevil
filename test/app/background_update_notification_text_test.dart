import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/app/background_update_service.dart';
import 'package:daredevil/domain/services/update_service.dart';

void main() {
  UpdateResult ok() => UpdateResult(date: DateTime(2026, 12, 2))
    ..success = true
    ..stocksAnalyzed = 5;

  // 手機靠背景更新自動跑，這則通知是 user 最常看到的更新結果
  test('交易日曆待更新時，背景更新通知帶上提醒', () {
    final result = ok()..calendarNotice = '交易日曆 2027 年尚未依證交所公告更新';
    expect(
      updateNotificationText(result, isChinese: true).body,
      '分析 5 檔，交易日曆待更新',
    );
    expect(
      updateNotificationText(result, isChinese: false).body,
      contains('trading calendar'),
    );
  });

  test('不需更新日曆時通知不變', () {
    final text = updateNotificationText(ok(), isChinese: true);
    expect(text.title, '盤後資料已更新');
    expect(text.body, '分析 5 檔');
  });

  // 抽成函式前後三個分支的文字必須一致
  test('非交易日跳過：沿用 result.message', () {
    final result = UpdateResult(date: DateTime(2026, 12, 5))
      ..skipped = true
      ..message = '非交易日，跳過更新';
    final text = updateNotificationText(result, isChinese: true);
    expect(text.title, '今日無更新');
    expect(text.body, '非交易日，跳過更新');
  });

  test('更新失敗：標題為失敗、內文沿用 message，不附日曆提醒', () {
    final result = UpdateResult(date: DateTime(2026, 12, 2))
      ..success = false
      ..message = '更新失敗: 網路錯誤'
      ..calendarNotice = '交易日曆 2027 年尚未依證交所公告更新';
    final text = updateNotificationText(result, isChinese: true);
    expect(text.title, '更新失敗');
    expect(text.body, '更新失敗: 網路錯誤');
  });

  test('成功但沒有可列的項目：內文為「更新完成」', () {
    final result = UpdateResult(date: DateTime(2026, 10, 1))..success = true;
    expect(updateNotificationText(result, isChinese: true).body, '更新完成');
    expect(
      updateNotificationText(result, isChinese: false).body,
      'Update complete',
    );
  });
}
