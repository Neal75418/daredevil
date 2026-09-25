import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/log_redaction.dart';

/// 對外輸出（Sentry、CLI 日誌、update_run.message）前遮掉秘密與個資。
///
/// 實例（security review 本機重現）：FinMind 在收到 header 前斷線時，dio 的
/// 錯誤字串帶出完整 uri——`...&token=<JWT>`——再經 logger 進 Sentry breadcrumb。
void main() {
  const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoiMTIzNCJ9.abc-def_ghi';

  test('🚨 uri 裡的 token 參數值被遮掉,其餘保留', () {
    const raw =
        'HttpException: Connection closed before full header was received, '
        'uri = https://api.finmindtrade.com/api/v4/data'
        '?dataset=TaiwanStockPrice&token=$jwt&data_id=2330';
    final out = LogRedaction.redact(raw);
    expect(out, isNot(contains(jwt)));
    expect(out, contains('token=***'));
    expect(out, contains('dataset=TaiwanStockPrice'));
    expect(out, contains('data_id=2330'));
  });

  test('token 在字串結尾、或大小寫不同也要遮', () {
    expect(LogRedaction.redact('a?Token=$jwt'), 'a?Token=***');
  });

  test('Authorization: Bearer 的值被遮掉', () {
    final out = LogRedaction.redact('headers: {Authorization: Bearer $jwt}');
    expect(out, isNot(contains(jwt)));
    expect(out, contains('Bearer ***'));
  });

  test('🚨 SqliteException 的綁定參數（持倉張數、成本、備註）被遮掉,語句保留', () {
    const raw =
        'SqliteException(2067): while executing, UNIQUE constraint failed\n'
        '  Causing statement: INSERT INTO portfolio_transaction '
        '(symbol, shares, price, note) VALUES (?, ?, ?, ?), '
        'parameters: 2330, 3000, 612.5, 我的私房備註';
    final out = LogRedaction.redact(raw);
    expect(out, isNot(contains('我的私房備註')));
    expect(out, isNot(contains('612.5')));
    expect(out, contains('INSERT INTO portfolio_transaction'));
    expect(out, contains('parameters: <redacted>'));
  });

  test('🚨 參數內含換行（多行事件描述）也要整段遮掉', () {
    const raw =
        '  Causing statement: INSERT INTO stock_event (title, description) '
        'VALUES (?, ?), parameters: 法說會, 第一行\n第二行私密, 99';
    final out = LogRedaction.redact(raw);
    expect(out, isNot(contains('第二行私密')));
    expect(out, isNot(contains('99')));
  });

  test('小寫 bearer 與 base64 字元（+ / =）也要遮乾淨', () {
    expect(LogRedaction.redact('bearer abc.def'), 'bearer ***');
    expect(LogRedaction.redact('Bearer abc+/def==xyz done'), 'Bearer *** done');
  });

  test('沒有敏感內容的字串原樣回傳', () {
    const raw = 'FinMind TaiwanStockPrice(2330): 250 筆, token 未設定';
    expect(LogRedaction.redact(raw), raw);
  });
}
