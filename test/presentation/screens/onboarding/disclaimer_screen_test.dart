import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/screens/onboarding/disclaimer_screen.dart';

import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  Future<void> pump(WidgetTester tester, VoidCallback onAccept) => tester
      .pumpWidget(MaterialApp(home: DisclaimerScreen(onAccept: onAccept)));

  testWidgets('列出全部四點聲明', (tester) async {
    await pump(tester, () {});
    for (final key in [
      'disclaimer.intro',
      'disclaimer.point1',
      'disclaimer.point2',
      'disclaimer.point3',
      'disclaimer.point4',
    ]) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
  });

  testWidgets('按下同意才回呼', (tester) async {
    var accepted = 0;
    await pump(tester, () => accepted++);
    expect(accepted, 0);

    await tester.tap(find.text('disclaimer.accept'));
    expect(accepted, 1);
  });

  // 一般測試的 .tr() 只回傳 key（很短），看不出長條款會不會溢位，
  // 所以這條載入真實 zh-TW 翻譯。
  testWidgets('字級放大到 2 倍也不溢位（條款可捲動）', (tester) async {
    final zhTw =
        json.decode(File('assets/translations/zh-TW.json').readAsStringSync())
            as Map<String, dynamic>;
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'TW')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh', 'TW'),
        startLocale: const Locale('zh', 'TW'),
        assetLoader: _PreloadedAssetLoader(zhTw),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: MediaQuery.withClampedTextScaling(
              minScaleFactor: 2,
              maxScaleFactor: 2,
              child: DisclaimerScreen(onAccept: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('不是證券投資顧問'),
      findsOneWidget,
      reason: '前提：真實翻譯已載入',
    );
    expect(tester.takeException(), isNull);
  });
}

class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}
