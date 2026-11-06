import 'dart:io';

import 'package:daredevil/core/utils/device_time.dart';

/// CLI 日誌自輪替(2026-08-08)。
///
/// **為什麼不用 newsyslog**:那要在 `/etc/newsyslog.d/` 放一個未版控、
/// 機器本地、換機就消失的設定檔——而本專案今天已經被同一類東西咬過
/// 兩次(launchd plist 只存在 `~/Library` 差點靜默失效;改了 plist 檔
/// 卻沒重新 bootstrap,live job 一直跑舊定義)。輪替寫進程式就跟著
/// repo 走、有測試覆蓋、換機自動生效,而且不需要 sudo。
///
/// 策略是「就地截斷保留尾端」而非改名輪替:launchd 的 append 重導
/// 握著同一個 file descriptor,改名會讓後續輸出繼續寫進已改名的舊檔
/// (寫到沒人看的地方),就地截斷則沒有這個問題。
abstract final class LogRotation {
  /// 預設上限 1 MB。實測(2026-08-08 三次審查 F-7):每次執行約 100 bytes
  /// ——心跳行之外還有 `dart run` 自己吐的 `Running build hooks...`(44
  /// bytes 且無換行)。55 次/日 ≈ 5.5 KB/日 → 1 MB 約留 **190 天**。
  ///
  /// ⚠️ 上述只適用**穩態**。開發期間程式碼一改,下一次 `dart run` 會重新
  /// 編譯並吐出大量 `\r` 進度輸出:2026-08-08 一天之內就衝到 1.2 MB 觸發
  /// 輪替(平時要 190 天)。看到日誌暴漲先確認是不是剛改過 code,不必然
  /// 是故障。
  static const int defaultMaxBytes = 1024 * 1024;

  /// 超過 [maxBytes] 時就地截斷,保留最新的約一半內容。
  ///
  /// 失敗**不影響主功能**,但一律留痕跡(stderr)——「不該讓主功能失敗」
  /// 推導不出「失敗不必留紀錄」。呼叫點在兩支 CLI 的 `main()` 第一行且
  /// 不在 try 內,所以這裡必須真的把所有例外接住(2026-08-08 四次審查 I-5)。
  static void rotateIfNeeded(String path, {int maxBytes = defaultMaxBytes}) {
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final length = file.lengthSync();
      if (length <= maxBytes) return;

      // 保留一半:留太少會讓「剛截斷完」的日誌幾乎沒有上下文
      final keep = maxBytes ~/ 2;

      // ⚠️ 只讀尾端,不可 readAsBytesSync 把整份載入(2026-08-08 三次審查)。
      // 若哪天某個 bug 讓日誌衝到數 GB,整份讀入會丟 OutOfMemoryError;
      // 舊版的無型別 catch 連 Error 都接住 → 輪替從此每次靜默失敗 →
      // 日誌無限成長直到塞爆磁碟。而那正是最需要輪替的時候。
      final raf = file.openSync();
      List<int> tail;
      try {
        raf.setPositionSync(length - keep);
        tail = raf.readSync(keep);
      } finally {
        raf.closeSync();
      }

      // 從第一個換行之後開始,避免開頭是被切一半的殘句。
      //
      // ⚠️ 但只在「殘句本身很短」時才修剪(2026-08-08 實機事故)。
      // `dart run` 的進度輸出用 `\r` 不用 `\n`,異常時會一次吐出數十萬
      // 位元組完全沒有換行的內容;此時尾端窗內的第一個 `\n` 落在很後面,
      // 無條件修剪會把**整個保留區**吃光——實測 1.2 MB 的日誌輪替後只
      // 剩 104 bytes,異常當下的證據全滅,連「發生了什麼」都查不到了。
      // 輪替的目的是限制大小,不是銷毀證據:寧可開頭留一段殘句。
      final nl = tail.indexOf(0x0A);
      final maxTrim = tail.length ~/ 8;
      if (nl >= 0 && nl < tail.length - 1 && nl <= maxTrim) {
        tail = tail.sublist(nl + 1);
      }

      final header =
          '--- truncated at ${DeviceTime.now().toIso8601String()} '
          '(was $length bytes) ---\n';
      file.writeAsBytesSync([...header.codeUnits, ...tail]);
    } catch (e) {
      // 輪替失敗不影響本體——但**不可無聲**(2026-08-08 三次審查)。
      // 舊版是無型別 `catch (_) {}`,正是今天咬人的那個形狀本身。
      //
      // 最該留痕跡的情境:`writeAsBytesSync` 預設 O_TRUNC,會先把檔案
      // 截成 0 再寫入;若寫入失敗(磁碟滿、volume 唯讀、檔案被鎖),
      // 檔案就停在 **0 bytes**。磁碟滿正是最需要日誌的時候,而這段
      // 程式碼會在那一刻把日誌完全銷毀。
      //
      // 用 stderr 而非 AppLogger:兩支 CLI 由 `dart run` 執行,AppLogger
      // 的輸出包在 assert 內、asserts 未啟用時是 no-op(見 logger.dart)。
      // stderr 會落進 launchd 重導的同一份檔案。
      // 這裡刻意接住**所有**例外(含 Error):呼叫點是 CLI 的第一行、
      // 不在任何 try 內,逸出會讓 process 死在 beat() 之前 → 空白日誌,
      // 正是心跳要消滅的形狀。但不再無聲——失敗一定寫進 stderr。
      stderr.writeln('[LogRotation] 輪替失敗 $path: $e');
    }
  }
}
