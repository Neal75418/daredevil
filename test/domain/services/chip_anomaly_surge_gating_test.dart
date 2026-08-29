// 法人集中買賣：停牌股冒充今日 + 薄流動性股佔用名額
//
// 實測（2026-07-26 正式 DB，資料日 2026-07-24）：
//
// **一、停牌股用一個月前的資料冒充今日**
// `today` CTE 取 `rn = 1`——「60 天窗內最近的一列」，但**沒有比對目標
// 日期**。6806 森崴能源的法人與價格資料都停在 2026-06-22（停牌），那筆
// 32 天前的 -3,151 張仍被列入，而面板標題當時寫的是「今日偵測到 N 項異常」
// （該文案已於後續 commit 移除時間宣稱，見 chip_anomaly_time_semantics_test）。
// 24 檔命中裡有 2 檔日期不是 7/24（森崴能源落後 32 天、佳總落後 9 天），
// 而森崴能源正好排在全域第 3、佔據上市面板首位。
// 這與評分管線先前修掉的 staleBar 是同一類：取「最近一筆」而非「當日那筆」。
//
// **二、薄流動性股把真訊號擠出名單**
// 判準是純比值（單日 |淨額| > 30 日均值 × 5），分母對法人幾乎不參與的
// 股票趨近於零，於是任何微小成交都破表。5523 豐謙除了當日 -13 張，前面
// 每天都是 ±1~5 張，均量 1.6 張 → 8.1 倍過關；而它的 20 日**中位**成交值
// 只有 0.013 億（每天約 130 萬元），根本買不到。
//
// 而 `maxResultsPerType = 5` 是**全域**上限（非每市場），排序又依倍數，
// 所以雜訊直接吃掉名額：8 個顯示位置有 6 個是不可交易的股票，而華星光
// （中位成交 25.66 億、當日 3,115 張）排第 9 永遠看不到。
//
// 提高倍數門檻治不好——雜訊的倍數反而更高（竣邦 30.0×、光隆 17.7×、
// 豐謙 8.1× vs 華星光 5.5×），拉高門檻會先殺掉真訊號。
//
// **修法**：沿用候選層既有的流動性下限（`RuleParams
// .liquidityMinMedianTurnoverNtd` 3,000 萬 / 20 日**中位數**，2026-07-11
// 實測校準：砍 56% 無效運算、訊號股僅損失 7%），連同「資料不足 permissive
// 放行」與「自選清單豁免」一併比照 `CandidateSelector`。中位數而非平均是
// 關鍵——統一美國50 的 20 日平均 0.31 億過關、中位數 0.291 億不過，正是
// 該常數註解所說的「單日爆量讓殭屍股短暫通過」。
//
// 排序維持倍數：閘門管「值不值得看」、排序管「多異常」，兩件事分開。
// 過濾必須在取前 N **之前**，否則只是把名單變短，真訊號不會遞補上來。
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/chip_anomaly_service.dart';

void main() {
  late AppDatabase db;
  late ChipAnomalyService service;

  final asOf = DateTime.utc(2026, 7, 24);

  /// 高於門檻的日成交值（3,000 萬的十倍，確保中位數穩穩過關）
  const liquidTurnover = RuleParams.liquidityMinMedianTurnoverNtd * 10;

  /// 遠低於門檻（每天約 130 萬，對應實測的 5523 豐謙）
  const thinTurnover = 1300000.0;

  setUp(() async {
    db = AppDatabase.forTesting();
    service = ChipAnomalyService(database: db);
  });

  tearDown(() async => db.close());

  Future<void> addStock(String symbol, String name, {String market = 'TWSE'}) =>
      db.upsertStocks([
        StockMasterCompanion.insert(symbol: symbol, name: name, market: market),
      ]);

  /// 灌 [days] 個交易日的價格，日成交值固定為 [turnoverPerDay]。
  /// close 固定 100 → volume = turnover / 100。
  Future<void> addPrices(
    String symbol, {
    required double turnoverPerDay,
    int days = 25,
    DateTime? lastDate,
  }) async {
    final last = lastDate ?? asOf;
    await db.insertPrices([
      for (var i = 0; i < days; i++)
        DailyPriceCompanion.insert(
          symbol: symbol,
          date: last.subtract(Duration(days: i)),
          close: const Value(100.0),
          volume: Value(turnoverPerDay / 100),
        ),
    ]);
  }

  /// 平常每天 [baseline] 股，最新一日 [todayNet] 股。
  /// [lastDate] 用來模擬停牌（最新一列早於 asOf）。
  Future<void> addInstitutional(
    String symbol, {
    required double baseline,
    required double todayNet,
    DateTime? lastDate,
  }) async {
    final last = lastDate ?? asOf;
    await db.insertInstitutionalData([
      DailyInstitutionalCompanion.insert(
        symbol: symbol,
        date: last,
        foreignNet: Value(todayNet),
      ),
      for (var i = 1; i <= 20; i++)
        DailyInstitutionalCompanion.insert(
          symbol: symbol,
          date: last.subtract(Duration(days: i)),
          // 正負交錯，避免同時觸發連續買賣超類判斷
          foreignNet: Value(i.isEven ? baseline : -baseline),
        ),
    ]);
  }

  Future<List<String>> surgeSymbols() async {
    final byMarket = (await service.detectAnomaliesByMarket(asOf)).byMarket;
    return [
      for (final list in byMarket.values)
        for (final a in list)
          if (a.type == ChipAnomalyType.institutionalSurge) a.symbol,
    ];
  }

  group('停牌股不得冒充今日', () {
    test('🚨 最新法人列早於資料日者不列入（實測 6806 森崴能源落後 32 天）', () async {
      await addStock('6806', '森崴能源');
      await addPrices('6806', turnoverPerDay: liquidTurnover);
      // 資料停在 32 天前，仍是它自己「最近的一列」
      await addInstitutional(
        '6806',
        baseline: 100000,
        todayNet: -3151000,
        lastDate: asOf.subtract(const Duration(days: 32)),
      );

      expect(
        await surgeSymbols(),
        isNot(contains('6806')),
        reason: '一個月前的停牌資料不是今日訊號',
      );
    });

    test('當日有列者照常列入（確認上一條不是把功能整個關掉）', () async {
      await addStock('2330', '台積電');
      await addPrices('2330', turnoverPerDay: liquidTurnover);
      await addInstitutional('2330', baseline: 100000, todayNet: -3151000);

      expect(await surgeSymbols(), contains('2330'));
    });
  });

  group('流動性閘門', () {
    test('🚨 薄流動性股不得列入（實測 5523 豐謙：13 張 / 中位成交 130 萬）', () async {
      await addStock('5523', '豐謙', market: 'TPEx');
      await addPrices('5523', turnoverPerDay: thinTurnover);
      await addInstitutional('5523', baseline: 1600, todayNet: -13000);

      expect(
        await surgeSymbols(),
        isNot(contains('5523')),
        reason: '每天只成交 130 萬元的股票，滑價會吃掉整個 edge——訊號必須可交易',
      );
    });

    test('🚨 過濾須在取前 N 之前：雜訊讓位後真訊號要遞補上來', () async {
      // maxResultsPerType 個雜訊（倍數更高，會排在真訊號前面）
      for (var i = 0; i < RuleParams.liquidityMedianWindowDays && i < 6; i++) {
        final s = 'N$i';
        await addStock(s, '雜訊$i', market: 'TPEx');
        await addPrices(s, turnoverPerDay: thinTurnover);
        // 倍數 ~20 倍，遠高於真訊號
        await addInstitutional(s, baseline: 1000, todayNet: -20000);
      }
      // 真訊號：倍數較低但完全可交易
      await addStock('4979', '華星光', market: 'TPEx');
      await addPrices('4979', turnoverPerDay: liquidTurnover);
      await addInstitutional('4979', baseline: 500000, todayNet: 3115000);

      expect(
        await surgeSymbols(),
        contains('4979'),
        reason: '若先取前 N 再過濾，名單只會變短；真訊號永遠遞補不上來',
      );
    });

    test('自選清單豁免（與 CandidateSelector 一致——使用者主動追蹤）', () async {
      await addStock('5523', '豐謙', market: 'TPEx');
      await addPrices('5523', turnoverPerDay: thinTurnover);
      await addInstitutional('5523', baseline: 1600, todayNet: -13000);
      await db.addToWatchlist('5523');

      expect(await surgeSymbols(), contains('5523'));
    });

    test('價格資料不足無法判定中位數時 permissive 放行（與候選層同慣例）', () async {
      await addStock('9999', '新上市', market: 'TPEx');
      // 只有 3 天價格 → 低於 liquidityMinDataDays，無法判定
      await addPrices('9999', turnoverPerDay: thinTurnover, days: 3);
      await addInstitutional('9999', baseline: 100000, todayNet: -3151000);

      expect(
        await surgeSymbols(),
        contains('9999'),
        reason: '無法判定 ≠ 不流動；候選層對這種情況也是放行',
      );
    });
  });

  // 同型掃描（bug class sweep）：融券暴增用的是同一個 `rn = 1` 取區間內最近列
  // 的寫法，同樣沒有比對目標日期。
  //
  // 五個 detector 掃過：法人集中買賣與融券暴增兩者是 `date DESC` + 區間（同型）；
  // 內部人轉讓的 rn 依 `transfer_shares DESC`（刻意取窗內最大，非日期語意）；
  // 高質押率與外資接近上限不收 date 參數（定期揭露非每日事件）。
  //
  // 實測 2026-07-24 正式 DB：融券暴增這側目前**只有 1 檔**最新列非當日
  // （1,993 檔當日），面板上顯示的 5 檔全部是 7/24 —— 也就是說這裡是**同型
  // 潛伏、目前無症狀**。仍然要修：它與剛在法人集中買賣上實際發作的
  // （6806 森崴能源落後 32 天卻佔據面板首位）是同一個 bug class。
  //
  // 不在此加流動性閘門：融券側已有三道絕對量地板
  // （shortSurgeMinTodayLots 50 / shortSurgeMinAvgLots 10 / 高量豁免 100），
  // 實測也沒有雜訊佔位的現象。
  group('同型：融券暴增', () {
    Future<void> addMargin(
      String symbol, {
      required double baseline,
      required double todayShort,
      DateTime? lastDate,
    }) async {
      final last = lastDate ?? asOf;
      await db.insertMarginTradingData([
        MarginTradingCompanion.insert(
          symbol: symbol,
          date: last,
          shortSell: Value(todayShort),
        ),
        for (var i = 1; i <= 6; i++)
          MarginTradingCompanion.insert(
            symbol: symbol,
            date: last.subtract(Duration(days: i)),
            shortSell: Value(baseline),
          ),
      ]);
    }

    Future<List<String>> shortSurgeSymbols() async {
      final byMarket = (await service.detectAnomaliesByMarket(asOf)).byMarket;
      return [
        for (final list in byMarket.values)
          for (final a in list)
            if (a.type == ChipAnomalyType.shortSurge) a.symbol,
      ];
    }

    test('🚨 最新融券列早於資料日者不列入', () async {
      await addStock('9001', '停牌股');
      await addMargin(
        '9001',
        baseline: 20,
        todayShort: 200,
        // 5 天前：在 shortSurgeLookbackDays(15) 窗內但非當日。
        // （20 天前會整批落在窗外被區間條件擋掉 → 測試假綠）
        lastDate: asOf.subtract(const Duration(days: 5)),
      );

      expect(
        await shortSurgeSymbols(),
        isNot(contains('9001')),
        reason: '與法人集中買賣同一個 bug class：取「最近一筆」而非「當日那筆」',
      );
    });

    test('當日有列者照常列入（確認沒把功能關掉）', () async {
      await addStock('9002', '正常股');
      await addMargin('9002', baseline: 20, todayShort: 200);

      expect(await shortSurgeSymbols(), contains('9002'));
    });
  });

  // ETF 過濾發生在「取前 N 之後」——席位空轉不遞補
  //
  // b66b6de 為流動性閘門立下的規則就寫在 chip_anomaly_service.dart:439-442：
  // 「必須在取前 N 之前過濾……若先取前 N 再過濾，名單只會變短、真訊號永遠
  // 遞補不上來」。但同一個檔案裡還有**更晚的一層**：ETF 排除在彙總處
  // （:93 `if (etfSymbols.contains(anomaly.symbol)) continue;`）執行，而各
  // detector 早已各自 `LIMIT 5`（:163/:219/:262/:342）或 `.take(5)`（:459）。
  // 被丟掉的席位不會由第 6 名遞補。
  //
  // 實測（正式 DB 2026-07-17）：融券暴增 top-5 是
  // [1514 亞力 57.4×, 3149 正達 37.7×, **00940 元大台灣價值高息(ETF)** 32.3×,
  //  2303 聯電 32.1×, 3324 雙鴻 29.0×] —— 00940 佔第 3 名後被丟棄，該區只剩
  // 4 檔，而排第 6 的個股永遠補不進來。使用者看不見：類別徽章顯示的是過濾
  // 後的數量，縮水完全靜默。
  //
  // 修法不是把 ETF 條件推進各 detector 的 SQL —— :65-69 的 docstring 明說
  // 刻意在彙總處單點過濾（宇宙定義 DRY，與 mode_recommendation_provider 的
  // droppedEtf 同一理由）。正解是**把「取前 N」也移到彙總處、排在所有過濾
  // 之後**：SQL 依序回傳全部 → detector 內流動性過濾 → 彙總處 ETF 過濾 →
  // 取前 N。各 detector 無上限的列數實測為 6/23/24/33，量體安全。
  group('ETF 過濾不得讓席位空轉', () {
    Future<void> addMargin(
      String symbol, {
      required double baseline,
      required double todayShort,
    }) => db.insertMarginTradingData([
      MarginTradingCompanion.insert(
        symbol: symbol,
        date: asOf,
        shortSell: Value(todayShort),
      ),
      for (var i = 1; i <= 6; i++)
        MarginTradingCompanion.insert(
          symbol: symbol,
          date: asOf.subtract(Duration(days: i)),
          shortSell: Value(baseline),
        ),
    ]);

    Future<List<String>> shortSurgeSymbols() async {
      final byMarket = (await service.detectAnomaliesByMarket(asOf)).byMarket;
      return [
        for (final list in byMarket.values)
          for (final a in list)
            if (a.type == ChipAnomalyType.shortSurge) a.symbol,
      ];
    }

    test('🚨 ETF 佔住的席位須由下一名遞補，不得讓名單縮水', () async {
      // 6 檔合格，倍數遞減：E1(ETF) 排第 3，S6 排第 6
      const ratios = [10.0, 8.0, 6.0, 5.0, 4.0, 3.5];
      for (var i = 0; i < 6; i++) {
        final isEtf = i == 2;
        final sym = isEtf ? '00940' : 'S${i + 1}';
        await db.upsertStocks([
          StockMasterCompanion.insert(
            symbol: sym,
            name: isEtf ? '元大台灣價值高息' : '個股${i + 1}',
            market: 'TWSE',
            industry: Value(isEtf ? 'ETF' : '電子工業'),
          ),
        ]);
        await addMargin(sym, baseline: 100, todayShort: 100 * ratios[i]);
      }

      final got = await shortSurgeSymbols();

      expect(
        got,
        isNot(contains('00940')),
        reason: 'ETF 本來就該排除（宇宙定義），這部分現行行為正確',
      );
      expect(
        got.length,
        ChipAnomalyParams.maxResultsPerType,
        reason:
            'ETF 讓出的席位必須由第 6 名遞補。現行實作先 LIMIT 5 再丟 ETF，'
            '名單直接縮成 4 筆，而符合條件的個股永遠補不進來',
      );
      expect(got, contains('S6'), reason: '第 6 名就是應該遞補上來的那一檔');
    });
  });

  // 內部人轉讓：每檔只取「最大單筆」而非合計
  //
  // `ROW_NUMBER() OVER (PARTITION BY it.symbol ORDER BY it.transfer_shares DESC)`
  // + `WHERE rn = 1` 等同 per-symbol MAX，其餘申報人整筆消失；外層
  // `ORDER BY transfer_shares DESC` 也是拿這個 MAX 去跨檔排名。
  //
  // 實測正式 DB（全表 9 列 / 6 檔）——多筆的語意是**不同的人**，不是拆單：
  //   4568 科際精密 07-23 三筆，皆「經理人本人」但三位不同姓名
  //       柯承恩 100,000 / 林功穎 50,000 / 陳英毅 35,000
  //       → 顯示 100張，實際合計 185張，低報 45.9%
  //   2643 捷迅 07-15 兩筆：董事本人 顧城明 39,869、經理人本人 李佳慧 39,869
  //       → 低報 50.0%
  //
  // 排名同樣被扭曲：2643（2 筆合計 79,738）落在 8155 博智（單筆 50,000）
  // 之後，被 LIMIT 5 截掉而完全不出現。
  //
  // 區塊副標是「董監事或大股東申報轉讓股票」——公司層級語意，SUM 才對得上；
  // docstring（:205）也只寫「有申報轉讓記錄」，沒有任何一處承諾 per-filer。
  // 5 個既有測試全部只插一列，沒有任何測試把 MAX 釘為預期行為。
  //
  // 「三位經理人同日集體申報」與「一人申報」是不同強度的訊號，所以合計後
  // 附註筆數。版面安全：值旁的股名是 Expanded + ellipsis，值變長只會擠壓
  // 股名，不會 RenderFlex overflow。
  group('內部人轉讓須合計而非取最大單筆', () {
    Future<void> addTransfers(
      String symbol,
      List<({String who, int shares})> filings, {
      int daysAgo = 3,
    }) => db.insertInsiderTransfers([
      for (final f in filings)
        InsiderTransferCompanion.insert(
          symbol: symbol,
          reportDate: asOf.subtract(Duration(days: daysAgo)),
          identity: '經理人本人',
          name: f.who,
          transferMethod: '信託',
          transferShares: f.shares,
          currentHolding: 1000000,
        ),
    ]);

    Future<List<ChipAnomaly>> insiderRows() async {
      final byMarket = (await service.detectAnomaliesByMarket(asOf)).byMarket;
      return [
        for (final list in byMarket.values)
          for (final a in list)
            if (a.type == ChipAnomalyType.insiderTransfer) a,
      ];
    }

    test('🚨 同檔多位內部人申報須合計（實測 4568：100/50/35 → 185張，非 100張）', () async {
      await addStock('4568', '科際精密', market: 'TPEx');
      await addTransfers('4568', [
        (who: '柯承恩', shares: 100000),
        (who: '林功穎', shares: 50000),
        (who: '陳英毅', shares: 35000),
      ]);

      final rows = await insiderRows();

      expect(
        rows.single.keyValue,
        contains('185張'),
        reason: '顯示最大單筆等於低報 45.9%',
      );
    });

    test('多筆時標示筆數（集體申報與單人申報是不同強度的訊號）', () async {
      await addStock('4568', '科際精密', market: 'TPEx');
      await addTransfers('4568', [
        (who: '柯承恩', shares: 100000),
        (who: '林功穎', shares: 50000),
        (who: '陳英毅', shares: 35000),
      ]);

      expect((await insiderRows()).single.keyValue, '185張（3 筆）');
    });

    test('單筆維持原格式（不得因此改動既有 4 個格式化測試的預期）', () async {
      await addStock('8155', '博智', market: 'TPEx');
      await addTransfers('8155', [(who: '張義德', shares: 50000)]);

      expect((await insiderRows()).single.keyValue, '50張');
    });

    test('🚨 跨檔排名依合計值（2 筆中量須勝過 1 筆小量）', () async {
      await addStock('2643', '捷迅', market: 'TPEx');
      await addTransfers('2643', [
        (who: '顧城明', shares: 39869),
        (who: '李佳慧', shares: 39869),
      ]);
      await addStock('8155', '博智', market: 'TPEx');
      await addTransfers('8155', [(who: '張義德', shares: 50000)]);

      final rows = await insiderRows();

      expect(
        rows.first.symbol,
        '2643',
        reason: '合計 79,738 > 50,000；用 MAX(39,869) 排名會讓它輸給單筆小量的 8155',
      );
    });

    test('全部申報皆 0 股時仍走零股哨兵', () async {
      await addStock('9003', '零股申報', market: 'TPEx');
      await addTransfers('9003', [
        (who: '甲', shares: 0),
        (who: '乙', shares: 0),
      ]);

      expect(
        (await insiderRows()).single.keyValue,
        contains(kZeroInsiderTransfer),
      );
    });
  });
}
