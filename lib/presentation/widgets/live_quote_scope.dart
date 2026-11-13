import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:daredevil/presentation/providers/live_quote_provider.dart';

/// 把畫面要看的股票登記到報價中心(2026-10-06)。
///
/// **可見性 = `TickerMode.of(context)`**:go_router 沒在看的分頁包在
/// `TickerMode(enabled: false)`,被不透明頁面蓋住的頁面也是(Overlay 以
/// `tickerEnabled: false` 建構);底部面板、對話框不是不透明頁面,底下
/// 畫面維持登記。行為由 `test/presentation/widgets/live_quote_scope_test.dart`
/// 以真的 go_router 釘住,套件升級改了行為會先紅。
///
/// 清單有兩種給法:
/// - 預設建構子:固定清單,畫面每次重建時給當下算的、重新登記。
/// - [LiveQuoteScope.listen]:給一個 provider,清單一變就登記,不等畫面重畫。
///   App 看不見時 Flutter 不畫幀,要在那時跟著換清單的頁面(熱力圖收盤後
///   抓到一批換下一批)用這個。這一頁看不見(`TickerMode` 關閉)時不聽這個
///   provider,看得見時才聽。provider 要用 autoDispose:沒人聽時要被釋放;
///   還掛著的話,回到這一頁時會踩到 Riverpod 的暫停計數檢查(見
///   `_LiveQuoteScopeState._subscription` 的說明)。
class LiveQuoteScope extends ConsumerStatefulWidget {
  const LiveQuoteScope({
    super.key,
    required List<LiveQuoteRegistration> this.registrations,
    required this.child,
  }) : source = null;

  const LiveQuoteScope.listen({
    super.key,
    required ProviderListenable<List<LiveQuoteRegistration>> this.source,
    required this.child,
  }) : registrations = null;

  /// 固定的清單;[LiveQuoteScope.listen] 時為 null
  final List<LiveQuoteRegistration>? registrations;

  /// 清單的來源;預設建構子時為 null
  final ProviderListenable<List<LiveQuoteRegistration>>? source;

  final Widget child;

  @override
  ConsumerState<LiveQuoteScope> createState() => _LiveQuoteScopeState();
}

class _LiveQuoteScopeState extends ConsumerState<LiveQuoteScope> {
  /// initState 先拿:dispose 時不能 ref.read(Riverpod 3 會拋 StateError)
  late final LiveQuoteCenter _center;
  bool _registered = false;

  /// [LiveQuoteScope.source] 的訂閱,只在這一頁看得見時存在。
  ///
  /// 看不見時是關掉、不是暫停:暫停的話清單的 provider 還掛著、只是不活躍,
  /// 而它依賴的 provider 若同時被畫面 `ref.watch`(熱力圖頁就是)、期間又變過,
  /// 回到這一頁時 flutter_riverpod 先恢復畫面的訂閱、當場重算,通知到這個
  /// 不活躍的下游,riverpod 3.2.1 內部的暫停計數檢查會失敗。關掉後 autoDispose
  /// 的 provider 會被釋放,回來時重新建立
  ProviderSubscription<List<LiveQuoteRegistration>>? _subscription;

  @override
  void initState() {
    super.initState();
    _center = ref.read(liveQuoteCenterProvider.notifier);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LiveQuoteScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 來源換了:關掉舊的訂閱,下面改聽新的
    if (oldWidget.source != widget.source) _stopListening();
    // 每次重建都重新登記,清單內容沒變也一樣:報價中心連登記的日期一起記,
    // 「已有今天正式資料」只在登記那天算數,要跟著畫面最近一次重建。內容
    // 相同的重新登記不影響進行中的一輪
    _sync();
  }

  void _stopListening() {
    _subscription?.close();
    _subscription = null;
  }

  void _sync() {
    if (!TickerMode.of(context)) {
      _stopListening();
      if (_registered) {
        _center.unregister(this);
        _registered = false;
      }
      return;
    }
    final source = widget.source;
    if (source == null) {
      _center.register(this, widget.registrations!);
    } else {
      // 清單之後每次變動都以同一個 owner 重新登記;現值先登記一次
      final subscription = _subscription ??= ref.listenManual(
        source,
        (_, next) => _center.register(this, next),
      );
      _center.register(this, subscription.read());
    }
    _registered = true;
  }

  @override
  void dispose() {
    if (_registered) _center.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
