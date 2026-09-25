import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/repositories/settings_repository.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/settings/widgets/api_token_tile.dart';

import '../../../../helpers/widget_test_helpers.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

/// 設定頁存／清 token 必須更新記憶體中的 [finMindTokenProvider]；只寫進
/// 安全儲存的話，App 內的 FinMind client 要到重開才拿得到新 token。
void main() {
  const token = 'eyJhbGciOiJIUzI1NiJ9.payload_long_enough.sig';

  setUpAll(() async {
    await setupTestLocalization();
  });

  late MockSettingsRepository repo;
  late ProviderContainer container;

  Future<void> pumpTile(WidgetTester tester, {required bool hasToken}) async {
    repo = MockSettingsRepository();
    when(() => repo.hasFinMindToken()).thenAnswer((_) async => hasToken);
    when(() => repo.setFinMindToken(any())).thenAnswer((_) async {});
    when(() => repo.clearFinMindToken()).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ApiTokenTile())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🚨 存入 token 後，App 內立即生效', (tester) async {
    await pumpTile(tester, hasToken: false);

    await tester.tap(find.text('settings.apiToken'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), token);
    await tester.pump();
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    verify(() => repo.setFinMindToken(token)).called(1);
    expect(container.read(finMindTokenProvider), token);
  });

  testWidgets('刪除 token 後，App 內立即回到匿名', (tester) async {
    await pumpTile(tester, hasToken: true);
    container.read(finMindTokenProvider.notifier).set(token);

    await tester.tap(find.text('settings.apiToken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('common.delete'));
    await tester.pumpAndSettle();

    verify(() => repo.clearFinMindToken()).called(1);
    expect(container.read(finMindTokenProvider), isNull);
  });
}
