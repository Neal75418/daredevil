/// `dart build cli` 的入口——理由與 `bin/intraday_alert_check.dart` 相同。
///
/// daily 這支在 15:30 執行,網路通常已就緒,所以沒有像盤中那支一樣出過
/// 事;但失效機制完全一樣(`dart run` 每次跑 build hook、需要網路),
/// 沒理由只保護一支。
library;

import '../tool/daily_update.dart' as cli;

Future<void> main(List<String> args) => cli.main(args);
