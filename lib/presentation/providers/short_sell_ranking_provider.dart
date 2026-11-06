import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/models/tpex/tpex_short_sell_ranking.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/core/utils/device_time.dart';

// ==================================================
// 融券排行狀態
// ==================================================

/// 融券賣出排行狀態
class ShortSellRankingState {
  const ShortSellRankingState({
    this.rankings = const [],
    this.isLoading = false,
    this.error,
    this.fetchedAt,
  });

  final List<TpexShortSellRanking> rankings;
  final bool isLoading;
  final String? error;
  final DateTime? fetchedAt;

  ShortSellRankingState copyWith({
    List<TpexShortSellRanking>? rankings,
    bool? isLoading,
    Object? error = sentinel,
    DateTime? fetchedAt,
  }) {
    return ShortSellRankingState(
      rankings: rankings ?? this.rankings,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, sentinel) ? this.error : error as String?,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}

// ==================================================
// 融券排行 Notifier
// ==================================================

class ShortSellRankingNotifier extends Notifier<ShortSellRankingState> {
  @override
  ShortSellRankingState build() => const ShortSellRankingState();

  /// 從 TPEX API 載入融券排行資料
  Future<void> loadData() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final tpex = ref.read(tpexClientProvider);
      final rankings = await tpex.getShortSellRanking();

      state = state.copyWith(
        rankings: rankings,
        isLoading: false,
        error: null, // 成功後清除先前的錯誤
        fetchedAt: DeviceTime.now(),
      );
    } catch (e) {
      AppLogger.warning('ShortSellRankingNotifier', '載入融券排行失敗', e);
      state = state.copyWith(error: ErrorDisplay.message(e), isLoading: false);
    }
  }

  /// 清除錯誤訊息（用於關閉錯誤 banner）
  void clearError() => state = state.copyWith(error: null);
}

// ==================================================
// Provider
// ==================================================

final shortSellRankingProvider =
    NotifierProvider<ShortSellRankingNotifier, ShortSellRankingState>(
      ShortSellRankingNotifier.new,
    );
