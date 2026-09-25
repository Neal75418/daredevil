import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/presentation/screens/today/widgets/signal_card_guide_sheet.dart';
import 'package:daredevil/presentation/widgets/score_tier_badge.dart';
import 'package:daredevil/presentation/widgets/stock_card_sparkline.dart';

/// 供給預先讀好的翻譯 map（避開 rootBundle 在 fake async 下不 resolve）
class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

/// 說明裡的門檻與天數由程式常數帶入：載入真實 zh-TW 翻譯斷言整句，
/// 常數一改、說明跟著改（寫死數字會和實際門檻脫節）。
void main() {
  late Map<String, dynamic> zhTw;
  late Map<String, dynamic> en;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
    zhTw =
        json.decode(await File('assets/translations/zh-TW.json').readAsString())
            as Map<String, dynamic>;
    en =
        json.decode(await File('assets/translations/en.json').readAsString())
            as Map<String, dynamic>;
  });

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'TW'),
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: [locale],
        path: 'assets/translations',
        fallbackLocale: locale,
        startLocale: locale,
        assetLoader: _PreloadedAssetLoader(
          locale.languageCode == 'en' ? en : zhTw,
        ),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const Scaffold(body: SignalCardGuideSheet()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('標題與四段說明', (tester) async {
    await pump(tester);
    expect(find.text('訊號卡怎麼看'), findsOneWidget);
    expect(find.text('強／中／弱／觀察'), findsOneWidget);
    expect(find.text('5日／60日'), findsOneWidget);
    expect(find.text('數字'), findsOneWidget);
    expect(find.text('卡片上的其他資訊'), findsOneWidget);
  });

  testWidgets('分級門檻來自 RuleParams', (tester) async {
    await pump(tester);
    const strong = RuleParams.tierStrongThreshold;
    const medium = RuleParams.tierMediumThreshold;
    const weak = RuleParams.minScoreThreshold;
    expect(
      find.textContaining(
        '強 ≥$strong、中 $medium–${strong - 1}、弱 $weak–${medium - 1}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('不是漲跌預測'), findsOneWidget);
    // 今日卡也可能出現「觀察」（路由門檻低於訊號層），說明不能漏
    expect(find.textContaining('觀察：低於 $weak'), findsOneWidget);
  });

  // 60日幾乎全是預設權重、5日把回測差的條件歸零：不能說成「分別校準」
  testWidgets('5日／60日：兩套權重、取較高者，不宣稱分別校準', (tester) async {
    await pump(tester);
    expect(find.textContaining('取 5日、60日兩套權重算出的分數中較高者'), findsOneWidget);
    expect(find.textContaining('其餘沿用預設'), findsOneWidget);
    expect(find.textContaining('分別以過去'), findsNothing);
  });

  testWidgets('附四個級距（含觀察）的實際徽章樣式', (tester) async {
    await pump(tester);
    final scores = tester
        .widgetList<ScoreTierBadge>(find.byType(ScoreTierBadge))
        .map((b) => b.shortScore)
        .toList();
    expect(scores, [
      RuleParams.tierStrongThreshold.toDouble(),
      RuleParams.tierMediumThreshold.toDouble(),
      RuleParams.minScoreThreshold.toDouble(),
      RuleParams.minScoreThreshold - 1.0,
    ]);
  });

  testWidgets('走勢圖天數來自 MiniSparkline', (tester) async {
    await pump(tester);
    // 缺值收盤會被略過，所以是「最近 N 筆」而非「N 個交易日」
    expect(
      find.textContaining('最近 ${MiniSparkline.maxDataPoints} 筆收盤'),
      findsOneWidget,
    );
    expect(find.textContaining('持平為灰色'), findsOneWidget);
    expect(find.textContaining('價格欄是最新收盤價與當日漲跌幅'), findsOneWidget);
  });

  testWidgets('附短版免責聲明', (tester) async {
    await pump(tester);
    expect(find.textContaining('不構成投資建議'), findsOneWidget);
  });

  // en 的佔位符若與程式傳入的名稱對不上，會原樣顯示「{strong}」而不報錯
  testWidgets('en：所有佔位符都被替換', (tester) async {
    await pump(tester, locale: const Locale('en'));
    expect(find.text('How to read a signal card'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
    expect(
      find.textContaining('Strong ≥${RuleParams.tierStrongThreshold}'),
      findsOneWidget,
    );
  });
}
