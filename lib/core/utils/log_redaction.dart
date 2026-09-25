/// 對外輸出（Sentry、CLI 日誌）前遮掉秘密與個資。
///
/// logger 與 Sentry 的 beforeSend／beforeBreadcrumb 共用這一份規則。
/// 來源端（例如 FinMind token 改走 header）才是根治；這裡是最後一道防線，
/// 擋住「錯誤字串把 uri 或 SQL 參數原樣帶出去」這一類洩漏。
abstract final class LogRedaction {
  /// uri query 裡的 token 參數值（到 `&`、空白或引號為止）
  static final _queryToken = RegExp(
    r'''(token=)[^&\s"']+''',
    caseSensitive: false,
  );

  /// Authorization header 的 Bearer 值（含 base64 的 `+ / =`）
  static final _bearer = RegExp(
    r'''(Bearer\s+)[^\s"',}]+''',
    caseSensitive: false,
  );

  /// `SqliteException.toString()` 在語句後附帶綁定參數
  /// （持倉張數、成本、備註都可能在這裡）；語句本身是參數化的，保留供除錯。
  /// 參數字串可能含換行（多行事件描述），且它固定在 toString 結尾，
  /// 所以一路遮到字串結束——多遮只少一點除錯資訊，少遮就是洩漏。
  static final _sqlParameters = RegExp(r'(, parameters: )[\s\S]*');

  static String redact(String input) => input
      .replaceAllMapped(_queryToken, (m) => '${m[1]}***')
      .replaceAllMapped(_bearer, (m) => '${m[1]}***')
      .replaceAllMapped(_sqlParameters, (m) => '${m[1]}<redacted>');
}
