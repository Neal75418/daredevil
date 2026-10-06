import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/presentation/providers/live_quote_provider.dart';

/// 把畫面要看的股票登記到報價中心(2026-10-06)。
///
/// **可見性 = `TickerMode.of(context)`**:go_router 沒在看的分頁包在
/// `TickerMode(enabled: false)`,被不透明頁面蓋住的頁面也是(Overlay 以
/// `tickerEnabled: false` 建構);底部面板、對話框不是不透明頁面,底下
/// 畫面維持登記。行為由 `test/presentation/widgets/live_quote_scope_test.dart`
/// 以真的 go_router 釘住,套件升級改了行為會先紅。
class LiveQuoteScope extends ConsumerStatefulWidget {
  const LiveQuoteScope({
    super.key,
    required this.registrations,
    required this.child,
  });

  final List<LiveQuoteRegistration> registrations;
  final Widget child;

  @override
  ConsumerState<LiveQuoteScope> createState() => _LiveQuoteScopeState();
}

class _LiveQuoteScopeState extends ConsumerState<LiveQuoteScope> {
  /// initState 先拿:dispose 時不能 ref.read(Riverpod 3 會拋 StateError)
  late final LiveQuoteCenter _center;
  bool _registered = false;

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
    if (!listEquals(oldWidget.registrations, widget.registrations)) _sync();
  }

  void _sync() {
    if (TickerMode.of(context)) {
      _center.register(this, widget.registrations);
      _registered = true;
    } else if (_registered) {
      _center.unregister(this);
      _registered = false;
    }
  }

  @override
  void dispose() {
    if (_registered) _center.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
