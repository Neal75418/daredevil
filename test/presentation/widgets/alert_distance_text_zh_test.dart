import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/widgets/alert_distance_text.dart';

/// 供給預先讀好的翻譯 map（避開 rootBundle 在 fake async 下不 resolve）
class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

/// 已掛提醒的距離文字,以真實 zh-TW 翻譯斷言整句(2026-10-06,路線圖第 2 項)。
///
/// 一般測試的 `.tr()` 只回 key,看不到百分比有沒有代進「距現價 {percent}」;
/// 參數名或翻譯的佔位字拼錯,畫面會直接露出「{percent}」。真實翻譯會寫進
/// 全域狀態,所以獨立成一個檔案。
void main() {
  late Map<String, dynamic> zhTw;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
    zhTw =
        json.decode(await File('assets/translations/zh-TW.json').readAsString())
            as Map<String, dynamic>;
  });

  PriceAlertEntry below(double target) => PriceAlertEntry(
    id: 1,
    symbol: '2330',
    alertType: 'BELOW',
    targetValue: target,
    isActive: true,
    createdAt: DateTime(2026, 10, 6),
  );

  testWidgets('🚨 「距現價 -2.0%」與「已達到」整句正確', (tester) async {
    final texts = <String?>[];
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
            home: Builder(
              builder: (context) {
                texts
                  ..clear()
                  ..addAll([
                    AlertDistanceText.forAlert(below(98), 100),
                    AlertDistanceText.forAlert(below(98), 97),
                  ]);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(texts, ['距現價 -2.0%', '已達到']);
  });
}
