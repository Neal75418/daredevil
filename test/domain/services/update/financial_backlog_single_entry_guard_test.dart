// 守門：財報回填目標只能來自 `FundamentalSyncer.selectFinancialBacklog` 這一個入口
//
// 2026-09-05 把兩條佇列（上市取候選前 N、上櫃最舊優先）收成一條，理由之一就是
// 「守衛只掛在 N 個呼叫點之一」這個病在本專案反覆發作。若日後有人為某個市場或
// 某類股票再開一條旁路（另一個 `syncFinancialStatements(symbols: …)` 呼叫點、
// 或把舊的取前 N 選法加回來），這裡會轉紅。
//
// 兩條斷言互為 sanity floor：掃描器失效時「呼叫點恰為 1」會先變成 0 而非套套邏輯。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test(
    '🚨 lib 裡 syncFinancialStatements(symbols:) 的呼叫點恰為 1，且與 selectFinancialBacklog 同檔',
    () {
      expect(
        libFiles.length,
        greaterThan(100),
        reason: 'sanity floor：掃描器要真的看到 lib',
      );

      // 每個 match 一筆——同一檔裡加第二個旁路也要轉紅（coordinator 正是最
      // 可能長出旁路的檔案；只數檔案數會讓那種旁路無聲通過）
      final callSites = <String>[];
      for (final f in libFiles) {
        final src = f.readAsStringSync();
        // 排除定義本身（fundamental_syncer 裡的 `Future<int?> syncFinancialStatements({`）
        for (final m in RegExp(
          r'\.syncFinancialStatements\(\s*symbols:',
        ).allMatches(src)) {
          callSites.add('${f.path}@${m.start}');
        }
      }
      expect(callSites, hasLength(1), reason: '呼叫點：$callSites');
      final only = File(callSites.single.split('@').first).readAsStringSync();
      expect(
        only,
        contains('selectFinancialBacklog('),
        reason: '目標清單必須由單一入口算出，不能在呼叫點自己拼',
      );
    },
  );

  test('🚨 舊的兩條佇列與配額拆分不得復活', () {
    final revived = <String>[];
    for (final f in libFiles) {
      final src = f.readAsStringSync();
      for (final banned in const [
        'selectFinancialSyncTargets',
        'selectOtcFinancialBacklog',
        'selectOtcFinancialTargets',
        'otcFinancialLimitForBudget',
        'otcFinancialSyncMaxCount',
        'financialSyncMaxCandidates',
      ]) {
        if (src.contains(banned)) revived.add('${f.path}: $banned');
      }
    }
    expect(revived, isEmpty);
  });
}
