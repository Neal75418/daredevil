import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/logger.dart';

/// logger 是 Sentry breadcrumb 與 CLI 日誌的共同出口，遮罩要在這裡做，
/// 不能指望 600+ 個呼叫點各自小心。
void main() {
  const secret = 'eyJhbGciOiJIUzI1NiJ9.secretpayload.sig';
  final error = Exception('uri = https://x/api?dataset=A&token=$secret');

  tearDown(() {
    AppLogger.setSentryDelegates();
    AppLogger.forceOutput = false;
  });

  test('🚨 warning 的 breadcrumb data 不帶 token', () {
    final crumbs = <Map<String, dynamic>?>[];
    AppLogger.setSentryDelegates(
      breadcrumb: (message, category, level, data) => crumbs.add(data),
    );

    AppLogger.warning('FinMind', '請求失敗', error);

    expect(crumbs.single!['error'], isNot(contains(secret)));
    expect(crumbs.single!['error'], contains('token=***'));
  });

  test('🚨 CLI 日誌（forceOutput）印出的 Error 行不帶 token', () {
    AppLogger.forceOutput = true;
    final out = <String>[];
    runZoned(
      () => AppLogger.warning('FinMind', '請求失敗', error),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => out.add(line),
      ),
    );

    expect(out.join('\n'), contains('token=***'));
    expect(out.join('\n'), isNot(contains(secret)));
  });

  test('🚨 呼叫端把例外插進 message（\'失敗: \$e\'）也要遮', () {
    AppLogger.forceOutput = true;
    final crumbs = <String>[];
    AppLogger.setSentryDelegates(
      breadcrumb: (message, category, level, data) => crumbs.add(message),
    );
    final out = <String>[];
    runZoned(
      () => AppLogger.warning('Update', '同步失敗: $error'),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => out.add(line),
      ),
    );

    expect(out.join('\n'), isNot(contains(secret)));
    expect(crumbs.single, isNot(contains(secret)));
  });

  test('🚨 error 上報時附帶的 message 不帶 token', () {
    final messages = <String>[];
    AppLogger.setSentryDelegates(
      capture: (error, stackTrace, tag, message) => messages.add(message),
    );

    AppLogger.error('Update', '同步失敗: $error', error);

    expect(messages.single, isNot(contains(secret)));
  });
}
