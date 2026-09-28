import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/calibration_thresholds.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 規則準確度追蹤服務
///
/// 從 `daily_reason` 直接聚合，計算每條規則的命中率和平均報酬率，寫入
/// `rule_accuracy` 表供 stock-detail 規則命中率 UI 消費。支援多持有天數
/// (1, 3, 5, 10, 20, 60 交易日)。
///
/// **誠實揭露：不是「unbiased」統計**（2026-07-18 audit 修訂前的 class doc
/// 曾如此宣稱，與同檔案內的已知偏誤註解自相矛盾）。目前狀態：
/// - Lookahead bias（entry 用訊號當日 close）：**已修復**，見下方
///   `_computeUnbiasedRuleStats` 內 "(1) Lookahead bias" 註解。
/// - Survivorship bias（下市股尾端訊號靜默剔除）：**已修復**，見 "(2)"
///   註解與 [CalibrationThresholds.stalePriceThresholdDays]。
/// - Zero/negative price false hit（entry/exit 為 0 時除以零得 +Infinity，
///   或 exit=0 被算成假 -100% 虧損）：**已修復**（review finding，
///   2026-07-18），見下方 entry/exit guard 的 `<= 0` 分支。
/// - **Co-occurrence inflation：仍未修復**（已知限制，本次不處理）。同
///   (symbol, date) 多條規則同時觸發時，同一個 forward return 被計入每條
///   規則，hit_rate 可能被少數共現事件膨脹；完整修正（按規則對 return
///   加權降權）超出目前範圍。`_BiasCounters` / `co_occurrence_index` 揭露
///   程度，但只寫 log，不直接影響數字。緩解措施：[getRuleSummaryText]
///   在樣本數低於 [CalibrationThresholds.sampleSizeCutThreshold] 時附上
///   低信心註記——降低小樣本規則被誤讀為「精準」的風險，但不消除偏誤本身。
///
/// **成功判定**：per-period threshold 取代寬鬆的 `>0` 基準，避免「勉強沒虧」
/// 被算成命中。Threshold 來源為 [CalibrationThresholds.successThresholds]，
/// 與 `tool/replay_calibrator.dart` 跟 `tool/recalibrate.dart` 共用同一份
/// 常數，避免不同 writer 用不同門檻寫 rule_accuracy 表造成 calibration
/// 不可重現。
class RuleAccuracyService {
  RuleAccuracyService({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  static const String _tag = 'RuleAccuracyService';

  /// 預設驗證天數
  static const int defaultHoldingDays = 5;

  /// 支援的持有天數（1D/3D 短線 + 5D/10D/20D 中線 + 60D 長線）
  static const List<int> holdingPeriods = [1, 3, 5, 10, 20, 60];

  /// 判定 `returnRate`（%）是否達到 `period` 的命中門檻
  ///
  /// 使用 `>=`（含）而非 `>`（嚴格）— 邊界 case（returnRate 剛好等於
  /// CalibrationThresholds.successThresholds 的門檻值）算命中，對應
  /// 「門檻就是及格線」的直覺。
  static bool _isSuccessFor(double returnRate, int period) {
    final threshold =
        CalibrationThresholds.successThresholds[period] ??
        CalibrationThresholds.defaultSuccessThreshold;
    return returnRate >= threshold;
  }

  /// 更新規則準確度統計（per-period + 彙總）
  ///
  /// 2026-04 Stage 2 Commit 2：改用 [_computeUnbiasedRuleStats] 從 [daily_reason]
  /// 直接聚合，取代舊的 `primary_rule_id` from `recommendation_validation` 路徑。
  ///
  /// Public contract：`UpdateService` 的 post-update hook 在每次更新後呼叫此
  /// method 重算 `rule_accuracy`。
  Future<void> updateRuleAccuracyStats() async {
    await _computeUnbiasedRuleStats();
  }

  /// 從 `daily_reason` + `daily_price` 聚合 per-rule 統計寫入 `rule_accuracy`。
  ///
  /// 方法名的 "Unbiased" 是相對於它取代的舊實作（見下方 Gap 1），**不代表結果
  /// 無偏**——co-occurrence inflation 仍未修，且 `daily_reason` 只在分數過門檻時
  /// 才落庫。完整揭露見 class doc 的「誠實揭露」段。
  ///
  /// ## 為什麼這樣做（修 Gap 1 primary_rule_id bias）
  ///
  /// 舊實作從 `recommendation_validation` 依 `primary_rule_id` 聚合，只統計每次推薦
  /// 的「最高分那條規則」。後果：常作為 rank 1 / rank 2 的規則（例如 `VOLUME_SPIKE`
  /// 一觸發通常被 `REVERSAL_W2S` 的 35 分壓過）**永遠拿不到樣本**，整個 calibration
  /// 管線變成「強者恆強」的同義複製。
  ///
  /// 新實作直接掃 `daily_reason` — 每個觸發事件都計入，不再受 rank 偏見影響。
  /// universe 是「全部成立訊號的股票」而非「Top 20 推薦」，進一步消除 survivor bias。
  ///
  /// **註（觀察區）**：`daily_reason` 的持久化門檻已降到 `observationScoreThreshold`
  /// （8，供掃描頁「觀察區」用），但校準須維持「只學成立訊號」。故
  /// [_computeUnbiasedRuleStats] 顯式過濾到 signal-tier（任一 horizon ≥
  /// `minScoreThreshold`）的 (symbol, date)，使校準樣本與門檻調整前一致、不被
  /// 觀察層（8–11）污染。
  ///
  /// ## Algorithm
  ///
  /// 1. 撈所有 `daily_reason` rows
  /// 2. **Empty guard**：若為空 → warning log 後**不動 `rule_accuracy`** 直接 return
  ///    （防止誤清既有 valid stats — 詳見下方「Empty guard」段落）
  /// 3. 為相關 symbols 建 price lookup map `{symbol: {normalized_date: (open, close)}}`
  /// 4. **Stale-symbol 過濾**（audit finding #7a）：symbol 最新價格早於
  ///    dataset max date 超過 [CalibrationThresholds.stalePriceThresholdDays]
  ///    → 整個 symbol 的 reason 排除（survivorship bias fix，見上方偏誤註解）
  /// 5. 對每個 reason × 每個 holding period：
  ///    - 查 entry（訊號隔日 open，缺值 fallback close；lookahead bias fix）
  ///      / exit close（exit date 由 [TaiwanCalendar.addTradingDays] 算）；
  ///      兩者皆需 `> 0`，否則視同缺值排除（zero-price guard，見上方偏誤註解）
  ///    - 計算 returnRate + isSuccess（via [_isSuccessFor]）
  ///    - 累加至 `(ruleId, period)` 的 accumulator
  /// 6. Transaction: 清空舊 `rule_accuracy` 行 → 寫入新統計
  ///
  /// ## Empty guard（2026-04 Stage 2 code review followup）
  ///
  /// 早期版本無論 `daily_reason` 是否為空都先 `delete rule_accuracy` 再檢查。
  /// 問題：若 `daily_reason` 因 syncer 異常暫時空了，會把累積過的 valid 統計
  /// 一併清掉。新版本改為**先 guard 再 delete**，empty 時保留既有 stats 並 log
  /// warning 以便 ops 觀察到資料流異常。
  ///
  /// ## 已知限制
  ///
  /// - Memory footprint：price lookup map 為 `O(symbols × window-of-dates)`。
  ///   window 由 reasons 的 entry-date 範圍 + 最長 holdingPeriod 決定，比早期版本
  ///   的全表掃緊得多。post-launch 累積數年資料時仍應再評估 chunked aggregation。
  /// - 嚴格 date match（無 ±1 日容忍）：trading calendar 精確計算，不需 legacy mitigation。
  Future<void> _computeUnbiasedRuleStats() async {
    // 只取「成立訊號」(任一 horizon ≥ minScoreThreshold) 的 (symbol, date)：
    // daily_reason 持久化門檻已降到 observationScoreThreshold（8）供掃描頁觀察區，
    // 但校準須維持只學成立訊號，過濾掉觀察層（8–11）的 reason，使樣本與門檻調整前一致。
    final signalRows =
        await (_db.select(_db.dailyAnalysis)..where(
              (t) =>
                  t.scoreShort.isBiggerOrEqualValue(
                    RuleParams.minScoreThreshold.toDouble(),
                  ) |
                  t.scoreLong.isBiggerOrEqualValue(
                    RuleParams.minScoreThreshold.toDouble(),
                  ),
            ))
            .get();
    final signalKeys = <String>{
      for (final a in signalRows)
        '${a.symbol}|${DateContext.normalize(a.date).millisecondsSinceEpoch}',
    };
    final reasons = (await _db.select(_db.dailyReason).get())
        .where(
          (r) => signalKeys.contains(
            '${r.symbol}|${DateContext.normalize(r.date).millisecondsSinceEpoch}',
          ),
        )
        .toList();

    // Empty guard: 若沒資料就不動 rule_accuracy，保留既有 valid stats
    if (reasons.isEmpty) {
      AppLogger.warning(
        _tag,
        '_computeUnbiasedRuleStats: daily_reason 為空，保留既有 rule_accuracy '
        '（可能原因：syncer 異常、scoring pipeline 未跑、或 DB 被手動清掉）',
      );
      return;
    }

    // === 在 transaction 之外做讀取與聚合（H3 + M2）===
    //
    // 早期版本把整個 read + accumulate loop 包進 `_db.transaction()` 內，會把
    // 寫鎖時間從毫秒級拉長到秒級，前景 reader 跑大型 query 期間會被 SQLITE_BUSY；
    // 同時 price 查詢無日期下界，會把 daily_price 全表（2000 symbols × N years）
    // 整個拉進 in-memory map，一年後就 OOM。
    //
    // 改寫策略：
    // 1. 從 reasons 算出實際需要的 [minEntryDate, maxExitDate] window
    // 2. 用 date bound 過濾 daily_price — 只撈這次計算實際會用到的行
    // 3. priceMap + ruleStats 都在 transaction 外完成
    // 4. transaction 只做 delete + batch insert（純寫入，秒級內結束）

    final normalizedEntryDates = reasons
        .map((r) => DateContext.normalize(r.date))
        .toList();
    var minEntry = normalizedEntryDates.first;
    var maxEntry = normalizedEntryDates.first;
    for (final d in normalizedEntryDates) {
      if (d.isBefore(minEntry)) minEntry = d;
      if (d.isAfter(maxEntry)) maxEntry = d;
    }
    // holdingPeriods 已知 const sorted ascending；最後一個是最長 holding window，
    // exit-date 邊界由它決定。若未來改成非排序則需 reduce(max)。
    final maxHoldingPeriod = holdingPeriods.last;
    // SQL 比較走 epoch seconds。daily_price.date 在不同 syncer / 測試 fixture
    // 之間可能來自 `DateTime.utc(...)`（UTC 午夜）或 local `DateTime(...)`
    // （Taipei 午夜），兩者在 epoch 上相差約 8h；`DateContext.normalize`
    // 固定回 local 午夜，與 stored UTC 午夜的邊界 row 直接比較會差 8h 而被
    // 誤排除。上下界各加 1 天 buffer 兜底（cover 任意 TZ ±14h 偏移）。
    // in-memory accumulator 仍走 exact-date lookup，buffer 只是多撈幾行，
    // 不會引入錯誤命中。
    const tzBuffer = Duration(days: 1);
    final queryLowerBound = minEntry.subtract(tzBuffer);
    final queryUpperBound = DateContext.normalize(
      TaiwanCalendar.addTradingDays(maxEntry, maxHoldingPeriod),
    ).add(tzBuffer);

    final allSymbols = reasons.map((r) => r.symbol).toSet().toList();
    final priceRows =
        await (_db.select(_db.dailyPrice)..where(
              (t) =>
                  t.symbol.isIn(allSymbols) &
                  t.date.isBiggerOrEqualValue(queryLowerBound) &
                  t.date.isSmallerOrEqualValue(queryUpperBound),
            ))
            .get();

    // Survivorship bias fix（audit finding #7a）：symbol 最新價格早於 dataset
    // 自身 max date 超過 [CalibrationThresholds.stalePriceThresholdDays]（下市
    // / 長停）→ 整個 symbol 從統計排除，而非只排除算不出 exit return 的尾端
    // reason（詳見常數 docstring：只排除尾端會把「贏家全留、崩盤前夕靜默
    // 消失」的存活者偏差樣式留在統計裡）。兩個查詢都是全表 unbounded（latest
    // price 可能落在上面的 bounded window 之外），與 priceRows 的窗查詢無關。
    final datasetMaxDate = await _db.getLatestDataDate();
    final staleSymbols = <String>{};
    if (datasetMaxDate != null) {
      final latestPrices = await _db.getLatestPricesBatch(allSymbols);
      final staleCutoff = datasetMaxDate.subtract(
        const Duration(days: CalibrationThresholds.stalePriceThresholdDays),
      );
      for (final symbol in allSymbols) {
        final latest = latestPrices[symbol]?.date;
        if (latest == null || latest.isBefore(staleCutoff)) {
          staleSymbols.add(symbol);
        }
      }
    }

    // 建 price lookup：{symbol: {normalized_date: (open, close)}}
    //
    // 同時保留 open（entry 用，見下方 lookahead bias fix）與 close（exit 用）。
    final priceMap = <String, Map<DateTime, ({double? open, double? close})>>{};
    for (final p in priceRows) {
      if (p.open == null && p.close == null) continue;
      final normalized = DateContext.normalize(p.date);
      priceMap.putIfAbsent(p.symbol, () => {})[normalized] = (
        open: p.open,
        close: p.close,
      );
    }

    // 累加 per-(ruleId, period) 統計
    //
    // ## Known biases（calibration 訓練資料的方法論注意事項）
    //
    // **(1) Lookahead bias（已修復，audit finding #6，2026-07-18）**：entry
    // 原本用訊號當日 close（規則觸發賴以判斷的輸入之一），但真實使用者只能
    // T+1 open 進場。現改用訊號隔日 open（缺值 fallback 當日 close；隔日
    // 完全無資料視為未成熟樣本排除，不得退回同日 close 頂替）。exit date
    // 仍錨定「訊號日 + period 個交易日」不變，只換算報酬用的 entry 價格
    // （見下方迴圈）。Audit 實測（live DB 2025-07~2026-07，n=518K）
    // close→next-open 平均漂移 +0.28pp，約為 5D 命中門檻 19%，此修法後已消除。
    // 舊 docstring 曾聲稱此修法「需 daily_price 加 open 欄位（成本大）」——
    // 該 blocker 不成立：open 欄位早已存在且 99% 已填值，audit 已證實。
    //
    // **(2) Survivorship bias（已修復，audit finding #7a，2026-07-18）**：
    // 舊行為只在 missing exit close 時靜默 continue（單一 reason × period
    // 粒度），只排除「剛好落在下市點附近」的訊號，卻留下該股下市前仍算得出
    // 的（較早、較正常）訊號——winner 全留、崩盤前夕靜默消失。現在改用
    // staleSymbols 整股排除：symbol 最新價格早於 dataset max date 超過
    // [CalibrationThresholds.stalePriceThresholdDays]（下市 / 長停）即整股
    // 排除。下方 `_BiasCounters` 累計 skippedStaleSymbol（整股排除）與
    // skippedNoExitPrice（仍保留——正常股「訊號太新、還沒到出場日」的
    // immature case）分開揭露，兩者語意不同不應混為一談。
    //
    // **⚠️ 整股排除本身也是一種 survivorship**：判定用的是全域最新價
    // （`getLatestPricesBatch`），而非訊號當下可知的資訊。訊號發生時無從
    // 得知該股三個月後會下市，卻據此把它整批剔除——統計因此活在一個
    // 「事後確認活到今天」的宇宙裡，對專打弱勢股的規則（52 週新低、
    // RSI 極度超賣、PBR 低估等價值陷阱高發區）影響最大，因為它們真正的
    // 風險就是被剔掉的那條尾巴。
    //
    // 目前接受此限制，不改成「以最後有效收盤價入帳」：下市前多為連續跌停
    // 無量，該價格不是可成交價；而「固定懲罰值」是憑空數字，用假數字取代
    // 有偏誤的統計並不更誠實。且以現況資料（daily_reason 僅 8 天）下市需
    // 數月，實際排除量為零。
    //
    // 正確的處置方向是**揭露而非修正**——把 skippedStaleSymbol 佔比呈現到
    // 規則命中率 UI（目前只寫 AppLogger）。待 daily_reason 累積至有意義的
    // 深度後再做。
    //
    // **(3) Co-occurrence inflation**：同 (symbol, date) 多條規則同時觸發
    // 時，**同一個** forward return 被計入每條規則 → Calibrator 的
    // hit_rate × avg_return × √n 三項全被膨脹。`coOccurrenceEvents`
    // 累計多條同時觸發的事件數，metadata `co_occurrence_index =
    // total_reasons / unique_(symbol,date)` 揭露 entanglement 程度。
    final ruleStats = <String, Map<int, _StatsAccumulator>>{};
    final biasCounters = _BiasCounters();

    // 為 co-occurrence index 計算所需：去重 (symbol, date) 與總 reason 數
    final uniqueEntries = <String>{};
    for (final reason in reasons) {
      final entryDate = DateContext.normalize(reason.date);
      uniqueEntries.add('${reason.symbol}@${entryDate.toIso8601String()}');
    }
    biasCounters.totalReasons = reasons.length;
    biasCounters.uniqueEntries = uniqueEntries.length;

    for (final reason in reasons) {
      if (staleSymbols.contains(reason.symbol)) {
        biasCounters.skippedStaleSymbol++;
        continue;
      }

      final symbolPrices = priceMap[reason.symbol];
      if (symbolPrices == null) {
        biasCounters.skippedNoSymbolPrices++;
        continue;
      }

      final entryDate = DateContext.normalize(reason.date);

      // Lookahead bias fix（audit finding #6，2026-07-18）：entry 用訊號隔日
      // open（缺值 fallback 當日 close），不可用訊號當日 close —— 那是規則
      // 賴以觸發的輸入之一，真實使用者只能隔日進場。隔日完全無資料（尚未
      // 發生，或當日停牌）→ 視為未成熟樣本排除，不得退回同日 close 頂替。
      final nextTradingDate = DateContext.normalize(
        TaiwanCalendar.addTradingDays(entryDate, 1),
      );
      // review finding（2026-07-18，sibling of audit finding #6）：`open ??
      // close` 只在 open 為 **null** 時才 fallback；FinMind 部分價格列
      // open=0.0（非 null，calibration.db 實測 19,030 筆 / 0.61%，其中 358
      // 筆 close>0）。舊 guard 只查 `== null`，讓 entry=0 通過，下方
      // `(exitClose-entryPrice)/entryPrice` 除以零得 +Infinity，
      // `Infinity >= threshold` 恆真 → false hit，把整個 (rule, period) 的
      // avgReturn 污染成 +Infinity/NaN。`<= 0` 與 `tool/replay_calibrator.dart`
      // 的 entry guard 對齊。
      final entryPrice =
          symbolPrices[nextTradingDate]?.open ??
          symbolPrices[nextTradingDate]?.close;
      if (entryPrice == null || entryPrice <= 0) {
        biasCounters.skippedNoEntryPrice++;
        continue;
      }

      for (final period in holdingPeriods) {
        final exitDate = DateContext.normalize(
          TaiwanCalendar.addTradingDays(entryDate, period),
        );
        // 同型 bug，exit 端：close=0.0（停牌/異常列）舊 guard 只查
        // `== null`，會被當成合法出場價算出 -100% 的假最大虧損。
        final exitClose = symbolPrices[exitDate]?.close;
        if (exitClose == null || exitClose <= 0) {
          biasCounters.skippedNoExitPrice++;
          continue;
        }

        final returnRate = ((exitClose - entryPrice) / entryPrice) * 100;
        final isSuccess = _isSuccessFor(returnRate, period);

        ruleStats
            .putIfAbsent(reason.reasonType, () => <int, _StatsAccumulator>{})
            .putIfAbsent(period, _StatsAccumulator.new)
            .add(returnRate, isSuccess, entryDate);
      }
    }

    // 一次性 log bias counter 供 reviewer 與 ELK / debug 頁面消費。
    // Survivorship inflated hit_rate 的程度可用 skippedStaleSymbol 比例反推；
    // co_occurrence_index > 1 意味同事件多 rule entanglement，calibration
    // 報告應降權看待單一規則的 hit_rate。
    final coOccurrenceIndex = uniqueEntries.isEmpty
        ? 0.0
        : reasons.length / uniqueEntries.length;
    AppLogger.info(
      'RuleAccuracy',
      'bias_telemetry total_reasons=${biasCounters.totalReasons} '
          'unique_(symbol,date)=${biasCounters.uniqueEntries} '
          'co_occurrence_index=${coOccurrenceIndex.toStringAsFixed(2)} '
          'skipped_stale_symbol=${biasCounters.skippedStaleSymbol} '
          'skipped_no_symbol_prices=${biasCounters.skippedNoSymbolPrices} '
          'skipped_no_entry_price=${biasCounters.skippedNoEntryPrice} '
          'skipped_no_exit_price=${biasCounters.skippedNoExitPrice}',
    );

    // === Transaction：只做 delete + per-row upsert ===
    //
    // 寫入仍走 `insertOnConflictUpdate` loop（如原本 Stage 2 寫法）— drift 的
    // `_db.batch` 嵌進 `_db.transaction` 後行為不對等（Batch 自己會嘗試開
    // transaction），會吞掉新行；改用 loop await 維持原語意。資料量小
    // （~64 rules × ≤6 periods ≈ 數百 rows），lock 時間在毫秒級。
    await _db.transaction(() async {
      await _db.delete(_db.ruleAccuracy).go();
      for (final ruleEntry in ruleStats.entries) {
        final ruleId = ruleEntry.key;
        for (final periodEntry in ruleEntry.value.entries) {
          final period = periodEntry.key;
          final acc = periodEntry.value;
          await _db
              .into(_db.ruleAccuracy)
              .insertOnConflictUpdate(
                RuleAccuracyCompanion.insert(
                  ruleId: ruleId,
                  period: '${period}D',
                  triggerCount: Value(acc.count),
                  successCount: Value(acc.successCount),
                  avgReturn: Value(acc.avgReturnPct),
                  distinctDates: Value(acc.distinctDates),
                ),
              );
        }
      }
    });

    // 'ALL' period 已於 2026-04 移除：跨 holdingPeriods 合併會把 1D（門檻
    // 0%）與 60D（門檻 8%）的 success_count 加總後除以總 trigger_count，
    // 得到一個沒有可解釋意義的 hit_rate（被低門檻樣本拉高）。dual-horizon
    // UI 已 ship，使用者直接查 5D / 60D 兩個 horizon 的命中率即可。
    AppLogger.info(
      _tag,
      '_computeUnbiasedRuleStats: ${ruleStats.length} rules × '
      '${holdingPeriods.length} periods 聚合自 ${reasons.length} reasons '
      '(price window: ${_formatDate(queryLowerBound)}~${_formatDate(queryUpperBound)})',
    );
  }

  /// 取得規則命中率
  ///
  /// [period] 持有天數週期，如 '5D'、'60D'（預設 '5D' — 對齊 short horizon 預設）。
  /// 'ALL' 已於 2026-04 移除（混 threshold 算 hit_rate 數學上沒意義）。
  Future<RuleStats?> getRuleStats(String ruleId, {String? period}) async {
    final result =
        await (_db.select(_db.ruleAccuracy)..where(
              (t) => t.ruleId.equals(ruleId) & t.period.equals(period ?? '5D'),
            ))
            .getSingleOrNull();

    if (result == null) return null;

    final hitRate = result.triggerCount > 0
        ? (result.successCount / result.triggerCount) * 100
        : 0.0;

    return RuleStats(
      ruleId: result.ruleId,
      hitRate: hitRate,
      avgReturn: result.avgReturn,
      triggerCount: result.triggerCount,
      distinctDates: result.distinctDates,
    );
  }

  /// 取得規則摘要文字（用於 UI 顯示）
  ///
  /// 樣本基礎一律隨附，例如
  /// 「命中率 65%，平均 5 日報酬 +2.3%（樣本 35 筆 / 40 個觸發日）」。
  ///
  /// 低信心註記在**兩個條件擇一**成立時附加於括號**之後**：
  /// `distinctDates < ` [CalibrationThresholds.minDistinctDates]（觸發日太少
  /// → clustered 觀察數不足）或 `triggerCount < `
  /// [CalibrationThresholds.sampleSizeCutThreshold]（與 calibration cut 共用
  /// 同一門檻）——例如「命中率 70%，平均 5 日報酬 +2.3%
  /// （樣本 10 筆 / 3 個觸發日），信心度較低」。
  ///
  /// 觸發日條件由 f8de299（2026-07-26）加入，該 commit 的 docstring 未同步；
  /// 以現有資料深度所有規則都會落在低信心側，這是預期結果（8 天不足以評估
  /// 命中率），distinct_dates 上限 = 資料深度 − 持有窗，會隨天數單調成長。
  ///
  /// **為什麼需要（audit finding #7b）**：這是 `rule_accuracy` 唯一的 UI
  /// 消費端——bias telemetry（co-occurrence inflation 等）只寫 AppLogger.info
  /// log，使用者永遠看不到。樣本數越小，被少數幾個 co-occurrence 共現事件
  /// 主導、hit_rate 被膨脹的風險越高；此處無法反推「這條規則本身」的
  /// co-occurrence 程度（telemetry 是聚合值，非 per-rule），但樣本數本身
  /// 是可得、便宜、方向正確的 proxy：n 越小，任何未修正的偏誤（含
  /// co-occurrence）對這個數字的影響占比越大。
  Future<String?> getRuleSummaryText(
    String ruleId, {
    int holdingDays = defaultHoldingDays,
  }) async {
    final stats = await getRuleStats(ruleId, period: '${holdingDays}D');
    if (stats == null || stats.triggerCount < 5) return null;

    // **不顯示隨機基準比較**（2026-07-26 移除 P1-9 加入的 lift）。
    //
    // 曾以 `CalibrationThresholds.successProbabilityBaselines`（5D=0.3461）
    // 當基準顯示 lift。實測後發現該比較兩端來自完全不同的市場環境：
    // - 基準是 2026-06-18 在**另一個 dev DB** 上對全期算的靜態值；
    //   本機全期實測其實是 29.23%，並非 34.61%
    // - 而 hit_rate 來自 `daily_reason`，僅 8 天；5D 前瞻只有最早三天的
    //   觸發有結果，那三天之後緊接 2026-07-17 全市場單日 −3.95% 的崩盤
    // - 該窗實測基準是 **19.04%**。逐日基準全期範圍 5.79%~66.20%、
    //   標準差 13.06pp —— 靜態基準在這種變異下沒有意義
    //
    // 後果是方向性的：以靜態基準計，14 條有樣本的規則中 13 條顯示為負；
    // 以同窗基準計，11 條為正，**10 條正負號翻轉**。顯示一個方向相反的
    // 比較，比不顯示更糟。
    //
    // 要正確做需要與量測窗同期的實測 baseline（`tool/replay_calibrator.dart`
    // 的超額模式已有正解，資產 `assets/rule_scores_calibrated_short.json`
    // 也已帶 `backtest.baseline_hit_rate`），但那只涵蓋 44 條規則中的 41 條，
    // 且 `daily_reason` 僅 8 天時任何基準設計都算不出可信數字。待資料深度
    // 足夠（≥ `minDistinctDates` 個觸發日）再回頭處理。
    //
    // 兩個常數本身**不得刪**：`tool/recalibrate.dart` 的 `_processHorizon`
    // 在 absolute 路徑仍以它們為 H0。
    final hitRateStr = stats.hitRate.roundToDouble().toStringAsFixed(0);
    final returnStr = AppNumberFormat.signedPercent(
      stats.avgReturn,
      decimals: 1,
    );
    // 樣本一律標示「筆數 / 觸發日數」。有效樣本量級是觸發日數而非 pooled
    // 筆數 —— 同日觸發的數十檔幾乎共用同一個市場因子（實測 2026-07-17
    // 全市場單日 −3.95%），加上持有窗重疊，pooled 筆數是偽重複。
    // 此認知早已寫在 CalibrationThresholds.minDistinctDates 的註解裡，
    // 但只落實於 calibration 決策層的 clustered t-stat，顯示層仍以 pooled
    // 筆數判斷信心度：實測 CONCENTRATION_HIGH 761 筆全來自 8 個交易日，
    // 遠超門檻 30 卻以「完全有信心」的樣子呈現。
    final summary =
        '命中率 $hitRateStr%，平均 $holdingDays 日報酬 $returnStr'
        '（樣本 ${stats.triggerCount} 筆 / ${stats.distinctDates} 個觸發日）';

    if (stats.distinctDates < CalibrationThresholds.minDistinctDates ||
        stats.triggerCount < CalibrationThresholds.sampleSizeCutThreshold) {
      return '$summary，信心度較低';
    }

    return summary;
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }
}

/// 規則統計
class RuleStats {
  const RuleStats({
    required this.ruleId,
    required this.hitRate,
    required this.avgReturn,
    required this.triggerCount,
    this.distinctDates = 0,
  });

  final String ruleId;
  final double hitRate;
  final double avgReturn;

  /// pooled 觸發筆數 —— **不是**有效樣本量級，見 [distinctDates]
  final int triggerCount;

  /// 觸發「日」數：有效樣本量級（同日橫斷面相關 + 持有窗重疊使 pooled
  /// 筆數成為偽重複，見 CalibrationThresholds.minDistinctDates）
  final int distinctDates;
}

/// Per-(ruleId, period) 統計累加器
///
/// 用於 [RuleAccuracyService._computeUnbiasedRuleStats] 的 in-memory 聚合階段。
/// [add] 單筆 (returnRate, isSuccess) 累加。
class _StatsAccumulator {
  int count = 0;
  int successCount = 0;
  double _sumReturn = 0.0;

  /// 觸發日集合 —— 有效樣本量級。同日觸發的數十檔幾乎共用同一個市場
  /// 因子，pooled [count] 是偽重複（見 CalibrationThresholds.minDistinctDates）。
  final Set<DateTime> _dates = <DateTime>{};

  void add(double returnRate, bool success, DateTime entryDate) {
    count++;
    if (success) successCount++;
    _sumReturn += returnRate;
    _dates.add(entryDate);
  }

  int get distinctDates => _dates.length;

  double get avgReturnPct => count > 0 ? _sumReturn / count : 0.0;
}

/// Calibration bias telemetry — 累計 [RuleAccuracyService] 的 sampling
/// drop / co-occurrence 指標，供 reviewer 判斷 calibrated 結果的可信度。
///
/// 不影響 calibration 計算本身，純粹是 transparency layer：把以前 silently
/// `continue` 的 sample 漏失與多 rule 共現膨脹數值化出來，避免 hit_rate
/// 被解讀為「真實命中率」時忽略樣本選擇偏誤。
class _BiasCounters {
  /// 樣本來源規則總數（含 co-occurring）
  int totalReasons = 0;

  /// 去重後 (symbol, date) 數量
  ///
  /// `totalReasons / uniqueEntries = co_occurrence_index`，> 1 意味
  /// 同事件多規則 entanglement，per-rule hit_rate 會 share 同一 return。
  int uniqueEntries = 0;

  /// symbol 最新價格早於 dataset max date 超過
  /// [CalibrationThresholds.stalePriceThresholdDays] 而整股排除的 reason 數
  /// （survivorship bias fix，audit finding #7a——下市 / 長停股，不只排除
  /// 尾端算不出 exit 的訊號，整股排除避免留下「贏家全留」的偏誤樣本）
  int skippedStaleSymbol = 0;

  /// symbol 在 priceMap 中完全缺資料的 reason 數（多為極早期 / 下市股）
  int skippedNoSymbolPrices = 0;

  /// 訊號隔日缺 open/close 資料、**或資料為 0/負值**的 reason 數（多為尚未
  /// 成熟的最新訊號、隔日停牌，或 FinMind 異常列 open=0.0）。Lookahead bias
  /// fix（audit finding #6）後 entry 改用隔日資料，此計數器涵蓋「算不出
  /// 隔日進場價」的所有情況——不得退回同日 close 頂替。`<= 0` 分支見 review
  /// finding（2026-07-18）：`open ?? close` 不會 fallback 掉 open=0.0（非
  /// null），未擋會除以零產生 +Infinity 污染 avgReturn。
  int skippedNoEntryPrice = 0;

  /// 出場日 close 缺資料、**或為 0/負值**的 (reason × period) 數
  ///
  /// 來源包含：尚未到出場日的 immature 樣本、出場日停牌（未達 stale 門檻，
  /// 含近期才下市者）、close ≤ 0 的異常列。長期無價的股票已由 staleSymbols
  /// 整股排除（計入 skippedStaleSymbol）。`<= 0`
  /// 分支見 review finding（2026-07-18）：停牌/異常列 close=0.0 若不擋會被
  /// 算成 -100% 假最大虧損。
  int skippedNoExitPrice = 0;
}
