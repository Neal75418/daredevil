import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/remote/mops_client.dart';

/// MOPS 公布期營收 CSV 解析與資料檢核(2026-08-03)。
///
/// 背景:TWSE openapi 彙總表(t187ap05_L)是月批式——8/3 晚間實測仍全為
/// 6 月,7 月要等申報期(~8/10)結束後才切換。逐日更新的唯一來源是舊版
/// MOPS(`mopsov.twse.com.tw`)的 t21sc03 CSV,公布期間逐日填充(8/3 實測
/// 已 35 家上市)。
///
/// 檢核設計(使用者要求「新端點接回的資料要做驗證」):
/// - **自洽檢核是主防線**:CSV 同列給「當月/上月/去年同月營收」與
///   「MoM%/YoY%」,用前三者重算後兩者——欄序哪天漂移,重算立刻對不上,
///   整批拒收(退回等 openapi 的現狀),絕不寫入錯位資料
/// - fixture 是 2026-08-03 晚間的真實 bytes(big5 名稱欄在 latin-1 視角
///   是亂碼——無妨,解析只取 ASCII 欄位,名稱 DB 主檔本來就有)
void main() {
  final realBytes = File(
    'test/fixtures/mops_t21sc03_july_partial.csv',
  ).readAsBytesSync();
  final wafBytes = File(
    'test/fixtures/mops_waf_security_page.html',
  ).readAsBytesSync();

  group('parseRevenueCsv × 真實 fixture(2026-08-03 已申報 35 家)', () {
    test('🚨 解析出全部已申報公司,年月正確', () {
      final rows = MopsClient.parseRevenueCsv(realBytes, year: 2026, month: 7);

      expect(rows.length, 35);
      expect(rows.every((r) => r.year == 2026 && r.month == 7), isTrue);
      expect(rows.every((r) => RegExp(r'^\d{4}$').hasMatch(r.code)), isTrue);
    });

    test('🚨 數值欄位正確(對照真實資料:1256 鮮活果汁-KY)', () {
      final rows = MopsClient.parseRevenueCsv(realBytes, year: 2026, month: 7);

      final r = rows.firstWhere((r) => r.code == '1256');
      expect(r.revenue, 619291);
      expect(r.momGrowth, closeTo(7.6004, 0.001));
      expect(r.yoyGrowth, closeTo(21.9896, 0.001));
    });

    test('南亞科 2408(2026-08-03 已申報)在解析結果中', () {
      final rows = MopsClient.parseRevenueCsv(realBytes, year: 2026, month: 7);
      expect(rows.any((r) => r.code == '2408'), isTrue);
    });
  });

  group('資料檢核(拒收壞資料)', () {
    test('🚨 WAF 安全頁(HTML 非 CSV)→ ApiException', () {
      expect(
        () => MopsClient.parseRevenueCsv(wafBytes, year: 2026, month: 7),
        throwsA(isA<ApiException>()),
      );
    });

    test('🚨 欄位漂移(營收欄與上月欄對調)→ 自洽檢核整批拒收', () {
      // 手工壞資料:當月與上月營收欄系統性對調(增減率仍是對調前算的)
      // → 每列 MoM%/YoY% 重算皆對不上 → 整批拒收
      const drifted =
          '"header"\n'
          '"115/08/04","115/7","1101","X","Y","12612013","13382706","10107877","6.11","32.39","1","1","1","-"\n'
          '"115/08/04","115/7","1102","X","Y","5000000","6000000","4000000","20.0","50.0","1","1","1","-"\n'
          '"115/08/04","115/7","1103","X","Y","3000000","4000000","2000000","33.33","100.0","1","1","1","-"\n';
      expect(
        () =>
            MopsClient.parseRevenueCsv(drifted.codeUnits, year: 2026, month: 7),
        throwsA(isA<FormatException>()),
      );
    });

    test('月份不符的列被排除(誤抓到舊月檔案時回空,不寫錯月)', () {
      const wrongMonth =
          '"header"\n'
          '"115/07/04","115/6","1101","X","Y","13382706","12612013","10107877","6.11","32.39","1","1","1","-"\n';
      final rows = MopsClient.parseRevenueCsv(
        wrongMonth.codeUnits,
        year: 2026,
        month: 7,
      );
      expect(rows, isEmpty);
    });

    test('增減率為 "-"(無前期基準)→ null,不炸', () {
      const dash =
          '"header"\n'
          '"115/08/04","115/7","1435","X","Y","499","0","0","-","-","499","0","-","-"\n';
      final rows = MopsClient.parseRevenueCsv(
        dash.codeUnits,
        year: 2026,
        month: 7,
      );
      expect(rows.single.code, '1435');
      expect(rows.single.momGrowth, isNull);
      expect(rows.single.yoyGrowth, isNull);
    });

    test('重複代號保留第一筆', () {
      const dup =
          '"header"\n'
          '"115/08/04","115/7","1101","X","Y","100","50","50","100.0","100.0","1","1","1","-"\n'
          '"115/08/04","115/7","1101","X","Y","999","50","50","1898.0","1898.0","1","1","1","-"\n';
      final rows = MopsClient.parseRevenueCsv(
        dup.codeUnits,
        year: 2026,
        month: 7,
      );
      expect(rows.single.revenue, 100);
    });

    test('非 4 位數代號(權證等)被排除', () {
      const weird =
          '"header"\n'
          '"115/08/04","115/7","911616","X","Y","100","50","50","100.0","100.0","1","1","1","-"\n'
          '"115/08/04","115/7","1101","X","Y","100","50","50","100.0","100.0","1","1","1","-"\n';
      final rows = MopsClient.parseRevenueCsv(
        weird.codeUnits,
        year: 2026,
        month: 7,
      );
      expect(rows.single.code, '1101');
    });
  });

  group('累計年增(2026-08-13 一魚三吃:欄位+低基期識別+排序防護)', () {
    test('🚨 真實 fixture:累計前期比較增減被解析(鮮活果汁 +41.87%)', () {
      final rows = MopsClient.parseRevenueCsv(realBytes, year: 2026, month: 7);
      final row = rows.firstWhere((r) => r.code == '1256');
      expect(row.ytdYoyGrowth, isNotNull);
      expect(row.ytdYoyGrowth!, closeTo(41.87, 0.01));
    });

    test('🚨 累計欄自洽失配 → ytd 設 null,單月欄仍完好(不整列拒收)', () {
      // 單月三欄自洽([5][6][7] vs [8][9]),但累計增減 [12] 與 [10][11]
      // 重算差 30 個百分點——累計欄壞不該拖累單月資料
      final line =
          '"115/08/04","115/7","9999","X","ELEC","1100","1000","1000",'
          '"10.0","10.0","2000","1000","70.0","-"\n';
      final rows = MopsClient.parseRevenueCsv(
        line.codeUnits,
        year: 2026,
        month: 7,
      );
      expect(rows, hasLength(1));
      expect(rows.single.yoyGrowth, closeTo(10.0, 0.01));
      expect(rows.single.ytdYoyGrowth, isNull, reason: '失配的累計值不可落庫');
    });

    test('舊版式(僅 10 欄)→ 列仍解析,ytd 為 null(向後相容)', () {
      final line =
          '"115/08/04","115/7","9998","X","ELEC","1100","1000","1000",'
          '"10.0","10.0"\n';
      final rows = MopsClient.parseRevenueCsv(
        line.codeUnits,
        year: 2026,
        month: 7,
      );
      expect(rows, hasLength(1));
      expect(rows.single.ytdYoyGrowth, isNull);
    });
  });
}
