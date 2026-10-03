// 除權除息計算結果（TWSE TWT49U／TWT49UDetail、TPEx exDailyQ）
//
// 股利歷史的來源：一次除權息一列、附除息日。樣本取自 2026-09-29 的
// 實際回應（欄位名、數字與日期格式照原樣）。
//
// TWSE 列表只給「權值+息值」合計：「息」列即現金股利；「權」列可能是
// 配股也可能只是現金增資；「權息」列的現金與配股混在一起——後兩者要查
// 明細才分得開。TPEx 列表本身就分欄。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

class MockDio extends Mock implements Dio {}

const _twseFields = [
  '資料日期',
  '股票代號',
  '股票名稱',
  '除權息前收盤價',
  '除權息參考價',
  '權值+息值',
  '權/息',
  '漲停價格',
  '跌停價格',
  '開盤競價基準',
  '減除股利參考價',
  '詳細資料',
  '最近一次申報資料 季別/日期',
  '最近一次申報每股 (單位)淨值',
  '最近一次申報每股 (單位)盈餘',
];

List<String> _twseRow(
  String date,
  String code,
  String value,
  String kind, {
  String close = '10.00',
  String reference = '9.50',
  String adjustedReference = '9.50',
}) => [
  date,
  code,
  '名稱',
  close,
  reference,
  value,
  kind,
  '11.00',
  '9.00',
  '9.50',
  adjustedReference,
  '$code,x',
  '',
  '',
  '',
];

Map<String, dynamic> _twseBody(
  List<List<String>> rows, {
  String strDate = '20250101',
  String endDate = '20251231',
}) => {
  'stat': 'OK',
  'title': '除權除息計算結果表',
  'fields': _twseFields,
  'data': rows,
  'strDate': strDate,
  'endDate': endDate,
};

Map<String, dynamic> _detailBody(String code, String cash, String shares) => {
  'stat': 'ok',
  'fields': [
    '股票代號',
    '股票名稱',
    '(每股配發現金股利)除息',
    '(增資配股) 除權',
    'A. 按普通股股東持股比例每千股無償配股',
    'B. 員工紅利轉增資',
    'C. (有償) 現金增資',
    '每股認購金額',
    'a. 公開承銷',
    'b. 員工認購',
    ' c. 原股東認購',
    '按股東持股比例每千股認購',
  ],
  'data': [
    [
      '$code  ',
      '名稱            ',
      cash,
      '',
      shares,
      '0 股',
      '35,000,000 股',
      '20 元／股',
      '3,500,000 股',
      '3,500,000 股',
      '28,000,000 股',
      '171.12939600 股',
    ],
  ],
};

const _tpexFields = [
  '除權息日期',
  '代號',
  '名稱',
  '除權息前收盤價',
  '除權息參考價',
  '權值',
  '息值',
  '權值+息值',
  '權/息',
  '漲停價',
  '跌停價',
  '開始交易基準價',
  '減除股利參考價',
  '現金股利',
  '每仟股無償配股',
  '現金增資股數',
  '現金增資認購價',
  '公開承銷股數',
  '員工認購股數',
  '原股東認購股數',
  '按持股比例仟股認購',
];

List<String> _tpexRow(
  String date,
  String code,
  String kind,
  String cash,
  String sharesPerThousand, {
  String close = '10.00',
  String reference = '9.50',
}) => [
  date,
  code,
  '名稱         ',
  close,
  reference,
  '0.000000',
  '0.000000',
  '0.000000',
  kind,
  '11.00',
  '9.00',
  '9.50',
  '9.50',
  cash,
  sharesPerThousand,
  '0',
  '0.00',
  '0',
  '0',
  '0',
  '0.00000000',
];

Map<String, dynamic> _tpexBody(
  List<List<String>> rows, {
  String date = '20250101~20251231',
  int? totalCount,
}) => {
  'date': date,
  'tables': [
    {
      'title': '',
      'totalCount': totalCount ?? rows.length,
      'fields': _tpexFields,
      'data': rows,
    },
  ],
  'stat': 'ok',
};

void main() {
  final start = DateTime(2025, 1, 1);
  final end = DateTime(2025, 12, 31);

  group('TwseClient.parseExRightResults（TWT49U）', () {
    List<ExRightResult>? parse(Map<String, dynamic> body) =>
        TwseClient.parseExRightResults(body, startDate: start, endDate: end);

    test('「息」列：權值+息值即現金股利，無配股，不需查明細', () {
      final r = parse(
        _twseBody([_twseRow('114年03月18日', '2330', '4.500020', '息')]),
      )!.single;
      expect(r.symbol, '2330');
      expect(r.exDate, DateTime(2025, 3, 18));
      expect(r.cashDividend, 4.50002);
      expect(r.stockSharesPerThousand, 0);
      expect(r.needsDetail, isFalse);
    });

    test('「權」列：現金為 0，配股未知（可能只是現金增資），需查明細', () {
      final r = parse(
        _twseBody([_twseRow('114年01月05日', '4108', '0.916328', '權')]),
      )!.single;
      expect(r.cashDividend, 0);
      expect(r.stockSharesPerThousand, isNull);
      expect(r.needsDetail, isTrue);
    });

    test('「權息」列：合計值拆不開，現金與配股皆未知，需查明細', () {
      final r = parse(
        _twseBody([_twseRow('114年01月13日', '2836', '0.600000', '權息')]),
      )!.single;
      expect(r.cashDividend, isNull);
      expect(r.stockSharesPerThousand, isNull);
      expect(r.needsDetail, isTrue);
    });

    test('區間內沒有除權息：回空清單（合法的無資料）', () {
      expect(parse({'stat': '很抱歉，沒有符合條件的資料!'}), isEmpty);
    });

    test('其他 stat：回 null（回應不可信），即使區間與欄位都對', () {
      final body = _twseBody([_twseRow('114年03月18日', '2330', '4.500020', '息')]);
      body['stat'] = '查詢日期大於可查詢最大日期，請重新查詢!';
      expect(parse(body), isNull);
    });

    test('回應區間與請求不符：回 null，不把別段區間當成這段', () {
      final rows = [_twseRow('114年03月18日', '2330', '4.500020', '息')];
      expect(parse(_twseBody(rows, strDate: '20250701')), isNull);
      expect(parse(_twseBody(rows, endDate: '20250630')), isNull);
    });

    test('缺必要欄位：回 null', () {
      final body = _twseBody([_twseRow('114年03月18日', '2330', '4.500020', '息')]);
      body['fields'] = (_twseFields.toList()..[6] = '類別');
      expect(parse(body), isNull);
    });

    test('欄位清單或資料型別不對：回 null，不拋型別錯誤', () {
      final badFields = _twseBody([
        _twseRow('114年03月18日', '2330', '4.500020', '息'),
      ]);
      badFields['fields'] = {'0': '資料日期'};
      expect(parse(badFields), isNull);

      final badData = _twseBody(const []);
      badData['data'] = {'0': 'x'};
      expect(parse(badData), isNull);
    });

    // 任一列解析不了就整批拒收：這是回補歷史的來源，略過的配發之後不會再
    // 被抓到。每條附正向對照——同一份回應去掉壞列即可解析。
    group('任一列無法解析：整批拒收', () {
      final good = _twseRow('114年03月18日', '2330', '4.500020', '息');
      final badRows = <String, List<String>>{
        '日期無效': _twseRow('114年02月30日', '1101', '1.000000', '息'),
        '代號空白': _twseRow('114年03月18日', '  ', '1.000000', '息'),
        '類別不明（例如改成 TPEx 的「除息」寫法）': _twseRow(
          '114年03月18日',
          '1102',
          '1.000000',
          '除息',
        ),
        '「息」列金額缺漏': _twseRow('114年03月18日', '1103', '--', '息'),
        '欄數不足': ['114年03月18日', '1104'],
      };
      for (final entry in badRows.entries) {
        test(entry.key, () {
          expect(parse(_twseBody([good])), isNotNull, reason: '正向對照');
          expect(parse(_twseBody([good, entry.value])), isNull);
        });
      }
    });
  });

  group('TWSE 列表帶出核對明細用的前收與減除股利參考價', () {
    List<ExRightResult>? parse(Map<String, dynamic> body) =>
        TwseClient.parseExRightResults(body, startDate: start, endDate: end);

    test('權、權息列：前收與減除股利參考價（含千分位）', () {
      for (final kind in ['權', '權息']) {
        final r = parse(
          _twseBody([
            _twseRow(
              '114年09月02日',
              '6669',
              '5,185.010000',
              kind,
              close: '7,800.00',
              adjustedReference: '2,614.99',
            ),
          ]),
        )!.single;
        expect(r.closeBefore, 7800, reason: kind);
        expect(r.dividendAdjustedReference, 2614.99, reason: kind);
      }
    });

    test('欄位清單缺前收或減除股利參考價：回 null（即使全是息列）', () {
      for (final col in ['除權息前收盤價', '減除股利參考價']) {
        final body = _twseBody([
          _twseRow('114年03月18日', '2330', '4.500020', '息'),
        ]);
        body['fields'] = [for (final f in _twseFields) f == col ? '其他' : f];
        expect(parse(body), isNull, reason: col);
      }
    });

    test('需查明細的列缺前收或參考價：整批拒收（無從核對明細）', () {
      final good = _twseRow('114年03月18日', '2330', '4.500020', '息');
      for (final bad in [
        _twseRow('114年01月13日', '2836', '0.600000', '權息', close: '--'),
        _twseRow(
          '114年01月13日',
          '2836',
          '0.600000',
          '權',
          adjustedReference: '--',
        ),
      ]) {
        expect(parse(_twseBody([good])), isNotNull, reason: '正向對照');
        expect(parse(_twseBody([good, bad])), isNull);
      }
    });

    test('息列不需核對：前收或參考價缺漏不影響', () {
      final r = parse(
        _twseBody([
          _twseRow('114年03月18日', '2330', '4.500020', '息', close: '--'),
        ]),
      )!.single;
      expect(r.cashDividend, 4.50002);
      expect(r.closeBefore, isNull);
    });
  });

  group('ExRightResult.matchesReference（2026-09-29 實測樣本）', () {
    ExRightResult twseRow(double close, double reference) => ExRightResult(
      symbol: 'X',
      exDate: DateTime(2026, 9, 1),
      cashDividend: null,
      stockSharesPerThousand: null,
      closeBefore: close,
      dividendAdjustedReference: reference,
    );
    ExRightDetail detail(double cash, double shares) => ExRightDetail(
      symbol: 'X',
      cashDividend: cash,
      stockSharesPerThousand: shares,
    );

    test('明細推算的減除股利參考價與列表一致（TWSE 捨去到 0.01）', () {
      for (final (close, reference, cash, shares) in [
        (127.50, 110.86, 0.0, 150.0), // 4763 2021 只配股
        (59.50, 51.84, 0.4, 140.0), // 2543 2024 權息＋現金增資
        (7800.0, 2614.99, 0.0, 1982.8), // 6669 2026 大額配股
        (25.20, 25.20, 0.0, 0.0), // 4108 2021 只有現金增資
        (10.60, 10.00, 0.15, 45.0), // 2836 2021 權息
        // 明細股數只顯示到小數 1 位：反推真值約 109.73 股、25.62–25.68 股
        (538.00, 484.80, 0.0, 109.7), // 6446 2025-09 只配股
        (168.00, 159.17, 4.743589, 25.6), // 4572 2025-07 權息
      ]) {
        expect(
          twseRow(close, reference).matchesReference(detail(cash, shares)),
          isTrue,
          reason: '$close $reference',
        );
      }
    });

    test('明細是別次除權息（2836 的 2024 列表配 2021 明細）→ 不一致', () {
      expect(twseRow(12.55, 11.89).matchesReference(detail(0.15, 45)), isFalse);
      expect(
        twseRow(12.55, 11.89).matchesReference(detail(0.3, 30)),
        isTrue,
        reason: '正向對照：2024 的明細',
      );
    });

    test('容差邊界：捨去誤差不到 0.01 算一致（含剛好 0.01 的浮點餘裕），超過就不一致', () {
      // 前收 100、無配發 → 推算 100
      bool at(double reference) =>
          twseRow(100, reference).matchesReference(detail(0, 0));
      expect(at(99.991), isTrue);
      expect(at(99.99), isTrue, reason: '100 − 99.99 在浮點下略大於 0.01');
      expect(at(99.989), isFalse);
      expect(at(100.011), isFalse, reason: '列表比推算值高也算不一致');
    });

    test('明細配股只到小數 1 位：真值在 ±0.1 股內算一致，超出就不一致', () {
      // 前收 1000、明細 100 股
      bool at(double reference) =>
          twseRow(1000, reference).matchesReference(detail(0, 100));
      expect(at(909.09), isTrue, reason: '100 股：1000 ÷ 1.1 = 909.0909');
      expect(at(909.01), isTrue, reason: '真值 100.09 股：909.0165 捨去');
      expect(at(908.92), isFalse, reason: '真值 100.2 股：908.9256 捨去');
      expect(at(909.19), isFalse, reason: '真值 99.88 股：909.1901 捨去');
    });

    test('列表沒有核對欄位（上櫃列、測試建構）→ 不擋', () {
      expect(
        ExRightResult(
          symbol: 'X',
          exDate: DateTime(2026, 9, 1),
          cashDividend: null,
          stockSharesPerThousand: null,
        ).matchesReference(detail(1, 1)),
        isTrue,
      );
    });
  });

  group('TwseClient.parseExRightDetail（TWT49UDetail）', () {
    test('權息明細：每股現金股利與每千股無償配股', () {
      final d = TwseClient.parseExRightDetail(
        _detailBody('2836', '0.15 元／股', '45 股'),
      )!;
      expect(d.symbol, '2836');
      expect(d.cashDividend, 0.15);
      expect(d.stockSharesPerThousand, 45);
    });

    test('小數位照原樣（存託憑證）', () {
      final d = TwseClient.parseExRightDetail(
        _detailBody('9105', '0.008773 元／股', '83.3 股'),
      )!;
      expect(d.cashDividend, 0.008773);
      expect(d.stockSharesPerThousand, 83.3);
    });

    test('數字帶千分位', () {
      final d = TwseClient.parseExRightDetail(
        _detailBody('1234', '1,200 元／股', '1,200 股'),
      )!;
      expect(d.cashDividend, 1200);
      expect(d.stockSharesPerThousand, 1200);
    });

    test('無相關資料：回 null', () {
      expect(TwseClient.parseExRightDetail({'stat': '無相關資料'}), isNull);
    });

    test('stat 異常：回 null，即使欄位與資料都在', () {
      final body = _detailBody('2836', '0.15 元／股', '45 股');
      body['stat'] = '查詢失敗';
      expect(TwseClient.parseExRightDetail(body), isNull);
    });

    test('金額欄無法解析：回 null，不當成 0', () {
      expect(
        TwseClient.parseExRightDetail(_detailBody('2836', '--', '45 股')),
        isNull,
      );
    });

    test('單位不符：回 null，不把別的單位當成元／股或股數', () {
      expect(
        TwseClient.parseExRightDetail(_detailBody('2836', '0.15 元', '45 股')),
        isNull,
      );
      expect(
        TwseClient.parseExRightDetail(
          _detailBody('2836', '0.15 元／股', '1.5 元／股'),
        ),
        isNull,
      );
    });

    test('stat 為 ok 但沒有資料列：回 null', () {
      final body = _detailBody('2836', '0.15 元／股', '45 股');
      body['data'] = <dynamic>[];
      expect(TwseClient.parseExRightDetail(body), isNull);
    });

    test('缺必要欄位或欄位清單型別不對：回 null', () {
      final missing = _detailBody('2836', '0.15 元／股', '45 股');
      missing['fields'] = (missing['fields'] as List).toList()
        ..[4] = 'A. 按普通股股東持股比例每千股配發';
      expect(TwseClient.parseExRightDetail(missing), isNull);

      final wrongType = _detailBody('2836', '0.15 元／股', '45 股');
      wrongType['fields'] = {'0': '股票代號'};
      expect(TwseClient.parseExRightDetail(wrongType), isNull);
    });

    test('代號空白：回 null', () {
      expect(
        TwseClient.parseExRightDetail(_detailBody('', '0.15 元／股', '45 股')),
        isNull,
      );
    });

    test('資料列比欄位清單短：回 null，不拋越界錯誤', () {
      final body = _detailBody('2836', '0.15 元／股', '45 股');
      body['data'] = [
        ['2836', '名稱', '0.15 元／股'],
      ];
      expect(TwseClient.parseExRightDetail(body), isNull);
    });
  });

  group('列表帶出還原用的前收盤與除權息參考價（兩市場、所有列）', () {
    test('上市息、權、權息列都帶前收盤與除權息參考價（含千分位）', () {
      final rows = TwseClient.parseExRightResults(
        _twseBody([
          _twseRow(
            '114年03月18日',
            '2330',
            '4.500020',
            '息',
            close: '1,000.00',
            reference: '995.50',
          ),
          _twseRow(
            '114年01月05日',
            '4108',
            '0.916328',
            '權',
            close: '25.20',
            reference: '24.28',
          ),
          _twseRow(
            '114年01月13日',
            '2836',
            '0.600000',
            '權息',
            close: '10.60',
            reference: '10.00',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!;
      expect(
        [for (final r in rows) (r.closeBefore, r.referencePrice)],
        [(1000.0, 995.5), (25.2, 24.28), (10.6, 10.0)],
      );
    });

    test('上市欄位清單缺除權息參考價：回 null', () {
      final body = _twseBody([_twseRow('114年03月18日', '2330', '4.500020', '息')]);
      body['fields'] = [for (final f in _twseFields) f == '除權息參考價' ? '其他' : f];
      expect(
        TwseClient.parseExRightResults(body, startDate: start, endDate: end),
        isNull,
      );
    });

    test('上市單列缺值：照收、該欄為 null（不讓一列拖垮整個市場）', () {
      final r = TwseClient.parseExRightResults(
        _twseBody([
          _twseRow(
            '114年03月18日',
            '2330',
            '4.500020',
            '息',
            close: '--',
            reference: '--',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!.single;
      expect(r.cashDividend, 4.50002);
      expect(r.closeBefore, isNull);
      expect(r.referencePrice, isNull);
    });

    test('上櫃列帶前收盤與除權息參考價', () {
      final r = TpexClient.parseExRightResults(
        _tpexBody([
          _tpexRow(
            '114/06/18',
            '6762',
            '除權息',
            '0.30000000',
            '150.00000327',
            close: '1,200.00',
            reference: '1,043.22',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!.single;
      expect(r.closeBefore, 1200);
      expect(r.referencePrice, 1043.22);
    });

    test('上櫃欄位清單缺前收盤或除權息參考價：回 null', () {
      for (final col in ['除權息前收盤價', '除權息參考價']) {
        final body = _tpexBody([
          _tpexRow('114/01/02', '6488', '除息', '3.00000000', '0.00000000'),
        ]);
        ((body['tables'] as List).first as Map)['fields'] = [
          for (final f in _tpexFields) f == col ? '其他' : f,
        ];
        expect(
          TpexClient.parseExRightResults(body, startDate: start, endDate: end),
          isNull,
          reason: col,
        );
      }
    });

    test('上櫃單列缺值：照收、該欄為 null', () {
      final r = TpexClient.parseExRightResults(
        _tpexBody([
          _tpexRow(
            '114/01/02',
            '6488',
            '除息',
            '3.00000000',
            '0.00000000',
            close: '--',
            reference: '--',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!.single;
      expect(r.closeBefore, isNull);
      expect(r.referencePrice, isNull);
    });
  });

  group('ExRightResult.withDetail', () {
    ExRightResult twse(String kind) => TwseClient.parseExRightResults(
      _twseBody([_twseRow('114年01月13日', '2836', '0.600000', kind)]),
      startDate: start,
      endDate: end,
    )!.single;

    test('權息列補上明細後金額齊全', () {
      final r = twse('權息').withDetail(
        TwseClient.parseExRightDetail(_detailBody('2836', '0.15 元／股', '45 股'))!,
      );
      expect(r.cashDividend, 0.15);
      expect(r.stockSharesPerThousand, 45);
      expect(r.needsDetail, isFalse);
      expect(r.closeBefore, 10, reason: '核對欄位照原列保留');
      expect(r.dividendAdjustedReference, 9.5);
      expect(r.referencePrice, 9.5, reason: '除權息參考價照原列保留');
    });

    test('權列補上明細：只有現金增資時金額皆 0', () {
      final r = twse('權').withDetail(
        TwseClient.parseExRightDetail(_detailBody('2836', '0 元／股', '0 股'))!,
      );
      expect(r.needsDetail, isFalse);
      expect(r.cashDividend, 0);
      expect(r.stockSharesPerThousand, 0);
    });
  });

  group('TpexClient.parseExRightResults（exDailyQ）', () {
    List<ExRightResult>? parse(Map<String, dynamic> body) =>
        TpexClient.parseExRightResults(body, startDate: start, endDate: end);

    test('除息、除權、除權息皆直接取分欄的現金股利與每仟股無償配股', () {
      final r = parse(
        _tpexBody([
          _tpexRow('114/01/02', '00950B', '除息', '0.08000000', '0.00000000'),
          _tpexRow('114/06/18', '6762', '除權息', '0.30000000', '150.00000327'),
        ]),
      )!;
      expect(r.map((e) => e.symbol), ['00950B', '6762']);
      expect(r[0].exDate, DateTime(2025, 1, 2));
      expect(r[0].cashDividend, 0.08);
      expect(r[0].stockSharesPerThousand, 0);
      expect(r[1].cashDividend, 0.3);
      expect(r[1].stockSharesPerThousand, 150.00000327);
      expect(r.every((e) => !e.needsDetail), isTrue);
    });

    test('只有現金增資的除權：金額皆 0、不需查明細', () {
      final r = parse(
        _tpexBody([
          _tpexRow('114/01/02', '4109', '除權', '0.00000000', '0.00000000'),
        ]),
      )!.single;
      expect(r.needsDetail, isFalse);
      expect(r.cashDividend, 0);
      expect(r.stockSharesPerThousand, 0);
    });

    test('區間內沒有除權息：回空清單', () {
      expect(parse(_tpexBody(const [])), isEmpty);
    });

    test('stat 異常：回 null，即使區間與欄位都對', () {
      final body = _tpexBody([
        _tpexRow('114/01/02', '00950B', '除息', '0.08', '0'),
      ]);
      body['stat'] = 'error';
      expect(parse(body), isNull);
    });

    test('回應區間與請求不符：回 null', () {
      expect(
        parse(
          _tpexBody([
            _tpexRow('114/01/02', '00950B', '除息', '0.08', '0'),
          ], date: '20250101~20250630'),
        ),
        isNull,
      );
    });

    test('筆數與 totalCount 不符（可能被分頁截斷）：回 null', () {
      expect(
        parse(
          _tpexBody([
            _tpexRow('114/01/02', '00950B', '除息', '0.08', '0'),
          ], totalCount: 2),
        ),
        isNull,
      );
    });

    test('缺必要欄位：回 null', () {
      final body = _tpexBody([
        _tpexRow('114/01/02', '00950B', '除息', '0.08', '0'),
      ]);
      final table = (body['tables'] as List).first as Map<String, dynamic>;
      table['fields'] = _tpexFields.toList()..[14] = '每仟股配股';
      expect(parse(body), isNull);
    });

    test('tables 為空、型別不對，或欄位清單型別不對：回 null', () {
      final empty = _tpexBody(const [])..['tables'] = <dynamic>[];
      expect(parse(empty), isNull);

      final notList = _tpexBody(const [])..['tables'] = {'0': 'x'};
      expect(parse(notList), isNull);

      final notMap = _tpexBody(const [])..['tables'] = ['x'];
      expect(parse(notMap), isNull);

      // 空 Map：長度 0 與 totalCount 0 相符，只有型別檢查擋得住
      final badData = _tpexBody(const []);
      ((badData['tables'] as List).first as Map<String, dynamic>)['data'] =
          <String, dynamic>{};
      expect(parse(badData), isNull);

      final badFields = _tpexBody(const []);
      ((badFields['tables'] as List).first as Map<String, dynamic>)['fields'] =
          {'0': '除權息日期'};
      expect(parse(badFields), isNull);
    });

    group('任一列無法解析：整批拒收', () {
      final good = _tpexRow('114/01/02', '00950B', '除息', '0.08', '0');
      final badRows = <String, List<String>>{
        '日期無效': _tpexRow('114/02/30', '2222', '除息', '0.5', '0'),
        '代號空白': _tpexRow('114/01/02', '  ', '除息', '0.5', '0'),
        '現金股利無法解析': _tpexRow('114/01/02', '1111', '除息', '--', '0'),
        '配股無法解析': _tpexRow('114/01/02', '3333', '除權', '0', '--'),
        '欄數不足': ['114/01/02', '4444'],
      };
      for (final entry in badRows.entries) {
        test(entry.key, () {
          expect(parse(_tpexBody([good])), isNotNull, reason: '正向對照');
          expect(parse(_tpexBody([good, entry.value])), isNull);
        });
      }
    });
  });

  group('fetch', () {
    late MockDio dio;

    setUp(() => dio = MockDio());

    void stub(Map<String, dynamic> body) {
      when(
        () => dio.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(),
          statusCode: 200,
          data: body,
        ),
      );
    }

    Map<String, dynamic> capturedQuery(String path) =>
        verify(
              () => dio.get<dynamic>(
                path,
                queryParameters: captureAny(named: 'queryParameters'),
                options: any(named: 'options'),
              ),
            ).captured.single
            as Map<String, dynamic>;

    test('TWSE 列表：以西元緊湊日期查詢區間', () async {
      stub(_twseBody([_twseRow('114年03月18日', '2330', '4.500020', '息')]));

      final r = await TwseClient(
        dio: dio,
      ).getExRightResults(startDate: start, endDate: end);

      expect(r.single.symbol, '2330');
      expect(capturedQuery(ApiEndpoints.twseExRightResults), {
        'startDate': '20250101',
        'endDate': '20251231',
        'response': 'json',
      });
    });

    test('TWSE 列表回應不可信：拋 ApiException，不回空清單', () async {
      stub(_twseBody(const [], endDate: '20250630'));

      await expectLater(
        TwseClient(dio: dio).getExRightResults(startDate: start, endDate: end),
        throwsA(isA<ApiException>()),
      );
    });

    test('TWSE 明細：以代號與除權息日查詢', () async {
      stub(_detailBody('2836', '0.15 元／股', '45 股'));

      final d = await TwseClient(
        dio: dio,
      ).getExRightDetail('2836', DateTime(2021, 1, 13));

      expect(d.cashDividend, 0.15);
      expect(capturedQuery(ApiEndpoints.twseExRightDetail), {
        'STK_NO': '2836',
        'T1': '20210113',
        'response': 'json',
      });
    });

    test('TWSE 明細回傳的代號與請求不符：拋 ApiException', () async {
      stub(_detailBody('2330', '4.50002 元／股', '0 股'));

      await expectLater(
        TwseClient(dio: dio).getExRightDetail('2836', DateTime(2021, 1, 13)),
        throwsA(isA<ApiException>()),
      );
    });

    test('TPEx 列表：以西元斜線日期查詢區間', () async {
      stub(_tpexBody([_tpexRow('114/01/02', '00950B', '除息', '0.08', '0')]));

      final r = await TpexClient(
        dio: dio,
      ).getExRightResults(startDate: start, endDate: end);

      expect(r.single.symbol, '00950B');
      expect(capturedQuery(ApiEndpoints.tpexExRightResults), {
        'startDate': '2025/01/01',
        'endDate': '2025/12/31',
        'response': 'json',
      });
    });

    test('TPEx 列表回應不可信：拋 ApiException', () async {
      stub(
        _tpexBody([
          _tpexRow('114/01/02', '00950B', '除息', '0.08', '0'),
        ], totalCount: 2),
      );

      await expectLater(
        TpexClient(dio: dio).getExRightResults(startDate: start, endDate: end),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
