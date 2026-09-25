import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/presentation/screens/today/widgets/data_stale_banner.dart';

/// 供給預先讀好的翻譯 map（避開 rootBundle 在 fake async 下不 resolve）
class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

/// 一般 widget 測試的 `.tr()` 只回 key、看不到參數；落後天數與日期是這個
/// 提示的全部資訊，所以載入真實 zh-TW 翻譯斷言整句。
void main() {
  late Map<String, dynamic> zhTw;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    zhTw =
        json.decode(await File('assets/translations/zh-TW.json').readAsString())
            as Map<String, dynamic>;
  });

  Future<void> pump(WidgetTester tester, VoidCallback onUpdate) async {
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
            home: Scaffold(
              body: DataStaleBanner(
                dataDate: DateTime(2026, 9, 14),
                tradingDaysBehind: 4,
                onUpdate: onUpdate,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('顯示落後的交易日數與最新資料日', (tester) async {
    await pump(tester, () {});
    expect(find.text('資料落後 4 個交易日（最新 9/14 收盤）'), findsOneWidget);
  });

  testWidgets('點「立即更新」觸發更新', (tester) async {
    var calls = 0;
    await pump(tester, () => calls++);

    await tester.tap(find.text('立即更新'));
    expect(calls, 1);
  });
}
