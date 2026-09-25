import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/domain/services/update/history_coverage.dart';
import 'package:daredevil/presentation/screens/today/widgets/history_building_banner.dart';

/// 供給預先讀好的翻譯 map（避開 rootBundle 在 fake async 下不 resolve）
class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

/// 百分比與剩餘次數是這個提示的全部資訊；一般測試的 .tr() 只回 key，
/// 所以載入真實 zh-TW 翻譯斷言整句。
void main() {
  late Map<String, dynamic> zhTw;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    zhTw =
        json.decode(await File('assets/translations/zh-TW.json').readAsString())
            as Map<String, dynamic>;
  });

  testWidgets('顯示建置百分比與約需的更新次數', (tester) async {
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
            home: const Scaffold(
              body: HistoryBuildingBanner(
                coverage: HistoryCoverage(covered: 120, total: 540),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 120/540 = 22%；缺 420 ÷ 單次 30 = 14 次
    expect(find.textContaining('22%'), findsOneWidget);
    expect(find.textContaining('14 次'), findsOneWidget);
  });
}
