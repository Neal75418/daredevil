import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:daredevil/core/utils/log_redaction.dart';

/// `SentryFlutter.init` 的 beforeSend：送出前遮掉秘密與個資。
///
/// captureException 送的是例外物件本身（不經 logger 的字串遮罩），它的
/// `value` 就是 `toString()`——dio 的錯誤會帶 uri、SqliteException 會帶綁定
/// 參數。事件內附的 breadcrumbs 也一併處理。
SentryEvent redactSentryEvent(SentryEvent event) {
  for (final e in event.exceptions ?? const <SentryException>[]) {
    if (e.value case final v?) e.value = LogRedaction.redact(v);
  }
  if (event.message case final m?) {
    m.formatted = LogRedaction.redact(m.formatted);
  }
  event.breadcrumbs?.forEach(redactBreadcrumb);
  return event;
}

/// `SentryFlutter.init` 的 beforeBreadcrumb：包含 SDK 自動收集的
/// breadcrumb（例如 http 請求的 url），不只 logger 送的。
Breadcrumb? redactBreadcrumb(Breadcrumb? crumb) {
  if (crumb == null) return null;
  if (crumb.message case final m?) crumb.message = LogRedaction.redact(m);
  if (crumb.data case final data?) {
    crumb.data = {
      for (final MapEntry(:key, :value) in data.entries)
        key: value is String ? LogRedaction.redact(value) : value,
    };
  }
  return crumb;
}
