import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/data/models/tpex/tpex_industry_eps.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/industry_eps_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class _MockTpexClient extends Mock implements TpexClient {}

void main() {
  testWidgets('🚨 幽靈 reload:畫面關閉且 keepAlive 窗過期後,epoch bump 不得再打 API', (
    tester,
  ) async {
    // 2026-08-29 稽核實證:provider keepAlive + epoch listener 無 guard
    // → 進過一次畫面後,**每次每日更新都打一次 TPEx API 直到 app 關掉**。
    // 註解寫「畫面開著時自動 reload」,程式碼是「永遠」。修法照 epoch
    // provider 文件的規約 #2(listener 不加條件判斷)——生命週期交給
    // autoDispose:畫面關閉 → provider dispose → listener 消失。
    final mock = _MockTpexClient();
    when(() => mock.getIndustryEps()).thenAnswer((_) async => const []);

    final watching = ValueNotifier(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tpexClientProvider.overrideWithValue(mock)],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: watching,
            builder: (context, isWatching, _) => isWatching
                ? Consumer(
                    builder: (context, ref, _) {
                      ref.watch(industryEpsProvider);
                      return const SizedBox();
                    },
                  )
                : const SizedBox(),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );

    // 模擬畫面進入:主動載入一次
    await container.read(industryEpsProvider.notifier).loadData();
    verify(() => mock.getIndustryEps()).called(1);

    // 畫面開著時 bump → 自動 reload(這是 M6 follow-up 的正當行為,釘住)
    container.read(dataUpdateEpochProvider.notifier).bump();
    await tester.pump();
    verify(() => mock.getIndustryEps()).called(1);

    // 畫面關閉(listener 移除)+ keepAlive 窗過期 → provider 應 dispose
    watching.value = false;
    await tester.pump();
    await tester.pump(
      const Duration(minutes: ApiConfig.keepAliveMin, seconds: 5),
    );

    // 之後的每日更新 bump 不得再喚起任何 API 呼叫
    container.read(dataUpdateEpochProvider.notifier).bump();
    await tester.pump();
    verifyNever(() => mock.getIndustryEps());
  });

  testWidgets('keepAlive 窗內返回畫面沿用快取,不重打 API', (tester) async {
    final mock = _MockTpexClient();
    when(() => mock.getIndustryEps()).thenAnswer(
      (_) async => const [
        TpexIndustryEps(
          symbol: '6488',
          companyName: '環球晶',
          industry: '半導體',
          eps: 10.5,
          year: 2026,
          quarter: 2,
          revenue: 0,
          operatingProfit: 0,
          netIncome: 0,
        ),
      ],
    );
    final watching = ValueNotifier(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tpexClientProvider.overrideWithValue(mock)],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: watching,
            builder: (context, isWatching, _) => isWatching
                ? Consumer(
                    builder: (context, ref, _) {
                      ref.watch(industryEpsProvider);
                      return const SizedBox();
                    },
                  )
                : const SizedBox(),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(industryEpsProvider.notifier).loadData();

    // 離開畫面 30 秒後回來(窗內)——資料還在,不需重載
    watching.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    watching.value = true;
    await tester.pump();

    expect(
      container.read(industryEpsProvider).allData,
      isNotEmpty,
      reason: '3 分鐘 keepAlive 窗內返回應沿用快取(與 stock_detail 同一樣板)',
    );
    verify(() => mock.getIndustryEps()).called(1);
  });
}
