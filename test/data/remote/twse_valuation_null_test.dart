// 估值缺值語意(2026-08-15 數值稽核第 3 條)
//
// TWSE BWIBBU 對「無法計算」的欄位回**空字串**(2026-08-15 實測真實回應;
// 文件常寫成 `-`,兩種都要能處理)——虧損無本益比、未配息無殖利率。
// 舊解析用 `?? 0.0` 落庫成 **0**,與「本益比 0」不可區分。
//
// 實測 production:per=0 每日 213–246 檔(約 20%),其中虧損 151 檔
// (語意上可理解)、**獲利 38 檔**(真的算不出來,例:正崴 Q2 EPS 12.56
// 卻 per=0)。而同一欄位的 TPEX 路徑寫的是 NULL——**兩市場 null 語意
// 不一致,跨市場的排序/分位數/平均本益比統計全部不成立**。
//
// 規則端多以 `> 0` 擋掉,所以訊號層無誤觸發;這裡修的是資料層語意。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/remote/twse_client.dart';

void main() {
  final d = DateTime(2026, 8, 14);

  test('🚨 空字串/`-`(無法計算)必須落 NULL,不得寫成 0', () {
    final r = TwseClient.parseValuationRows([
      {
        'Code': '1101',
        'Name': '台泥',
        'PEratio': '-', // 虧損 → 無本益比
        'DividendYield': '-', // 未配息
        'PBratio': '0.85',
      },
    ], d);
    expect(r, hasLength(1));
    expect(r.first.per, isNull, reason: 'per=0 會被讀成「本益比 0」——那是極度便宜,語意完全相反');
    expect(r.first.dividendYield, isNull);
    expect(r.first.pbr, 0.85, reason: '有值的欄位不受影響');
  });

  test('空字串與缺欄位同樣落 NULL', () {
    final r = TwseClient.parseValuationRows([
      {'Code': '1102', 'Name': '亞泥', 'PEratio': '', 'PBratio': '1.2'},
    ], d);
    expect(r.first.per, isNull);
    expect(r.first.dividendYield, isNull, reason: '欄位缺席');
    expect(r.first.pbr, 1.2);
  });

  test('正常數值照常解析(確認不是把功能關掉)', () {
    final r = TwseClient.parseValuationRows([
      {
        'Code': '2330',
        'Name': '台積電',
        'PEratio': '27.76',
        'DividendYield': '0.92',
        'PBratio': '9.66',
      },
    ], d);
    expect(r.first.per, 27.76);
    expect(r.first.dividendYield, 0.92);
    expect(r.first.pbr, 9.66);
  });

  test('🚨 交易所明確回的 0.00 要保留(0 與 NULL 語意不同)', () {
    final r = TwseClient.parseValuationRows([
      {
        'Code': '1103',
        'Name': '嘉泥',
        'PEratio': '15.5',
        'DividendYield': '0.00',
        'PBratio': '1.1',
      },
    ], d);
    expect(r.first.dividendYield, 0.0, reason: '交易所明確回 0.00 是資訊,不該被當成缺值抹掉');
  });

  // 2026-08-15 對真實 API 回應實測:1,083 筆中 per 空字串 214 筆、
  // dividendYield 空字串 235 筆,新解析全部落 NULL、零筆寫成 0;
  // 台積電 27.76 / 9.66 / 0.92 照常解析。
  test('千分位照常處理', () {
    final r = TwseClient.parseValuationRows([
      {'Code': '9999', 'PEratio': '1,234.5', 'PBratio': '2.0'},
    ], d);
    expect(r.first.per, 1234.5);
  });
}
