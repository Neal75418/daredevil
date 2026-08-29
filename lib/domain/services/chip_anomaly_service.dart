import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 籌碼異動類型
enum ChipAnomalyType {
  /// 質押率飆升（>= 70%）
  highPledge,

  /// 內部人轉讓申報
  insiderTransfer,

  /// 外資逼近持股上限（> 上限 × 90%）
  foreignNearLimit,

  /// 融券暴增（當日融券賣出 > 5日均量 × 3，且當日量 ≥ 50 張、均量 ≥ 10 張下限）
  shortSurge,

  /// 法人集中大買/賣（單日淨額 > 30日平均絕對值 × 5）
  institutionalSurge,
}

/// 嚴重度
enum ChipSeverity { high, medium }

/// 單筆籌碼異動
class ChipAnomaly {
  const ChipAnomaly({
    required this.type,
    required this.severity,
    required this.symbol,
    required this.stockName,
    required this.market,
    this.keyValue,
  });

  final ChipAnomalyType type;
  final ChipSeverity severity;
  final String symbol;
  final String stockName;
  final String market;

  /// 關鍵數值（如質押率、張數等）
  final String? keyValue;
}

/// 籌碼異動偵測服務
///
/// 掃描當日市場數據，偵測重大籌碼異動事件。
/// 使用 custom SQL 批次查詢，避免逐檔 N+1 問題。
class ChipAnomalyService {
  ChipAnomalyService({required AppDatabase database}) : _db = database;

  final AppDatabase _db;
  static const String _tag = 'ChipAnomalyService';

  /// 偵測當日籌碼異動，依市場分組回傳
  ///
  /// 每種異動最多回傳 [ChipAnomalyParams.maxResultsPerType] 筆（避免大量結果
  /// 淹沒 dashboard）；截斷在下方彙總迴圈執行，晚於 ETF 排除。
  ///
  /// **ETF 排除（宇宙定義過濾）**：於此彙總處單點過濾，不逐類別各自加
  /// `WHERE industry != 'ETF'`——同三模式選股（mode_recommendation_provider.dart
  /// 的 `droppedEtf`）的宇宙定義理由：本 app 規則設計皆針對個股行為，ETF
  /// 走勢平滑、非個股籌碼訊號的適用對象（實例：006203 元大MSCI台灣曾出現在
  /// 法人集中買賣、00940 元大台灣價值高息曾出現在融券暴增）。
  Future<
    ({Map<String, List<ChipAnomaly>> byMarket, List<String> failedDetectors})
  >
  detectAnomaliesByMarket(DateTime date) async {
    final result = <String, List<ChipAnomaly>>{
      MarketCode.twse: [],
      MarketCode.tpex: [],
    };
    // 靜默稽核 #4:單一偵測器壞掉時,儀表板其他類別照常顯示——「今天
    // 沒有高質押異動」與「高質押偵測壞了」逐 pixel 相同。per-detector
    // 失敗列名,dashboard 據此掛「N 類未偵測」。detector 內層不再自吞
    // (catch 統一在這層,雙層 catch 會讓列名永遠空)。
    final failedDetectors = <String>[];
    Future<List<ChipAnomaly>> guard(
      String key,
      Future<List<ChipAnomaly>> Function() run,
    ) async {
      try {
        return await run();
      } catch (e) {
        AppLogger.warning(_tag, '$key 偵測失敗', e);
        failedDetectors.add(key);
        return const [];
      }
    }

    try {
      final anomaliesFuture = Future.wait([
        guard('highPledge', _detectHighPledge),
        guard('insiderTransfer', () => _detectInsiderTransfers(date)),
        guard('foreignNearLimit', _detectForeignNearLimit),
        guard('shortSurge', () => _detectShortSurge(date)),
        guard('institutionalSurge', () => _detectInstitutionalSurge(date)),
      ]);
      final etfSymbolsFuture = _loadEtfSymbols();

      final anomalies = await anomaliesFuture;
      final etfSymbolsOrNull = await etfSymbolsFuture;
      if (etfSymbolsOrNull == null) failedDetectors.add('etfFilter');
      final etfSymbols = etfSymbolsOrNull ?? const <String>{};

      // 「取前 N」在此處、且排在 ETF 排除**之後**——各 detector 依自己的
      // ORDER BY 回傳全部，不自行截斷。若先截斷再排除（原行為），ETF 佔住的
      // 席位不會由下一名遞補、名單靜默縮水：實測 2026-07-17 融券暴增 top-5
      // 的第 3 名是 00940（ETF），該區只顯示 4 檔而第 6 名補不進來。
      // 與 _detectInstitutionalSurge 流動性閘門同一條規則（見該處註解）。
      for (final list in anomalies) {
        var taken = 0;
        for (final anomaly in list) {
          if (etfSymbols.contains(anomaly.symbol)) continue;
          if (taken >= ChipAnomalyParams.maxResultsPerType) break;
          result[anomaly.market]?.add(anomaly);
          taken++;
        }
      }

      // 依嚴重度排序：high 在前
      for (final market in result.keys) {
        result[market]!.sort((a, b) {
          final sevCmp = a.severity.index.compareTo(b.severity.index);
          if (sevCmp != 0) return sevCmp;
          return a.type.index.compareTo(b.type.index);
        });
      }
    } catch (e) {
      // guard 已把 per-detector 失敗接走,這裡只剩彙總/排序的純運算——
      // 真走到代表全部結果不可信,全列名
      AppLogger.warning(_tag, '偵測籌碼異動失敗', e);
      return (
        byMarket: result,
        failedDetectors: const [
          'highPledge',
          'insiderTransfer',
          'foreignNearLimit',
          'shortSurge',
          'institutionalSurge',
          'etfFilter',
        ],
      );
    }

    return (byMarket: result, failedDetectors: failedDetectors);
  }

  /// 載入 ETF 股票代碼集合，供 [detectAnomaliesByMarket] 彙總時單點過濾用。
  ///
  /// 失敗回 null(靜默稽核 #4):舊版回空集合=過濾靜默失效,異動榜
  /// **混入 ETF** 而無任何症狀——null 讓彙總層把 etfFilter 列進
  /// failedDetectors,榜單照出、註記帶著。
  Future<Set<String>?> _loadEtfSymbols() async {
    try {
      const query = "SELECT symbol FROM stock_master WHERE industry = 'ETF'";
      final rows = await _db.customSelect(query).get();
      return rows.map((row) => row.read<String>('symbol')).toSet();
    } catch (e) {
      AppLogger.warning(_tag, '載入 ETF 清單失敗', e);
      return null;
    }
  }

  /// 質押率「變動觸發」：僅在**新**發生時計入，避免持續高於門檻的股票天天
  /// 佔用「今日偵測到 N 項異常」名額（警示疲勞）。
  ///
  /// 「新」定義（兩者擇一，皆須最新質押率 >=
  /// [FundamentalParams.highPledgeRatioThreshold]）：
  /// - 跨門檻：前次快照 < 門檻、最新快照 >= 門檻
  /// - 持續惡化：兩次快照皆 >= 門檻，但漲幅 >=
  ///   [FundamentalParams.kPledgeAlertDeltaPp]
  ///
  /// 該股無前次快照（僅 1 筆歷史）一律不計入（避免首次同步大量歷史資料時
  /// 洗版）。個股層級的持續性顯示（風險徽章、自選清單警示、股票詳情頁）
  /// 不受影響，見 [FundamentalParams.kPledgeAlertDeltaPp] 文件。
  Future<List<ChipAnomaly>> _detectHighPledge() async {
    const query = '''
        WITH ranked AS (
          SELECT ih.symbol, ih.pledge_ratio,
                 ROW_NUMBER() OVER (PARTITION BY ih.symbol ORDER BY ih.date DESC) AS rn
          FROM insider_holding ih
          WHERE ih.pledge_ratio IS NOT NULL
        ),
        latest AS (
          SELECT symbol, pledge_ratio AS latest_ratio FROM ranked WHERE rn = 1
        ),
        previous AS (
          SELECT symbol, pledge_ratio AS prev_ratio FROM ranked WHERE rn = 2
        )
        SELECT l.symbol, l.latest_ratio, s.name, s.market
        FROM latest l
        INNER JOIN previous p ON l.symbol = p.symbol
        INNER JOIN stock_master s ON l.symbol = s.symbol
        WHERE l.latest_ratio >= ?
          AND (p.prev_ratio < ? OR (l.latest_ratio - p.prev_ratio) >= ?)
        ORDER BY l.latest_ratio DESC
      ''';

    final rows = await _db
        .customSelect(
          query,
          variables: [
            const Variable<double>(FundamentalParams.highPledgeRatioThreshold),
            const Variable<double>(FundamentalParams.highPledgeRatioThreshold),
            const Variable<double>(FundamentalParams.kPledgeAlertDeltaPp),
          ],
        )
        .get();

    return rows.map((row) {
      final ratio = row.read<double>('latest_ratio');
      final ratioStr = ratio.toStringAsFixed(1);
      return ChipAnomaly(
        type: ChipAnomalyType.highPledge,
        severity: ChipSeverity.high,
        symbol: row.read<String>('symbol'),
        stockName: row.read<String>('name'),
        market: row.read<String>('market'),
        keyValue: '$ratioStr%',
      );
    }).toList();
  }

  /// 內部人轉讓：近 [ChipAnomalyParams.insiderTransferLookbackDays] 天內有申報轉讓記錄
  ///
  /// 每檔一列，股數為窗內所有內部人**合計**（多位申報時 keyValue 附註筆數）。
  Future<List<ChipAnomaly>> _detectInsiderTransfers(DateTime date) async {
    final since = date.subtract(
      const Duration(days: ChipAnomalyParams.insiderTransferLookbackDays),
    );

    // 一列 = 一檔公司，數字＝窗內**所有內部人合計**申報股數。
    // 原本用 ROW_NUMBER + rn = 1 取每檔最大單筆，其餘申報人整筆消失：
    // 實測 4568 科際精密 07-23 三位不同經理人（100k/50k/35k）只顯示 100張、
    // 低報 45.9%；且跨檔排名也用被低估的值，2643 捷迅（2 筆合計 79,738）
    // 因此輸給 8155 博智（單筆 50,000）而被截掉。
    // 區塊副標「董監事或大股東申報轉讓股票」與 docstring 皆為公司層級語意。
    const query = '''
        SELECT it.symbol, s.name, s.market,
               SUM(it.transfer_shares) AS transfer_shares,
               COUNT(*)                AS filings
        FROM insider_transfer it
        INNER JOIN stock_master s ON it.symbol = s.symbol
        WHERE it.report_date >= ?
        GROUP BY it.symbol, s.name, s.market
        ORDER BY transfer_shares DESC
      ''';

    final rows = await _db
        .customSelect(query, variables: [Variable.withDateTime(since)])
        .get();

    return rows.map((row) {
      final shares = row.read<int>('transfer_shares');
      final filings = row.read<int>('filings');
      return ChipAnomaly(
        type: ChipAnomalyType.insiderTransfer,
        severity: ChipSeverity.medium,
        symbol: row.read<String>('symbol'),
        stockName: row.read<String>('name'),
        market: row.read<String>('market'),
        keyValue: _formatInsiderShares(shares, filings: filings),
      );
    }).toList();
  }

  /// 外資逼近持股上限：持股比 > 上限 × 90%
  Future<List<ChipAnomaly>> _detectForeignNearLimit() async {
    const query = '''
        SELECT sh.symbol, sh.foreign_shares_ratio, sh.foreign_upper_limit_ratio,
               s.name, s.market
        FROM shareholding sh
        INNER JOIN (
          SELECT symbol, MAX(date) as max_date
          FROM shareholding
          GROUP BY symbol
        ) latest ON sh.symbol = latest.symbol AND sh.date = latest.max_date
        INNER JOIN stock_master s ON sh.symbol = s.symbol
        WHERE sh.foreign_upper_limit_ratio IS NOT NULL
          AND sh.foreign_shares_ratio IS NOT NULL
          AND sh.foreign_upper_limit_ratio > 0
          AND sh.foreign_shares_ratio >= sh.foreign_upper_limit_ratio * 0.9
        ORDER BY (sh.foreign_shares_ratio / sh.foreign_upper_limit_ratio) DESC
      ''';

    final rows = await _db.customSelect(query).get();

    return rows.map((row) {
      final ratio = row.read<double>('foreign_shares_ratio');
      final limit = row.read<double>('foreign_upper_limit_ratio');
      final pct = (ratio / limit * 100).toStringAsFixed(1);
      return ChipAnomaly(
        type: ChipAnomalyType.foreignNearLimit,
        severity: ChipSeverity.medium,
        symbol: row.read<String>('symbol'),
        stockName: row.read<String>('name'),
        market: row.read<String>('market'),
        keyValue: '$pct%',
      );
    }).toList();
  }

  /// 融券暴增：當日融券賣出 > 近 5 日均融券賣出 × [ChipAnomalyParams.shortSurgeMultiplier]
  ///
  /// 絕對量下限採雙路徑避免近零基期假訊號、同時救回冷基期突發建空：
  /// - 標準路徑：當日量 ≥ [ChipAnomalyParams.shortSurgeMinTodayLots] 張
  ///   且 5 日均量 ≥ [ChipAnomalyParams.shortSurgeMinAvgLots] 張
  /// - 高量豁免：當日量 ≥ [ChipAnomalyParams.shortSurgeHighVolTodayLots] 張時，
  ///   均量地板放寬到 [ChipAnomalyParams.shortSurgeHighVolMinAvgLots] 張
  /// avg5d 一律先以最低均量地板（HighVolMinAvgLots=3 張）HAVING 預過濾，排除近零
  /// 基期爆值（如 3528 均 0.333 張的 687 倍噪音）。
  Future<List<ChipAnomaly>> _detectShortSurge(DateTime date) async {
    final dateLowerBound = date.subtract(
      const Duration(days: ChipAnomalyParams.shortSurgeLookbackDays),
    );
    final disposalLookback = date.subtract(
      const Duration(days: ChipAnomalyParams.disposalExclusionLookbackDays),
    );

    const query =
        '''
        WITH recent AS (
          SELECT mt.symbol, mt.date, mt.short_sell,
                 s.name, s.market,
                 ROW_NUMBER() OVER (PARTITION BY mt.symbol ORDER BY mt.date DESC) AS rn
          FROM margin_trading mt
          INNER JOIN stock_master s ON mt.symbol = s.symbol
          WHERE mt.date <= ? AND mt.date >= ? AND mt.short_sell IS NOT NULL
        ),
        today AS (
          -- 與 _detectInstitutionalSurge 同一個 bug class：rn = 1 是「窗內最近
          -- 一列」，停牌股會拿停牌前最後一天冒充今日。此側目前無症狀
          -- （2026-07-24 實測 1,993 檔當日、僅 1 檔過期），修的是同型潛伏。
          SELECT symbol, name, market, short_sell
          FROM recent WHERE rn = 1 AND date = ?
            AND short_sell >= ${ChipAnomalyParams.shortSurgeMinTodayLots}
        ),
        avg5d AS (
          SELECT symbol, AVG(short_sell) AS avg_short
          FROM recent WHERE rn BETWEEN 2 AND 6
          GROUP BY symbol
          HAVING AVG(short_sell) >= ${ChipAnomalyParams.shortSurgeHighVolMinAvgLots}
        )
        SELECT t.symbol, t.name, t.market, t.short_sell, a.avg_short,
               (t.short_sell / a.avg_short) AS ratio
        FROM today t
        INNER JOIN avg5d a ON t.symbol = a.symbol
        WHERE t.short_sell > a.avg_short * ${ChipAnomalyParams.shortSurgeMultiplier}
          AND (
            a.avg_short >= ${ChipAnomalyParams.shortSurgeMinAvgLots}
            OR t.short_sell >= ${ChipAnomalyParams.shortSurgeHighVolTodayLots}
          )
          AND t.symbol NOT IN (
            SELECT symbol FROM trading_warning
            WHERE warning_type = 'DISPOSAL' AND date >= ?
          )
        ORDER BY ratio DESC
      ''';

    final rows = await _db
        .customSelect(
          query,
          variables: [
            Variable.withDateTime(date), // recent: mt.date <= ?
            Variable.withDateTime(dateLowerBound), // recent: mt.date >= ?
            Variable.withDateTime(date), // today: date = ?
            Variable.withDateTime(disposalLookback), // DISPOSAL 排除
          ],
        )
        .get();

    return rows.map((row) {
      final ratio = row.read<double>('ratio');
      return ChipAnomaly(
        type: ChipAnomalyType.shortSurge,
        severity: ChipSeverity.medium,
        symbol: row.read<String>('symbol'),
        stockName: row.read<String>('name'),
        market: row.read<String>('market'),
        keyValue: '${ratio.toStringAsFixed(1)}倍',
      );
    }).toList();
  }

  /// 法人集中大買/賣：單日絕對淨額 > 均值 × [ChipAnomalyParams.institutionalSurgeMultiplier]
  ///
  /// 使用倍率門檻替代 Z-score，避免 SQLite 中計算標準差的複雜度。
  Future<List<ChipAnomaly>> _detectInstitutionalSurge(DateTime date) async {
    final dateLowerBound = date.subtract(
      const Duration(days: ChipAnomalyParams.institutionalSurgeLookbackDays),
    );
    final disposalLookback = date.subtract(
      const Duration(days: ChipAnomalyParams.disposalExclusionLookbackDays),
    );

    const query =
        '''
        WITH recent AS (
          SELECT di.symbol, di.date,
                 COALESCE(di.foreign_net, 0) + COALESCE(di.investment_trust_net, 0) + COALESCE(di.dealer_net, 0) AS total_net,
                 s.name, s.market,
                 ROW_NUMBER() OVER (PARTITION BY di.symbol ORDER BY di.date DESC) AS rn
          FROM daily_institutional di
          INNER JOIN stock_master s ON di.symbol = s.symbol
          WHERE di.date <= ? AND di.date >= ?
        ),
        today AS (
          -- 必須是「當日那筆」而非「最近那筆」：停牌股的 rn = 1 會是停牌前
          -- 最後一個交易日，被當成今日訊號（實測 6806 森崴能源落後 32 天，
          -- 卻排在全域第 3、佔據面板首位，而標題寫的是「今日偵測到」）
          SELECT symbol, name, market, total_net
          FROM recent WHERE rn = 1 AND ABS(total_net) > 0 AND date = ?
        ),
        avg30d AS (
          SELECT symbol, AVG(ABS(total_net)) AS avg_abs_net
          FROM recent WHERE rn BETWEEN 2 AND 31
          GROUP BY symbol
          HAVING COUNT(*) >= 10 AND AVG(ABS(total_net)) > 0
        )
        SELECT t.symbol, t.name, t.market, t.total_net,
               a.avg_abs_net,
               (ABS(t.total_net) / a.avg_abs_net) AS surge_ratio
        FROM today t
        INNER JOIN avg30d a ON t.symbol = a.symbol
        WHERE ABS(t.total_net) > a.avg_abs_net * ${ChipAnomalyParams.institutionalSurgeMultiplier}
          AND t.symbol NOT IN (
            SELECT symbol FROM trading_warning
            WHERE warning_type = 'DISPOSAL' AND date >= ?
          )
        ORDER BY surge_ratio DESC
      ''';

    final rows = await _db
        .customSelect(
          query,
          variables: [
            Variable.withDateTime(date), // recent: di.date <= ?
            Variable.withDateTime(dateLowerBound), // recent: di.date >= ?
            Variable.withDateTime(date), // today: date = ?
            Variable.withDateTime(disposalLookback), // DISPOSAL 排除
          ],
        )
        .get();

    // 流動性閘門——與 CandidateSelector 同一組常數與慣例（3,000 萬 / 20 日
    // 中位數，2026-07-11 實測校準）。純比值判準的分母對法人幾乎不參與的
    // 股票趨近於零，任何微小成交都破表：實測 5523 豐謙當日 13 張、均量
    // 1.6 張 → 8.1 倍過關，而它每天只成交約 130 萬元。
    //
    // **必須在取前 N 之前過濾**：maxResultsPerType 是全域上限且依倍數排序，
    // 若先取前 N 再過濾，名單只會變短、真訊號永遠遞補不上來（實測 8 個顯示
    // 位置有 6 個不可交易，而中位成交 25.66 億的華星光排第 9）。
    final medianTurnover = await _db.getMedianTurnoverBatch(
      endDate: date,
      windowDays: RuleParams.liquidityMedianWindowDays,
      minDataDays: RuleParams.liquidityMinDataDays,
    );
    final watchlist = (await _db.getWatchlist()).map((w) => w.symbol).toSet();
    bool isTradeable(String symbol) {
      if (watchlist.contains(symbol)) return true; // 自選豁免：使用者主動追蹤
      final median = medianTurnover[symbol];
      // map 內沒有 = 有效天數不足、無法判定 → permissive 放行
      return median == null ||
          median >= RuleParams.liquidityMinMedianTurnoverNtd;
    }

    return rows.where((row) => isTradeable(row.read<String>('symbol'))).map((
      row,
    ) {
      final totalNet = row.read<double>('total_net');
      final isBuy = totalNet > 0;
      // DB 以「股」為單位，除以 1000 轉換為「張」後格式化
      final formatted = _formatSheets(totalNet.abs() / 1000);
      return ChipAnomaly(
        type: ChipAnomalyType.institutionalSurge,
        severity: ChipSeverity.high,
        symbol: row.read<String>('symbol'),
        stockName: row.read<String>('name'),
        market: row.read<String>('market'),
        keyValue: '${isBuy ? '+' : '-'}$formatted',
      );
    }).toList();
  }
}

/// 格式化張數（top-level，與 widget 層 _formatAmount 風格一致）
String _formatSheets(double value) {
  final absVal = value.abs();
  if (absVal >= 10000) {
    return '${(absVal / 10000).toStringAsFixed(1)}萬張';
  }
  return '${absVal.toStringAsFixed(0)}張';
}

/// 格式化內部人轉讓股數（股 → 張）
///
/// - shares == 0：申報尚未確定股數，使用 [kZeroInsiderTransfer] 哨兵值
/// - shares 1–999：不足一張，顯示 `<1張`（避免四捨五入誤判為零）
/// - shares ≥ 1000：正常換算為張數
String _formatInsiderShares(int shares, {int filings = 1}) {
  final base = shares == 0
      ? kZeroInsiderTransfer
      : shares < 1000
      ? '<1張'
      : '${shares ~/ 1000}張';
  // 多位內部人同期申報 ≠ 一人申報，筆數本身就是訊號強度的一部分。
  // 版面安全：同列的股名是 Expanded + ellipsis，值變長只擠壓股名。
  return filings > 1 ? '$base（$filings 筆）' : base;
}

/// 內部人轉讓「股數為零」的哨兵值
///
/// 由 service 產生、widget 消費，集中定義避免跨層硬編碼字串比對。
const kZeroInsiderTransfer = '0張';
