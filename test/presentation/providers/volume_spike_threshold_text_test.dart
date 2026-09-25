import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/notification_provider.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';

/// 供給預先讀好的翻譯 map（避開 rootBundle 在 fake async 下不 resolve）
class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

/// 爆量提醒的倍數是固定門檻（[AlertParams.volumeSpikeMultiplier]），不存在
/// targetValue：對話框對它一律存 0，舊版則會存成現價。說明與通知若讀
/// targetValue，會寫出「0 倍」或「850 倍」。
///
/// 一般單元測試的 `.tr()` 只回傳 key，看不到插入的數字，所以這裡載入真實
/// zh-TW 翻譯。
void main() {
  late Map<String, dynamic> zhTw;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    zhTw =
        json.decode(await File('assets/translations/zh-TW.json').readAsString())
            as Map<String, dynamic>;
  });

  PriceAlertEntry spikeAlert(double targetValue) => PriceAlertEntry(
    id: 1,
    symbol: '2330',
    alertType: AlertParams.typeVolumeSpike,
    targetValue: targetValue,
    isActive: true,
    createdAt: DateTime(2026, 9, 1),
  );

  testWidgets('說明與通知顯示固定倍數,與 targetValue 無關', (tester) async {
    final texts = <String>[];
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'TW')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh', 'TW'),
        startLocale: const Locale('zh', 'TW'),
        assetLoader: _PreloadedAssetLoader(zhTw),
        // 翻譯要經 MaterialApp 的 localizationsDelegates 才會真正載入
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
                    for (final target in [0.0, 850.0]) ...[
                      getAlertDescription(
                        spikeAlert(target),
                        AlertType.volumeSpike,
                      ),
                      NotificationNotifier.getAlertBody(
                        spikeAlert(target),
                        AlertType.volumeSpike,
                        null,
                      ),
                    ],
                  ]);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final multiplier = AlertParams.volumeSpikeMultiplier.toStringAsFixed(0);
    String render(String template) =>
        template.replaceAll('{value}', multiplier);
    final desc = render(
      ((zhTw['alert'] as Map)['desc'] as Map)['volumeSpike'] as String,
    );
    final body = render(
      (zhTw['notification'] as Map)['volumeSpikeBody'] as String,
    );
    expect(texts, [desc, body, desc, body], reason: 'targetValue 為 0 與 850 皆同');
  });
}
