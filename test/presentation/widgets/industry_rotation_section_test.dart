import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/industry_ranking.dart';
import 'package:daredevil/presentation/providers/industry_ranking_provider.dart';
import 'package:daredevil/presentation/widgets/industry_ranking_section.dart';

import '../../helpers/widget_test_helpers.dart';

/// 族群轉向的呈現(2026-08-11)。
///
/// 這個模式的存在理由:既有排行只給單一窗口的**水準值**,看不出資金往哪
/// 移動。2026-08-10 實測半導體 20日排第 34、5日排第 1——躍升 +33 才是訊號。
void main() {
  setUpAll(() async => setupTestLocalization());

  void widen(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(tester.view.resetPhysicalSize);
  }

  IndustryRotation rot({
    required String industry,
    required int jump,
    required RotationCategory category,
    int strongList = 3,
    int rank5 = 1,
    int rank20 = 34,
  }) => IndustryRotation(
    industry: industry,
    memberCount: 200,
    rankJump: jump,
    rank5d: rank5,
    rank20d: rank20,
    ret5dPct: 7.2,
    ret20dPct: -13.6,
    category: category,
    strongListCount: strongList,
    topMembers: const [
      IndustryMember(symbol: '2330', name: '台積電', retPct: 20),
      IndustryMember(symbol: '2454', name: '聯發科', retPct: 5),
    ],
    strongListSymbols: const {'2330'},
  );

  Widget app(List<IndustryRotation> rows) => ProviderScope(
    overrides: [
      industryRotationProvider.overrideWith((ref) async => rows),
      // 必須給 d20 一筆:整個 section 在排行為空時會收起來(輔助發現層
      // 的設計),按鈕跟著消失,測試就點不到「轉向」
      industryRankingProvider.overrideWith(
        (ref, window) async => [
          const IndustryRanking(
            industry: '佔位',
            momentumPct: 1,
            memberCount: 5,
            institutionalNetShares: 0,
            topMembers: [],
            advancingRatio: 0.5,
          ),
        ],
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: IndustryRankingSection())),
  );

  Future<void> switchToRotation(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('today.industryRotation'));
    await tester.pumpAndSettle();
    // ⚠️ 吃掉 RenderFlex 溢出:測試環境不載入翻譯,`.tr()` 渲染的是原始 key,
    // 而 key 比中文寬得多(`today.rotationJump` 288px vs「+33 名」80px)。
    // 那個溢出在產品裡不存在——真實中文的寬度預算由下方獨立的測試守。
    // 這裡若不吃掉,所有 widget 測試都會因為假溢出而紅。
    tester.takeException();
  }

  testWidgets('🚨 口徑字幕在排行與轉向視圖都渲染(2026-08-13 合併產業表現區塊)', (tester) async {
    // 原「產業表現」(當日·等權·分市場)與本排行(中位數·合併)口徑互撞:
    // 上櫃金融同屏 +4.37% vs −1.3%。合併後由這行字幕把口徑說清楚——
    // 它就是防止「跟官方指數對不上=壞掉」誤解的唯一防線。
    widen(tester);
    await tester.pumpWidget(
      app([
        rot(
          industry: '半導體業',
          jump: 33,
          category: RotationCategory.reboundFromDeep,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('today.industryRankingScope'), findsOneWidget);

    await tester.tap(find.text('today.industryRotation'));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(find.text('today.industryRankingScope'), findsOneWidget);
  });

  testWidgets('🚨 「今日」tab 存在且可切換(d1 視窗)', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        rot(
          industry: '半導體業',
          jump: 33,
          category: RotationCategory.reboundFromDeep,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('today.industryWindow1d'), findsOneWidget);
    await tester.tap(find.text('today.industryWindow1d'));
    await tester.pumpAndSettle();
    tester.takeException();
    // 排行清單仍渲染(overrideWith 對所有 window 回同一組資料)
    expect(find.text('today.industryRankingScope'), findsOneWidget);
  });

  testWidgets('切到轉向後顯示躍升名次與分類', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        rot(
          industry: '半導體業',
          jump: 33,
          category: RotationCategory.reboundFromDeep,
        ),
      ]),
    );
    await switchToRotation(tester);
    expect(find.textContaining('半導體業'), findsOneWidget);
    // 用 Key 而非文字:測試環境不載入翻譯,`.tr()` 不做參數替換
    expect(
      find.byKey(const Key('rotationJump.33')),
      findsOneWidget,
      reason: '躍升是主角,必須渲染出來',
    );
  });

  testWidgets('🚨 強者榜 0 檔的卡片要淡化——點進去也沒東西可買', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        rot(
          industry: '化學工業',
          jump: 24,
          category: RotationCategory.reboundFromDeep,
          strongList: 0,
        ),
        rot(
          industry: '半導體業',
          jump: 33,
          category: RotationCategory.reboundFromDeep,
          strongList: 8,
        ),
      ]),
    );
    await switchToRotation(tester);

    // 2026-08-10:化學工業躍升 +24 名但強者榜 0 檔,點進去空的。
    // 淡化讓使用者掃過去自然跳過,不必逐張讀數字。
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .map((o) => o.opacity)
        .toList();
    expect(opacities.any((o) => o < 0.6), isTrue, reason: '0 檔的卡片必須淡化');
    expect(opacities.any((o) => o == 1.0), isTrue, reason: '有成員的卡片不可被一起淡化');
  });

  testWidgets('🚨 沒有「持續強勢」時顯示說明卡,不可整個藏起來', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        rot(
          industry: '半導體業',
          jump: 33,
          category: RotationCategory.reboundFromDeep,
        ),
      ]),
    );
    await switchToRotation(tester);
    // 「沒有任何族群持續強勢」本身就是市場狀態(崩跌後常態)。
    // 藏起來會讓使用者以為功能壞了。
    expect(find.text('today.rotationNoSustained'), findsOneWidget);
  });

  testWidgets('有持續強勢時不顯示說明卡', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        rot(industry: '通信網路業', jump: 8, category: RotationCategory.sustained),
      ]),
    );
    await switchToRotation(tester);
    expect(find.text('today.rotationNoSustained'), findsNothing);
  });

  testWidgets('neutral 不顯示——轉向視角下沒有資訊', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      app([
        rot(industry: '甲', jump: 1, category: RotationCategory.neutral),
        rot(
          industry: '乙',
          jump: 33,
          category: RotationCategory.reboundFromDeep,
        ),
      ]),
    );
    await switchToRotation(tester);
    expect(find.textContaining('甲'), findsNothing);
    expect(find.textContaining('乙'), findsOneWidget);
  });

  test('🚨 卡片寬度預算:真實中文必須放得下', () {
    // ⚠️ **不能用 widget 測試驗版面**:測試環境不載入翻譯,`.tr()` 回傳的是
    // 原始 key,而 key 比中文寬得多——實測 `today.rotationJump` 288px vs
    // 「+33 名」80px。卡片可用寬度 186px,於是 widget 測試必然報溢出,
    // 而那個溢出在產品裡不存在。
    //
    // 2026-08-08 曾用 widget 溢出測試掃全專案,22 條「爆版」幾乎全是這個
    // 假象。所以這裡改成直接量**真實中文**的寬度預算——它測的是產品實際
    // 會渲染的東西,不受翻譯載入與否影響。
    double width(String text, TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    const cardWidth = 210.0;
    const padding = 12.0 * 2;
    const budget = cardWidth - padding;

    const title = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    const small = TextStyle(fontSize: 11);

    // 各行最長的實際內容(取自 2026-08-10 真實資料)
    final lines = <String, double>{
      '1 電腦及週邊設備業': width(
        '1 電腦及週邊設備業',
        const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      '+33 名 🔄 跌深反彈': width('+33 名', title) + 8 + width('🔄 跌深反彈', small),
      '5日#1  20日#34': width('5日#1  20日#34', small),
      '強者榜 8 檔': width('強者榜 8 檔', small),
    };
    for (final e in lines.entries) {
      expect(
        e.value,
        lessThanOrEqualTo(budget),
        reason:
            '「${e.key}」需 ${e.value.toStringAsFixed(0)}px,'
            '超過卡片可用的 ${budget.toStringAsFixed(0)}px',
      );
    }
  });
}
