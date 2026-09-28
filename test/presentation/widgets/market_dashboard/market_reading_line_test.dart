import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/domain/services/market_reading_service.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_reading_line.dart';

class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.byLocale);

  final Map<String, Map<String, dynamic>> byLocale;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      byLocale[locale.toString()]!;
}

void main() {
  const zh = Locale('zh', 'TW');
  const en = Locale('en');
  late Map<String, Map<String, dynamic>> translations;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
    Future<Map<String, dynamic>> read(String name) async =>
        json.decode(await File('assets/translations/$name').readAsString())
            as Map<String, dynamic>;
    translations = {
      'zh_TW': await read('zh-TW.json'),
      'en': await read('en.json'),
    };
  });

  group('formatReadingAmount', () {
    test('中文以億、取整數', () {
      expect(formatReadingAmount(3_500_000_000, zh), '35 億');
    });

    test('英文走 K/M/B：35 億 = 3.5 billion，不是 35 billion', () {
      expect(formatReadingAmount(3_500_000_000, en), '3.5B');
    });
  });

  group('背離判讀句以真實翻譯渲染金額', () {
    const reading = MarketReading(
      messageKey: 'marketOverview.reading.synthesis.extremeDownDivergence',
      tone: InterpretationTone.negative,
      args: {'pct': '7.02', 'breadthPct': '70'},
      amountArgs: {'netAmount': 3_500_000_000},
    );

    Future<String> render(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [zh, en],
          path: 'assets/translations',
          fallbackLocale: zh,
          startLocale: locale,
          saveLocale: false,
          assetLoader: _PreloadedAssetLoader(translations),
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const Scaffold(body: MarketReadingLine(reading: reading)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
    }

    testWidgets('中文：法人合計買超 35 億', (tester) async {
      expect(await render(tester, zh), contains('法人合計買超 35 億與指數背離'));
    });

    testWidgets('英文：net buying of 3.5B', (tester) async {
      expect(
        await render(tester, en),
        contains('institutional net buying of 3.5B diverges'),
      );
    });
  });
}
