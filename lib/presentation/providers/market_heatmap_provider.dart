import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/dao/heatmap_dao.dart';
import 'package:daredevil/data/repositories/heatmap_repository.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_grouping.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

final heatmapRepositoryProvider = Provider<HeatmapRepository>(
  (ref) => HeatmapRepository(ref.watch(databaseProvider)),
);

/// 大盤熱力圖頁的狀態
@immutable
class MarketHeatmapState {
  const MarketHeatmapState({
    this.isLoading = true,
    this.error,
    this.markets = const {},
    this.failedMarkets = const {},
  });

  /// 第一次讀取還沒完成
  final bool isLoading;

  /// 某一輪兩個市場都讀取失敗、而且沒有任何市場資料時的錯誤；之後任一
  /// 市場讀取成功就清掉
  final Object? error;

  /// 市場別 → 熱力圖資料；沒有正式資料的市場不在這裡
  final Map<String, HeatmapMarketData> markets;

  /// 上一次讀取失敗的市場（畫面保留舊資料；下一次成功讀到該市場時移除）
  final Set<String> failedMarkets;
}

final marketHeatmapProvider =
    NotifierProvider.autoDispose<MarketHeatmapNotifier, MarketHeatmapState>(
      MarketHeatmapNotifier.new,
    );

/// 讀資料庫、算熱力圖，並在資料可能變動時重讀：
///
/// - 開頁、盤後資料寫入的通知（`dataUpdateEpochProvider`）、跨午夜／開盤／
///   收盤（`liveQuoteBoundaryProvider`）都重讀。
/// - 頁面可見期間每分鐘比對內容指紋：launchd 在背景寫入時沒有通知，很多
///   寫入也不改日期，只能比內容。同時比對自選∪持股：從熱力圖點進個股頁加入
///   自選後返回，回到可見時的立即比對就會重讀，雙線框跟著出現。
/// - 重讀進行中又有觸發，結束後恰好再讀一次。
class MarketHeatmapNotifier extends Notifier<MarketHeatmapState> {
  static const _tag = 'MarketHeatmap';
  static const _allMarkets = [MarketCode.twse, MarketCode.tpex];

  /// 上一次成功讀取時、讀資料「前」取得的指紋（寫入夾在兩者之間時，下一次
  /// 比對會發現不同而再讀一次）
  final _baseline = <String, HeatmapFingerprint?>{};

  /// 上一次成功讀取時、讀資料「前」取得的自選∪持股（同上，夾在中間的變動
  /// 下一次比對會發現）；沒有正式資料的市場不記
  final _mineBaseline = <String, Set<String>>{};
  bool _active = true;
  bool _inFlight = false;
  bool _pending = false;
  bool _visible = false;
  bool _loadedOnce = false;
  bool _checkFailing = false;
  Timer? _timer;

  @override
  MarketHeatmapState build() {
    _active = true;
    ref.listen(dataUpdateEpochProvider, (_, _) => unawaited(reload()));
    ref.listen(liveQuoteBoundaryProvider, (_, _) => unawaited(reload()));
    ref.onDispose(() {
      _active = false;
      _timer?.cancel();
      _timer = null;
    });
    // 重建（invalidate）時沿用同一個實例：畫面仍可見就把計時器接回來
    if (_visible) _startTimer();
    unawaited(Future.microtask(reload));
    return const MarketHeatmapState();
  }

  HeatmapRepository get _repo => ref.read(heatmapRepositoryProvider);

  /// 重讀兩個市場；進行中再被呼叫只排一次，結束後再讀
  Future<void> reload() async {
    if (!_active) return;
    if (_inFlight) {
      _pending = true;
      return;
    }
    _inFlight = true;
    try {
      do {
        _pending = false;
        await _readAll();
      } while (_pending && _active);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _readAll() async {
    // 第一個 await 前先取：await 期間 dispose 後 ref.read 會拋錯
    final repo = _repo;
    final markets = Map.of(state.markets);
    final failed = Set.of(state.failedMarkets);
    Object? lastError;
    var anySuccess = false;
    for (final market in _allMarkets) {
      try {
        final read = Stopwatch()..start();
        final fp = await repo.fingerprint(market);
        if (fp == null) {
          markets.remove(market);
          _baseline[market] = null;
          _mineBaseline.remove(market);
        } else {
          final mine = await repo.mineSymbols();
          final input = await repo.loadInput(market, fp.date);
          read.stop();
          final compute = Stopwatch()..start();
          markets[market] = buildHeatmapMarket(input);
          compute.stop();
          _baseline[market] = fp;
          _mineBaseline[market] = mine;
          AppLogger.debug(
            _tag,
            '$market 讀取 ${read.elapsedMilliseconds}ms、'
            '計算 ${compute.elapsedMilliseconds}ms',
          );
        }
        failed.remove(market);
        anySuccess = true;
      } catch (e) {
        if (!_active) return;
        lastError = e;
        // 持續失敗不重複記：只在由成功（或從沒讀過）轉為失敗時記
        if (failed.add(market)) {
          AppLogger.warning(_tag, '$market 熱力圖讀取失敗', e);
        }
      }
      if (!_active) return;
    }
    _loadedOnce = true;
    state = MarketHeatmapState(
      isLoading: false,
      error: !anySuccess && markets.isEmpty ? lastError : null,
      markets: Map.unmodifiable(markets),
      failedMarkets: Set.unmodifiable(failed),
    );
  }

  /// 比對兩個市場的內容指紋與自選∪持股；有任一不同、或有讀取失敗待重試時
  /// 重讀。reload 進行中時不比對，直接排一次重讀。
  ///
  /// 會在畫面的 `didChangeDependencies` 被呼叫：不得同步寫 `state`。
  Future<void> checkFingerprint() async {
    if (!_active) return;
    if (_inFlight) {
      _pending = true;
      return;
    }
    final repo = _repo;
    try {
      var differs = state.failedMarkets.isNotEmpty;
      for (final market in _allMarkets) {
        final fp = await repo.fingerprint(market);
        if (fp != _baseline[market]) differs = true;
      }
      if (_mineBaseline.isNotEmpty) {
        final mine = await repo.mineSymbols();
        if (_mineBaseline.values.any((m) => !setEquals(m, mine))) {
          differs = true;
        }
      }
      _checkFailing = false;
      if (differs && _active) await reload();
    } catch (e) {
      if (!_active) return;
      if (!_checkFailing) {
        AppLogger.warning(_tag, '熱力圖比對失敗（指紋或自選），保留畫面', e);
      }
      _checkFailing = true;
    }
  }

  /// 頁面可見（`TickerMode` 開著且 App 在前景）才每分鐘比對指紋；回到可見
  /// 時立即比對一次（第一次讀取還沒完成時不比對，免得同一份資料讀兩次）。
  ///
  /// 會在畫面的 `didChangeDependencies`／`dispose` 被呼叫：不同步寫 `state`。
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _timer?.cancel();
    _timer = null;
    if (!visible || !_active) return;
    _startTimer();
    if (_loadedOnce) unawaited(checkFingerprint());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      HeatmapParams.fingerprintPollInterval,
      (_) => unawaited(checkFingerprint()),
    );
  }
}
