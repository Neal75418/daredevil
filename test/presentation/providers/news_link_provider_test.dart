import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  isActive: true,
  updatedAt: DateTime(2026, 10, 6),
);

void main() {
  test('用有效股票建顯示用比對器，每日更新後重建', () async {
    final db = MockAppDatabase();
    when(
      () => db.getAllActiveStocks(),
    ).thenAnswer((_) async => [stock('9901', '甲乙')]);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(newsLinkMatcherProvider, (_, _) {});
    addTearDown(sub.close);

    final m = await container.read(newsLinkMatcherProvider.future);
    expect(m.match('甲乙營收'), {'9901'}); // 2 字名預設收＝顯示用建法

    container.read(dataUpdateEpochProvider.notifier).bump();
    await container.read(newsLinkMatcherProvider.future);
    verify(() => db.getAllActiveStocks()).called(2);
  });
}
