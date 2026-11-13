import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/widgets/live_quote_status.dart';

import '../../helpers/provider_test_helpers.dart';
import '../../helpers/widget_test_helpers.dart';

/// 頁首狀態的中文全文(載入真實翻譯;翻譯寫入全域,所以獨立一檔)。
void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  testWidgets('報價延遲:寫出證交所資料停在哪個時刻', (tester) async {
    await tester.pumpWidget(
      buildProviderTestApp(
        Builder(
          builder: (_) => Text(
            const LiveHeaderStatus(LiveHeaderKind.delayed, '10:25:59').text(),
          ),
        ),
        zhTranslations: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('報價延遲（證交所資料停在 10:25:59）'), findsOneWidget);
  });
}
