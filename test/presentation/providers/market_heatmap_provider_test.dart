import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/dao/heatmap_dao.dart';
import 'package:daredevil/data/repositories/heatmap_repository.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';

class MockHeatmapRepository extends Mock implements HeatmapRepository {}

/// 可手動換值的邊界（真的那個會掛計時器等開盤、收盤、午夜）
class _FakeBoundary extends LiveQuoteBoundary {
  @override
  DateTime build() => DateTime(2026, 10, 7, 9);

  void set(DateTime t) => state = t;
}

const _twse = MarketCode.twse;
const _tpex = MarketCode.tpex;
final _d1007 = DateTime(2026, 10, 7);
final _d1008 = DateTime(2026, 10, 8);

HeatmapFingerprint _fp(DateTime date, {double closeSum = 100}) =>
    (date: date, rows: 2, changeRows: 2, changeSum: 1.0, closeSum: closeSum);

HeatmapMarketInput _input(
  String market,
  DateTime date, {
  Set<String> mine = const {},
}) => HeatmapMarketInput(
  market: market,
  dataDate: date,
  stocks: [
    HeatmapStockInput(
      symbol: market == _twse ? '9901' : '9911',
      name: '測試',
      industry: '測試業',
      close: 100,
      priceChange: 1,
      foreign: (shares: 1000, date: date),
    ),
  ],
  mine: mine,
);

/// 假 repository 的狀態：每個市場的指紋、讀取是否失敗、呼叫次數
class _Repo {
  _Repo() {
    when(() => mock.fingerprint(any())).thenAnswer((inv) async {
      final market = inv.positionalArguments[0] as String;
      fingerprintCalls[market] = (fingerprintCalls[market] ?? 0) + 1;
      final hook = onFingerprint;
      if (hook != null) await hook(market);
      if (fingerprintThrows.contains(market)) throw StateError('fp $market');
      return fingerprints[market];
    });
    when(() => mock.loadInput(any(), any())).thenAnswer((inv) async {
      final market = inv.positionalArguments[0] as String;
      final date = inv.positionalArguments[1] as DateTime;
      loadCalls[market] = (loadCalls[market] ?? 0) + 1;
      loadDates.add((market, date));
      final hook = onLoad;
      if (hook != null) await hook(market);
      if (loadThrows.contains(market)) throw StateError('load $market');
      return _input(market, date, mine: Set.of(mine));
    });
    when(() => mock.mineSymbols()).thenAnswer((_) async {
      mineCalls++;
      if (mineThrows) throw StateError('mine');
      // 每次回新的集合：比對要比內容，不能比是不是同一個物件
      return Set.of(mine);
    });
  }

  final mock = MockHeatmapRepository();
  final fingerprints = <String, HeatmapFingerprint?>{
    _twse: _fp(_d1007),
    _tpex: _fp(_d1007),
  };
  final fingerprintThrows = <String>{};

  /// 自選∪持股（真的 repository 由 loadInput 一併讀、也可單獨查）
  Set<String> mine = {};
  bool mineThrows = false;
  int mineCalls = 0;
  final loadThrows = <String>{};
  final fingerprintCalls = <String, int>{};
  final loadCalls = <String, int>{};
  final loadDates = <(String, DateTime)>[];
  Future<void> Function(String market)? onLoad;
  Future<void> Function(String market)? onFingerprint;

  int loads(String market) => loadCalls[market] ?? 0;
  int fingerprintsOf(String market) => fingerprintCalls[market] ?? 0;
}

/// 建好 container、開始監聽（第一次讀取排在 microtask，還沒跑）
ProviderContainer _open(_Repo repo) {
  final container = ProviderContainer(
    overrides: [
      heatmapRepositoryProvider.overrideWithValue(repo.mock),
      liveQuoteBoundaryProvider.overrideWith(_FakeBoundary.new),
    ],
  );
  container.listen(marketHeatmapProvider, (_, _) {});
  return container;
}

/// 建好 container 並等第一次讀取完成
ProviderContainer _start(FakeAsync async, _Repo repo) {
  final container = _open(repo);
  async.flushMicrotasks();
  return container;
}

MarketHeatmapNotifier _notifier(ProviderContainer c) =>
    c.read(marketHeatmapProvider.notifier);

MarketHeatmapState _state(ProviderContainer c) => c.read(marketHeatmapProvider);

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2026)));

  late List<String> warnings;
  setUp(() {
    warnings = [];
    AppLogger.setSentryDelegates(
      breadcrumb: (message, category, level, data) {
        if (category == 'MarketHeatmap' && level == 'warning') {
          warnings.add(message);
        }
      },
    );
  });
  tearDown(() => AppLogger.setSentryDelegates());

  test('開頁讀取兩個市場；沒有正式資料的市場不在 markets', () {
    fakeAsync((async) {
      final repo = _Repo()..fingerprints[_tpex] = null;
      final c = _start(async, repo);
      final s = _state(c);
      expect(s.isLoading, isFalse);
      expect(s.error, isNull);
      expect(s.markets.keys, [_twse]);
      expect(s.markets[_twse]!.dataDate, _d1007);
      expect(repo.loads(_tpex), 0);
      c.dispose();
    });
  });

  test('epoch 變動重讀', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      expect(repo.loads(_twse), 2);
      c.dispose();
    });
  });

  test('boundary 換值重讀', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      (c.read(liveQuoteBoundaryProvider.notifier) as _FakeBoundary).set(
        DateTime(2026, 10, 7, 13, 30),
      );
      async.flushMicrotasks();
      expect(repo.loads(_twse), 2);
      c.dispose();
    });
  });

  test('可見時每分鐘比對指紋：不變不重讀', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.elapse(const Duration(minutes: 3));
      // 開頁 1 次、變可見立即 1 次、每分鐘 3 次
      expect(repo.fingerprintsOf(_twse), 5);
      expect(repo.loads(_twse), 1);
      c.dispose();
    });
  });

  test('同一日期只改內容也重讀', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      repo.fingerprints[_twse] = _fp(_d1007, closeSum: 200);
      async.elapse(const Duration(minutes: 1));
      expect(repo.loads(_twse), 2);
      c.dispose();
    });
  });

  test('最新資料日改變時重讀、並換成新日期的資料', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      repo.fingerprints[_twse] = _fp(_d1008);
      async.elapse(const Duration(minutes: 1));
      expect(repo.loadDates.last, (_tpex, _d1007));
      expect(repo.loadDates, contains((_twse, _d1008)));
      expect(_state(c).markets[_twse]!.dataDate, _d1008);
      c.dispose();
    });
  });

  test('兩個市場分開偵測：只有上櫃變也重讀，重讀後兩邊基準都更新', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      repo.fingerprints[_tpex] = _fp(_d1007, closeSum: 300);
      async.elapse(const Duration(minutes: 1));
      expect(repo.loads(_tpex), 2);
      async.elapse(const Duration(minutes: 2));
      expect(repo.loads(_tpex), 2);
      expect(repo.loads(_twse), 2);
      c.dispose();
    });
  });

  test('自選或持股變了：價格指紋沒變也重讀，格子換上新的自選標記', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      expect(repo.loads(_twse), 1);
      repo.mine = {'9901'};
      async.elapse(const Duration(minutes: 1));
      expect(repo.loads(_twse), 2);
      final tile = _state(c).markets[_twse]!.industries.single.tiles.single;
      expect(tile.isMine, isTrue);
      async.elapse(const Duration(minutes: 2));
      expect(repo.loads(_twse), 2, reason: '重讀後基準更新，不再重讀');
      c.dispose();
    });
  });

  test('自選或持股內容沒變：不重讀', () {
    fakeAsync((async) {
      final repo = _Repo()..mine = {'9901'};
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.elapse(const Duration(minutes: 3));
      expect(repo.mineCalls, greaterThan(2), reason: '前提：每次比對都查');
      expect(repo.loads(_twse), 1);
      c.dispose();
    });
  });

  test('讀資料時自選剛好變了：基準取在讀資料前，下一次比對會再重讀', () {
    fakeAsync((async) {
      final repo = _Repo();
      repo.onLoad = (market) async {
        if (market == _twse) repo.mine = {'9901'};
      };
      final c = _start(async, repo);
      repo.onLoad = null;
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      expect(repo.loads(_twse), 2);
      async.elapse(const Duration(minutes: 1));
      expect(repo.loads(_twse), 2);
      c.dispose();
    });
  });

  test('比對時自選查詢失敗：保留畫面、只記一次 warning，恢復後照常比對', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final before = _state(c);
      repo.mineThrows = true;
      _notifier(c).setVisible(true);
      async.elapse(const Duration(minutes: 2));
      expect(_state(c).markets, before.markets);
      expect(repo.loads(_twse), 1);
      expect(warnings.where((w) => w.contains('熱力圖比對失敗')), hasLength(1));
      repo.mineThrows = false;
      repo.mine = {'9901'};
      async.elapse(const Duration(minutes: 1));
      expect(repo.loads(_twse), 2);
      c.dispose();
    });
  });

  test('不可見時不輪詢、回到可見立即比對', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final n = _notifier(c);
      n.setVisible(true);
      async.flushMicrotasks();
      n.setVisible(false);
      final before = repo.fingerprintsOf(_twse);
      async.elapse(const Duration(minutes: 5));
      expect(repo.fingerprintsOf(_twse), before);
      n.setVisible(true);
      async.flushMicrotasks();
      expect(repo.fingerprintsOf(_twse), before + 1);
      c.dispose();
    });
  });

  test('重讀中又觸發兩次，結束後恰好再讀一次', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final gate = Completer<void>();
      repo.onLoad = (market) => market == _twse ? gate.future : Future.value();
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      expect(repo.loads(_twse), 2); // 卡在第 2 次讀取
      c.read(dataUpdateEpochProvider.notifier).bump();
      unawaited(_notifier(c).checkFingerprint());
      async.flushMicrotasks();
      repo.onLoad = null;
      gate.complete();
      async.flushMicrotasks();
      expect(repo.loads(_twse), 3);
      async.flushMicrotasks();
      expect(repo.loads(_twse), 3);
      c.dispose();
    });
  });

  test('重讀中只有通知再觸發：結束後再讀一次', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final gate = Completer<void>();
      repo.onLoad = (market) => market == _twse ? gate.future : Future.value();
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      repo.onLoad = null;
      gate.complete();
      async.flushMicrotasks();
      expect(repo.loads(_twse), 3);
      c.dispose();
    });
  });

  test('重讀中只有指紋比對再觸發：結束後再讀一次', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final gate = Completer<void>();
      repo.onLoad = (market) => market == _twse ? gate.future : Future.value();
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      unawaited(_notifier(c).checkFingerprint());
      async.flushMicrotasks();
      repo.onLoad = null;
      gate.complete();
      async.flushMicrotasks();
      expect(repo.loads(_twse), 3);
      c.dispose();
    });
  });

  test('寫入夾在讀指紋與讀資料之間，下一次比對會再重讀', () {
    fakeAsync((async) {
      final repo = _Repo();
      // 第一次讀資料時，寫入剛好發生：之後的指紋已是新的
      repo.onLoad = (market) async {
        if (market == _twse) {
          repo.fingerprints[_twse] = _fp(_d1007, closeSum: 999);
        }
      };
      final c = _start(async, repo);
      repo.onLoad = null;
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      // 基準是讀資料「前」的指紋，所以立即比對就發現不同、重讀
      expect(repo.loads(_twse), 2);
      async.elapse(const Duration(minutes: 1));
      expect(repo.loads(_twse), 2);
      c.dispose();
    });
  });

  test('指紋查詢失敗保留畫面，下一分鐘照常比對', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final before = _state(c);
      repo.fingerprintThrows.add(_twse);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      expect(_state(c).markets, before.markets);
      expect(_state(c).error, isNull);
      repo.fingerprintThrows.clear();
      final calls = repo.fingerprintsOf(_twse);
      async.elapse(const Duration(minutes: 1));
      expect(repo.fingerprintsOf(_twse), calls + 1);
      expect(repo.loads(_twse), 1);
      c.dispose();
    });
  });

  test('指紋查詢持續失敗只記一次 warning', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      repo.fingerprintThrows.add(_twse);
      _notifier(c).setVisible(true);
      async.elapse(const Duration(minutes: 3));
      expect(warnings.where((w) => w.contains('熱力圖比對失敗')), hasLength(1));
      c.dispose();
    });
  });

  test('第一次讀取整個失敗顯示錯誤；下一次成功清掉', () {
    fakeAsync((async) {
      final repo = _Repo()..fingerprintThrows.addAll([_twse, _tpex]);
      final c = _start(async, repo);
      expect(_state(c).isLoading, isFalse);
      expect(_state(c).error, isNotNull);
      expect(_state(c).markets, isEmpty);
      repo.fingerprintThrows.clear();
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      expect(_state(c).error, isNull);
      expect(_state(c).markets.keys, unorderedEquals([_twse, _tpex]));
      c.dispose();
    });
  });

  test('有資料後的讀取失敗保留畫面、不顯示錯誤', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final before = _state(c).markets;
      repo.loadThrows.addAll([_twse, _tpex]);
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      expect(_state(c).markets, before);
      expect(_state(c).error, isNull);
      expect(_state(c).failedMarkets, {_twse, _tpex});
      c.dispose();
    });
  });

  test('單一市場讀取失敗後下一分鐘重試', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final before = _state(c).markets[_tpex];
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      repo.loadThrows.add(_tpex);
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      expect(_state(c).markets[_tpex], before);
      expect(_state(c).failedMarkets, {_tpex});
      repo.loadThrows.clear();
      final loads = repo.loads(_tpex);
      async.elapse(const Duration(minutes: 1));
      expect(repo.loads(_tpex), loads + 1);
      expect(_state(c).failedMarkets, isEmpty);
      c.dispose();
    });
  });

  test('讀取持續失敗只記一次 warning', () {
    fakeAsync((async) {
      final repo = _Repo()..loadThrows.add(_tpex);
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.elapse(const Duration(minutes: 3));
      expect(repo.loads(_tpex), greaterThanOrEqualTo(4));
      expect(warnings.where((w) => w.contains('讀取失敗')), hasLength(1));
      c.dispose();
    });
  });

  test('原本有資料、之後沒有正式資料的市場會從 markets 移除', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      expect(_state(c).markets.keys, contains(_tpex));
      repo.fingerprints[_tpex] = null;
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      expect(_state(c).markets.keys, [_twse]);
      c.dispose();
    });
  });

  test('沒有正式資料的市場不會每分鐘重讀', () {
    fakeAsync((async) {
      final repo = _Repo()..fingerprints[_tpex] = null;
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.elapse(const Duration(minutes: 3));
      expect(repo.loads(_tpex), 0);
      expect(repo.loads(_twse), 1);
      c.dispose();
    });
  });

  test('失敗後讀到沒有正式資料就不再重讀', () {
    fakeAsync((async) {
      final repo = _Repo()..loadThrows.add(_tpex);
      final c = _start(async, repo);
      expect(_state(c).failedMarkets, {_tpex});
      repo.fingerprints[_tpex] = null;
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      expect(_state(c).failedMarkets, isEmpty);
      final loads = repo.loads(_twse);
      async.elapse(const Duration(minutes: 3));
      expect(repo.loads(_twse), loads);
      c.dispose();
    });
  });

  test('讀取進行中離開頁面：不寫 state、不記 warning、不讀下一個市場', () {
    fakeAsync((async) {
      final repo = _Repo();
      final gate = Completer<void>();
      repo.onLoad = (market) => market == _twse ? gate.future : Future.value();
      final c = _open(repo);
      async.flushMicrotasks();
      // 進行中再觸發一次：結束時若不看是否已離開，會再讀一輪
      c.read(dataUpdateEpochProvider.notifier).bump();
      async.flushMicrotasks();
      c.dispose();
      gate.complete();
      async.flushMicrotasks();
      expect(warnings, isEmpty);
      expect(repo.loads(_tpex), 0);
      expect(repo.loads(_twse), 1);
    });
  });

  test('離開頁面後讀取才拋錯：不記 warning', () {
    fakeAsync((async) {
      final repo = _Repo();
      final gate = Completer<void>();
      repo.onLoad = (market) => market == _twse ? gate.future : Future.value();
      final c = _open(repo);
      async.flushMicrotasks();
      c.dispose();
      repo.loadThrows.add(_twse);
      gate.complete();
      async.flushMicrotasks();
      expect(warnings, isEmpty);
    });
  });

  test('離開頁面後指紋比對才拋錯：不記 warning', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      final gate = Completer<void>();
      repo.onFingerprint = (market) =>
          market == _twse ? gate.future : Future.value();
      unawaited(_notifier(c).checkFingerprint());
      async.flushMicrotasks();
      c.dispose();
      repo.fingerprintThrows.add(_twse);
      gate.complete();
      async.flushMicrotasks();
      expect(warnings, isEmpty);
    });
  });

  test('第一次讀取完成前就變可見：只讀一次', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _open(repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      expect(repo.loads(_twse), 1);
      expect(repo.fingerprintsOf(_twse), 1);
      c.dispose();
    });
  });

  test('指紋查詢恢復後再失敗，會再記一次 warning', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      repo.fingerprintThrows.add(_twse);
      async.elapse(const Duration(minutes: 1));
      repo.fingerprintThrows.clear();
      async.elapse(const Duration(minutes: 1));
      repo.fingerprintThrows.add(_twse);
      async.elapse(const Duration(minutes: 1));
      expect(warnings.where((w) => w.contains('熱力圖比對失敗')), hasLength(2));
      c.dispose();
    });
  });

  test('invalidate 重建後，可見的頁面仍每分鐘比對', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      c.invalidate(marketHeatmapProvider);
      c.read(marketHeatmapProvider);
      async.flushMicrotasks();
      final calls = repo.fingerprintsOf(_twse);
      async.elapse(const Duration(minutes: 2));
      expect(repo.fingerprintsOf(_twse), calls + 2);
      c.dispose();
    });
  });

  test('dispose 後計時器停止', () {
    fakeAsync((async) {
      final repo = _Repo();
      final c = _start(async, repo);
      _notifier(c).setVisible(true);
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 1);
      c.dispose();
      async.elapse(const Duration(minutes: 3));
      expect(async.periodicTimerCount, 0);
    });
  });
}
