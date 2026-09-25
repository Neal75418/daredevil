import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:daredevil/app/sentry_redaction.dart';

/// Sentry 的最後一道關卡：captureException 直接送例外物件，不經 logger
/// 的字串遮罩，所以 beforeSend 也要遮。
void main() {
  const secret = 'eyJhbGciOiJIUzI1NiJ9.secretpayload.sig';
  const leaky = 'uri = https://x/api?dataset=A&token=$secret';

  test('🚨 beforeSend 遮掉例外訊息、事件訊息、breadcrumb 內的 token', () {
    final event = SentryEvent(
      exceptions: [SentryException(type: 'DioException', value: leaky)],
      message: SentryMessage(leaky),
      breadcrumbs: [
        Breadcrumb(message: leaky, data: {'error': leaky, 'count': 3}),
      ],
    );

    final out = redactSentryEvent(event);

    expect(out.exceptions!.single.value, isNot(contains(secret)));
    expect(out.message!.formatted, isNot(contains(secret)));
    expect(out.breadcrumbs!.single.message, isNot(contains(secret)));
    expect(out.breadcrumbs!.single.data!['error'], isNot(contains(secret)));
    expect(out.breadcrumbs!.single.data!['count'], 3, reason: '非字串值原樣保留');
  });

  test('beforeBreadcrumb 遮掉 message 與字串 data', () {
    final out = redactBreadcrumb(
      Breadcrumb(message: leaky, data: {'error': leaky}),
    );
    expect(out!.message, isNot(contains(secret)));
    expect(out.data!['error'], isNot(contains(secret)));
  });

  test('null breadcrumb 原樣回傳 null', () {
    expect(redactBreadcrumb(null), isNull);
  });
}
