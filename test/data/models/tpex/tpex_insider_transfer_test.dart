import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/tpex/tpex_insider_transfer.dart';

void main() {
  group('TpexInsiderTransfer.fromJson', () {
    // 真實 TPEx OpenAPI (mopsfin_t187ap12_O) 的 key 帶群組前綴。
    // 舊版誤讀無前綴的 '轉讓股數'/'目前持有股數'/'轉讓方式' → 全 fallback 成 0
    // （DB 實測 17/17 筆皆 0 的 bug）。以下 key 已對 live API 核實。
    Map<String, dynamic> realRow() => <String, dynamic>{
      'SecuritiesCompanyCode': '2061',
      'CompanyName': '風青',
      'Date': '1150618',
      '申請人身分': '董事',
      '姓名': '陳信宇',
      '預定轉讓方式及股數-轉讓方式': ' 一般交易(每日得轉讓股數限制)',
      '預定轉讓方式及股數-轉讓股數': ' 500000',
      '目前持有股數-自有持股': '3232155',
      '有效轉讓期間': '1150620~1150719',
    };

    test('讀對 TPEx OpenAPI 群組前綴 key（含逗號/空白容錯）', () {
      final t = TpexInsiderTransfer.fromJson(realRow());

      expect(t.symbol, '2061');
      expect(t.name, '陳信宇');
      expect(t.transferShares, 500000, reason: '轉讓股數須來自「預定轉讓方式及股數-轉讓股數」');
      expect(t.currentHolding, 3232155, reason: '目前持有須來自「目前持有股數-自有持股」');
      expect(t.transferMethod.trim(), '一般交易(每日得轉讓股數限制)');
    });

    test('防回歸：誤用舊版無前綴 key 會讀成 0（即原 bug 來源）', () {
      final t = TpexInsiderTransfer.fromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '2061',
        'Date': '1150618',
        // 只有舊 key（模擬誤改回舊版）→ 新 key 不存在 → 0
        '轉讓股數': '500000',
        '目前持有股數': '3232155',
      });

      expect(
        t.transferShares,
        0,
        reason: '舊無前綴 key 不該被讀到（證明 17/17 全 0 的 bug 根因）',
      );
      expect(t.currentHolding, 0);
    });

    test('信託/贈與等非市場交易：方式別股數欄空 → fallback 到「預定轉讓總股數-自有持股」', () {
      // 真實 live API 列（信託 5347 世界）：方式別股數欄為空，股數在總股數欄。
      // 持股算術驗證：目前持有 231089 − 轉讓後 123089 = 108000。
      final t = TpexInsiderTransfer.fromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '5347',
        'CompanyName': '世界',
        'Date': '1150622',
        '姓名': '王子豪',
        '預定轉讓方式及股數-轉讓方式': '信託',
        '預定轉讓方式及股數-轉讓股數': '', // 信託/贈與/洽特定人此欄恆空
        '預定轉讓總股數-自有持股': '108000',
        '目前持有股數-自有持股': '231089',
        '有效轉讓期間': '1150622~1150624',
      });

      expect(
        t.transferShares,
        108000,
        reason: '方式別股數欄空時須 fallback 到「預定轉讓總股數-自有持股」',
      );
      expect(t.transferMethod, '信託');
    });

    // 兩種方式並存時，官方把兩個方式、兩個股數各自接在同一格（無分隔字元）：
    // 3189 景碩 2026-08-28「一般交易(每日得轉讓股數限制)鉅額逐筆交易」、
    // 8000000＋8000000 → 解析成 80000008000000（持股僅 67037104）。
    // 「預定轉讓總股數」恆為單一數字（自有、信託各一格），改以它為準。
    test('🚨 兩種方式並存：以總股數為準，不讀接在一起的方式別股數', () {
      final t = TpexInsiderTransfer.fromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '3189',
        'Date': '1150828',
        '預定轉讓方式及股數-轉讓方式': '一般交易(每日得轉讓股數限制)鉅額逐筆交易',
        '預定轉讓方式及股數-轉讓股數': '80000008000000',
        '預定轉讓總股數-自有持股': '16000000',
        '目前持有股數-自有持股': '67037104',
      });

      expect(t.transferShares, 16000000);
    });

    test('單一方式：總股數與方式別股數相同（live 2892：259000／259000）', () {
      final t = TpexInsiderTransfer.fromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '2892',
        'Date': '1150925',
        '預定轉讓方式及股數-轉讓方式': ' 一般交易(每日得轉讓股數限制)',
        '預定轉讓方式及股數-轉讓股數': ' 259000',
        '預定轉讓總股數-自有持股': '259000',
        '目前持有股數-自有持股': '259726',
      });

      expect(t.transferShares, 259000);
    });

    // 總股數欄空（舊資料／格式變動）才退回方式別股數；此時若仍讀出比持股
    // 還多的股數，代表格式又不如預期：整筆跳過（計畫轉讓不可能超過持有）
    test('轉讓股數大於目前持股 → 視為格式異常、整筆跳過', () {
      final row = <String, dynamic>{
        'SecuritiesCompanyCode': '3189',
        'Date': '1150828',
        '預定轉讓方式及股數-轉讓方式': '一般交易(每日得轉讓股數限制)鉅額逐筆交易',
        '預定轉讓方式及股數-轉讓股數': '80000008000000',
        '目前持有股數-自有持股': '67037104',
      };
      expect(TpexInsiderTransfer.tryFromJson(row), isNull);
    });

    // 申報表把總股數分成自有、保留運用決定權信託兩格；方式別股數是兩者合計。
    // 只讀自有會把信託部分算成 0（「由受託人持有者」自有為 0）
    test('信託股數：轉讓股數＝自有＋信託總股數', () {
      final t = TpexInsiderTransfer.fromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '2548',
        'Date': '1150824',
        '預定轉讓方式及股數-轉讓方式': '一般交易(每日得轉讓股數限制)',
        '預定轉讓方式及股數-轉讓股數': '300000',
        '預定轉讓總股數-自有持股': '0',
        '預定轉讓總股數-保留運用決定權信託股數': '300000',
        '目前持有股數-自有持股': '0',
        '目前持有股數-保留運用決定權信託股數': '500000',
      });
      expect(t.transferShares, 300000);
    });

    // 轉讓含信託時會超過「自有」持股，防線要和自有＋信託比，不能誤擋
    test('防線比的是自有＋信託持股：含信託的轉讓不被誤擋', () {
      final t = TpexInsiderTransfer.tryFromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '2548',
        'Date': '1150824',
        '預定轉讓總股數-自有持股': '100',
        '預定轉讓總股數-保留運用決定權信託股數': '1000',
        '目前持有股數-自有持股': '100',
        '目前持有股數-保留運用決定權信託股數': '1000',
      });
      expect(t?.transferShares, 1100);
    });

    test('總股數兩格都解析不出數字（如「--」）→ 退回方式別股數', () {
      final t = TpexInsiderTransfer.fromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '2061',
        'Date': '1150618',
        '預定轉讓方式及股數-轉讓股數': '500000',
        '預定轉讓總股數-自有持股': '--',
        '目前持有股數-自有持股': '3232155',
      });
      expect(t.transferShares, 500000);
    });

    test('目前持股不明（0／空）→ 無從比較，保留', () {
      final t = TpexInsiderTransfer.tryFromJson(<String, dynamic>{
        'SecuritiesCompanyCode': '2061',
        'Date': '1150618',
        '預定轉讓方式及股數-轉讓股數': '500000',
      });
      expect(t?.transferShares, 500000);
    });
  });

  group('tryFromTwseJson(TWSE t187ap12_L,2026-08-05 上市源補接)', () {
    Map<String, dynamic> twseRow() => {
      '出表日期': '1150804',
      '公司代號': '6834',
      '公司名稱': '天二科技',
      '申報人身分': '經理人利用他人名義持有者',
      '姓名': '宸芝芝投資有限公司',
      // TWSE 值帶前導空格(live API 實測)——解析必須 trim
      '預定轉讓方式及股數-轉讓方式': ' 一般交易(每日得轉讓股數限制)',
      '預定轉讓方式及股數-轉讓股數': ' 150000',
      '目前持有股數-自有持股': '150000',
      '預定轉讓總股數-自有持股': '150000',
      '有效轉讓期間': '1150807~1150906',
    };

    test('🚨 live 樣本完整解析(欄名差異:公司代號/出表日期/申報人身分)', () {
      final t = TpexInsiderTransfer.tryFromTwseJson(twseRow());

      expect(t, isNotNull);
      expect(t!.symbol, '6834');
      expect(t.reportDate, DateTime(2026, 8, 4));
      expect(t.identity, '經理人利用他人名義持有者');
      expect(t.name, '宸芝芝投資有限公司');
      expect(t.transferMethod, '一般交易(每日得轉讓股數限制)', reason: '前導空格須 trim');
      expect(t.transferShares, 150000);
      expect(t.currentHolding, 150000);
      expect(t.validPeriodStart, DateTime(2026, 8, 7));
      expect(t.validPeriodEnd, DateTime(2026, 9, 6));
    });

    test('方式別股數空(信託/贈與)→ fallback 總股數(與 TPEx 同規則)', () {
      final row = twseRow()
        ..['預定轉讓方式及股數-轉讓方式'] = '贈與'
        ..['預定轉讓方式及股數-轉讓股數'] = ''
        ..['預定轉讓總股數-自有持股'] = '88000';
      final t = TpexInsiderTransfer.tryFromTwseJson(row);
      expect(t!.transferShares, 88000);
    });

    test('🚨 兩種方式並存：以總股數為準（與 TPEx 同規則）', () {
      final row = twseRow()
        ..['預定轉讓方式及股數-轉讓方式'] = ' 一般交易(每日得轉讓股數限制)鉅額逐筆交易'
        ..['預定轉讓方式及股數-轉讓股數'] = ' 80000008000000'
        ..['預定轉讓總股數-自有持股'] = '16000000'
        ..['目前持有股數-自有持股'] = '67037104';
      expect(
        TpexInsiderTransfer.tryFromTwseJson(row)!.transferShares,
        16000000,
      );
    });

    test('轉讓股數大於目前持股 → 整筆跳過（與 TPEx 同規則）', () {
      final row = twseRow()
        ..['預定轉讓方式及股數-轉讓股數'] = ' 80000008000000'
        ..['預定轉讓總股數-自有持股'] = ''
        ..['目前持有股數-自有持股'] = '67037104';
      expect(TpexInsiderTransfer.tryFromTwseJson(row), isNull);
    });

    test('無效代號/日期 → null 不炸', () {
      expect(
        TpexInsiderTransfer.tryFromTwseJson(twseRow()..['公司代號'] = ''),
        isNull,
      );
      expect(
        TpexInsiderTransfer.tryFromTwseJson(twseRow()..['出表日期'] = 'x'),
        isNull,
      );
    });
  });
}
