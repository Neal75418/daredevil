// scripts/ 與文件的雙向守門（2026-08-22）
//
// **為什麼需要**：`scripts/calibrate.sh` + `calibrate-retry.sh` 曾有 6 週
// 沒有任何現行文件指向（只有 `docs/plans/` 的歷史設計檔提到），審計時第一
// 眼看起來像死碼。反過來，文件指向已刪除的腳本則會讓人照著跑然後撞
// "No such file"。兩個方向都靜默——沒有測試會紅、沒有錯誤訊息。
//
// 守門守的是「可發現性」，不是內容正確性：
//   1. 每支非 hook 的 script 至少被一份現行文件提到（否則等於藏起來）
//   2. 文件提到的每支 script 都真的存在
//
// hook 三件套（pre-commit / post-commit / install-hooks.sh）豁免自動掃描，
// 它們由 CLAUDE.md「Git Hooks」章節涵蓋，且不是給人手動跑的入口。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// hook 鏈：由 `install-hooks.sh` 安裝、CLAUDE.md 記載，不需個別文件入口
  const hookScripts = {'pre-commit', 'post-commit', 'install-hooks.sh'};

  /// 只算現行文件——`docs/plans/` 是歷史設計檔，提到不代表還能跑
  List<File> currentDocs() => [
    File('CLAUDE.md'),
    File('README.md'),
    ...Directory(
      'docs',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.md')),
  ].where((f) => f.existsSync()).toList();

  String allDocText() =>
      currentDocs().map((f) => f.readAsStringSync()).join('\n');

  test('🚨 每支可手動執行的 script 都有現行文件指向（否則等同藏起來）', () {
    final scripts = Directory('scripts')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => !hookScripts.contains(name))
        .toList();

    expect(scripts, isNotEmpty, reason: '前提：scripts/ 應有非 hook 腳本');

    final docText = allDocText();
    final undocumented = scripts
        .where((name) => !docText.contains('scripts/$name'))
        .toList();

    expect(
      undocumented,
      isEmpty,
      reason:
          '這些腳本沒有任何現行文件提到，下次審計會被當成死碼：$undocumented\n'
          '請在對應的 docs/*.md 或 CLAUDE.md 補上執行方式。',
    );
  });

  test('🚨 文件提到的 script 都真的存在（不得指向已刪除的檔案）', () {
    final referenced = RegExp(
      r'scripts/([A-Za-z0-9._-]+)',
    ).allMatches(allDocText()).map((m) => m.group(1)!).toSet();

    expect(referenced, isNotEmpty, reason: '前提：文件應提到至少一支腳本');

    final missing = referenced
        .where((name) => !File('scripts/$name').existsSync())
        .toList();

    expect(missing, isEmpty, reason: '文件指向不存在的腳本：$missing');
  });
}
