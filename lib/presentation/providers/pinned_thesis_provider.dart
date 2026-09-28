import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 釘選論點畫面狀態（出場層 Phase 2）
class PinnedThesisState {
  const PinnedThesisState({
    this.active = const [],
    this.invalidated = const [],
    this.currentCloses = const {},
    this.inactiveSymbols = const {},
  });

  /// ACTIVE 釘選（今日頁追蹤區）
  final List<PinnedThesisEntry> active;

  /// INVALIDATED（追蹤區紅標 + 警示頁 section）
  final List<PinnedThesisEntry> invalidated;

  /// symbol → 最新收盤（追蹤卡「參考價 vs 現價」；來源 daily_price，spec §6）
  final Map<String, double?> currentCloses;

  /// 已下市/停用（stock_master.isActive = false）的 symbol —— 追蹤卡
  /// 顯示「已下市，價格未更新」警示（spec §6）
  final Set<String> inactiveSymbols;

  bool isPinned(String symbol) => active.any((t) => t.symbol == symbol);
}

/// 釘選論點 Notifier
///
/// pin() 快照語意（spec §4）：pinnedDate = 該股**最新分析資料日**（非點擊
/// 時刻）、referencePrice = 該日收盤、mode 未指定時取觸發規則的 dominant
/// scoringMode、triggeredRules/scores 快照當日 daily_reason / daily_analysis。
class PinnedThesisNotifier extends AsyncNotifier<PinnedThesisState> {
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  Future<PinnedThesisState> build() {
    // 更新完成（monitor 可能剛標失效）→ epoch bump → 自動重載
    ref.watch(dataUpdateEpochProvider);
    return _load();
  }

  Future<PinnedThesisState> _load() async {
    final active = await _db.getActiveTheses();
    final invalidated = await _db.getThesesByStatus('INVALIDATED');
    final symbols = {
      for (final t in active) t.symbol,
      for (final t in invalidated) t.symbol,
    }.toList();

    var closes = <String, double?>{};
    var inactive = <String>{};
    if (symbols.isNotEmpty) {
      final latest = await _db.getLatestPricesBatch(symbols);
      closes = {for (final s in symbols) s: latest[s]?.close};
      final stocks = await _db.getStocksBatch(symbols);
      inactive = {
        for (final s in symbols)
          if (stocks[s] != null && !stocks[s]!.isActive) s,
      };
    }

    return PinnedThesisState(
      active: active,
      invalidated: invalidated,
      currentCloses: closes,
      inactiveSymbols: inactive,
    );
  }

  Future<void> _reload() async {
    state = AsyncData(await _load());
  }

  /// 釘選論點。[mode] 由今日頁 tab 傳入；未指定（個股詳情入口）時取
  /// 當日觸發規則的 dominant scoringMode。
  ///
  /// 同 symbol 已有 ACTIVE → 拋 [StateError]（UI 應以已釘選狀態擋住，
  /// DAO 層兜底）。無分析資料的股票拋 [StateError]（無論點可快照）。
  Future<void> pin(String symbol, {String? mode}) async {
    // 該股最新分析資料日
    final latestAnalysis =
        await (_db.select(_db.dailyAnalysis)
              ..where((t) => t.symbol.equals(symbol))
              ..orderBy([(t) => OrderingTerm.desc(t.date)])
              ..limit(1))
            .getSingleOrNull();
    if (latestAnalysis == null) {
      throw StateError('$symbol 無分析資料，無論點可釘選');
    }
    final dataDate = latestAnalysis.date;

    final prices = await _db.getLatestPricesBatch([symbol]);
    final close = prices[symbol]?.close;
    if (close == null) {
      throw StateError('$symbol 無收盤價，無法設定參考價');
    }

    final reasons = await _db.getReasons(symbol, dataDate);
    final codes = [for (final r in reasons) r.reasonType];

    await _db.pinThesis(
      symbol: symbol,
      pinnedDate: dataDate,
      referencePrice: close,
      mode: mode ?? _dominantMode(reasons),
      triggeredRules: jsonEncode(codes),
      scoreShort: latestAnalysis.scoreShort,
      scoreLong: latestAnalysis.scoreLong,
    );
    AppLogger.info('PinnedThesis', '釘選 $symbol（資料日 $dataDate、參考價 $close）');
    await _reload();
  }

  /// 取消 ACTIVE 釘選（誤觸/改變心意）= 物理刪除
  Future<void> cancel(int id) async {
    await _db.deletePinnedThesis(id);
    await _reload();
  }

  /// 封存 INVALIDATED（離開警示頁、保留紀錄）
  Future<void> archive(int id) async {
    await _db.archiveThesis(id);
    await _reload();
  }

  /// 手動重載入口（目前畫面不呼叫；更新後的自動重載走 dataUpdateEpoch）
  Future<void> refresh() => _reload();

  /// 封存紀錄（歷史複盤 sheet 用；on-demand、不進常駐 state）
  Future<List<PinnedThesisEntry>> archivedTheses() =>
      _db.getThesesByStatus('ARCHIVED');

  /// 觸發規則的 dominant scoringMode → mode 字串。
  /// 以 max(short, long) 分數加總比較；全 neutral 時 fallback 'strength'
  /// （最泛用的觀察語意）。
  static String _dominantMode(List<DailyReasonEntry> reasons) {
    final byCode = {for (final t in ReasonType.values) t.code: t};
    final sums = <ScoringMode, double>{};
    for (final r in reasons) {
      final type = byCode[r.reasonType];
      if (type == null) continue;
      final score = r.ruleScoreShort > r.ruleScoreLong
          ? r.ruleScoreShort
          : r.ruleScoreLong;
      if (score <= 0) continue;
      sums[type.scoringMode] = (sums[type.scoringMode] ?? 0) + score;
    }
    ScoringMode? best;
    var bestSum = 0.0;
    for (final entry in sums.entries) {
      if (entry.key == ScoringMode.neutral) continue;
      if (entry.value > bestSum) {
        best = entry.key;
        bestSum = entry.value;
      }
    }
    return switch (best) {
      ScoringMode.momentumEntry => 'momentum',
      ScoringMode.weaknessObserve => 'pullback',
      ScoringMode.strengthObserve || null || ScoringMode.neutral => 'strength',
    };
  }
}

final pinnedThesisProvider =
    AsyncNotifierProvider<PinnedThesisNotifier, PinnedThesisState>(
      PinnedThesisNotifier.new,
    );
