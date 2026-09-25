import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// golden 圖依平台字型渲染，CI（Linux）以 `--exclude-tags golden` 排除。
/// 漏標 `@Tags(['golden'])` 的 golden 測試會在 CI 跑、必然像素不符而紅燈
/// （2026-09-25 大盤總覽頁 golden 首次推上去即紅）。
void main() {
  test("用到 matchesGoldenFile 的測試檔都標了 @Tags(['golden'])", () {
    final goldenFiles = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .where((f) => f.readAsStringSync().contains('matchesGoldenFile('))
        .toList();

    // 下限：路徑或比對寫錯時會掃到 0 個、無聲通過
    expect(goldenFiles.length, greaterThanOrEqualTo(6));

    final untagged = [
      for (final f in goldenFiles)
        if (!f.readAsStringSync().contains("@Tags(['golden'])")) f.path,
    ];
    expect(untagged, isEmpty, reason: '這些 golden 測試會在 CI 跑：$untagged');
  });
}
