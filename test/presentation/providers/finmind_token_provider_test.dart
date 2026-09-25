import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/repositories/settings_repository.dart';

import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';

/// FinMind client 會因設定變更被 invalidate 重建（存／清 token、改快取時間）。
/// 原本 token 只在 app 啟動時設一次在「當時那個」client 上，重建後的 client
/// 是匿名的——額度從 600/hr 掉到 300/hr，要 token 的資料集失敗，直到重開 app。
class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  const token = 'eyJhbGciOiJIUzI1NiJ9.payload_long_enough.sig';

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [cacheDurationProvider.overrideWithValue(30)],
    );
    addTearDown(container.dispose);
  });

  test('client 帶著目前的 token', () {
    container.read(finMindTokenProvider.notifier).set(token);
    expect(container.read(finMindClientProvider).token, token);
  });

  test('🚨 client 被 invalidate 重建（例如改快取時間）後仍帶 token', () {
    container.read(finMindTokenProvider.notifier).set(token);
    final before = container.read(finMindClientProvider);

    container.invalidate(finMindClientProvider);
    final after = container.read(finMindClientProvider);

    expect(identical(before, after), isFalse, reason: '前提：真的重建了');
    expect(after.token, token);
  });

  test('🚨 存入新 token 後，client 立即改用新 token（不必重開 app）', () {
    final anonymous = container.read(finMindClientProvider);
    expect(anonymous.hasToken, isFalse, reason: '前提：一開始沒有 token');

    container.read(finMindTokenProvider.notifier).set(token);

    expect(container.read(finMindClientProvider).token, token);
  });

  test('清除 token 後，client 回到匿名', () {
    container.read(finMindTokenProvider.notifier).set(token);
    container.read(finMindTokenProvider.notifier).set(null);

    expect(container.read(finMindClientProvider).hasToken, isFalse);
  });

  // 原本 main 以 `client.token = token` 設定，setter 會驗格式；改走 provider
  // 後這道驗證必須還在。來源之一是 FINMIND_TOKEN 環境變數（repository 註明
  // 不 trim），帶換行的 token 放進 header 會讓每個請求都失敗，且錯誤字串
  // 內含 token 原文。
  test('🚨 格式無效的 token（例如尾端換行）以匿名模式運作，不放進 header', () {
    container.read(finMindTokenProvider.notifier).set('$token\n');

    expect(container.read(finMindTokenProvider), isNull);
    expect(container.read(finMindClientProvider).hasToken, isFalse);
  });

  group('啟動時從安全儲存載入', () {
    late MockSettingsRepository repo;
    setUp(() => repo = MockSettingsRepository());

    test('🚨 載入後 client 帶著 token', () async {
      when(() => repo.getFinMindToken()).thenAnswer((_) async => token);

      await container.read(finMindTokenProvider.notifier).loadFrom(repo);

      expect(container.read(finMindClientProvider).token, token);
    });

    test('儲存區沒有 token → 匿名', () async {
      when(() => repo.getFinMindToken()).thenAnswer((_) async => null);

      await container.read(finMindTokenProvider.notifier).loadFrom(repo);

      expect(container.read(finMindClientProvider).hasToken, isFalse);
    });

    test('讀取失敗不影響啟動，以匿名模式運作', () async {
      when(
        () => repo.getFinMindToken(),
      ).thenThrow(Exception('keychain locked'));

      await container.read(finMindTokenProvider.notifier).loadFrom(repo);

      expect(container.read(finMindTokenProvider), isNull);
    });
  });
}
