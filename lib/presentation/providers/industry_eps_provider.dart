import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/models/tpex/tpex_industry_eps.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==================================================
// 產業 EPS 狀態
// ==================================================

/// 產業別 EPS 排名狀態
class IndustryEpsState {
  const IndustryEpsState({
    this.allData = const [],
    this.isLoading = false,
    this.error,
    this.selectedIndustry,
    this.fetchedAt,
  });

  final List<TpexIndustryEps> allData;
  final bool isLoading;
  final String? error;
  final String? selectedIndustry;
  final DateTime? fetchedAt;

  /// 所有可選的產業列表
  List<String> get industries {
    final set = <String>{};
    for (final d in allData) {
      if (d.industry.isNotEmpty) set.add(d.industry);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// 篩選後的資料（依 EPS 降序排列）
  List<TpexIndustryEps> get filteredData {
    var data = allData;
    if (selectedIndustry != null) {
      data = data.where((d) => d.industry == selectedIndustry).toList();
    }
    return data..sort((a, b) => b.eps.compareTo(a.eps));
  }

  /// 季別標示
  String get quarterLabel {
    if (allData.isEmpty) return '';
    final first = allData.first;
    return '${first.year} Q${first.quarter}';
  }

  IndustryEpsState copyWith({
    List<TpexIndustryEps>? allData,
    bool? isLoading,
    String? error,
    Object? selectedIndustry = sentinel,
    DateTime? fetchedAt,
  }) {
    return IndustryEpsState(
      allData: allData ?? this.allData,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      selectedIndustry: selectedIndustry == sentinel
          ? this.selectedIndustry
          : selectedIndustry as String?,
    );
  }
}

// ==================================================
// 產業 EPS Notifier
// ==================================================

class IndustryEpsNotifier extends Notifier<IndustryEpsState> {
  /// autoDispose 後的必要配套(review 重現 2026-08-29):3 分鐘窗過後
  /// loadData 在途中 dispose,post-await 的 state 寫入會拋
  /// UnmountedRefException——catch 還會記「載入失敗」的假 breadcrumb
  /// (API 其實成功)再二次拋逸出。與 comparison_provider 同一 guard;
  /// epoch 規約 #2 禁的是 listener 內的條件,notifier 自身早退 guard
  /// 是它明文要求的。
  bool _active = true;

  @override
  IndustryEpsState build() {
    _active = true;
    ref.onDispose(() => _active = false);
    // 保活機制：keepAliveMin 內返回同一頁面時使用快取（與 stock_detail
    // 同一樣板）。窗過期即 dispose——這不只是記憶體整潔：本 provider 掛
    // epoch listener，keepAlive 版本讓「進過一次畫面」變成「每次每日更新
    // 都打一次 TPEx API 直到 app 關掉」（2026-08-29 稽核實證），listener
    // 的壽命必須跟著畫面走，而 epoch 規約 #2 禁止在 listener 內加條件
    // 判斷——所以由 autoDispose 收生命週期，不加 guard。
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: ApiConfig.keepAliveMin), () {
      try {
        link.close();
      } catch (_) {
        // link 可能已在 dispose 時關閉，忽略此例外
      }
    });
    ref.onDispose(timer.cancel);

    // M6 follow-up：runUpdate 完成後 bump dataUpdateEpoch；產業 EPS
    // 畫面開著時自動 reload，否則只在使用者重新進入頁面才更新。
    ref.listen(dataUpdateEpochProvider, (_, _) {
      loadData();
    });
    return const IndustryEpsState();
  }

  /// 從 TPEX API 載入產業 EPS 資料
  Future<void> loadData() async {
    if (!_active) return; // 讀 state.isLoading 之前——dispose 後讀 state 也 throw
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final tpex = ref.read(tpexClientProvider);
      final data = await tpex.getIndustryEps();
      if (!_active) return; // dispose 後寫 state 會 throw

      state = state.copyWith(
        allData: data,
        isLoading: false,
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      // 真 API 錯誤也可能落在 dispose 之後——先 guard 再碰 state,
      // 否則這裡的 warning 是假失敗(或二次 throw 逸出)
      if (!_active) return;
      AppLogger.warning('IndustryEpsNotifier', '載入產業 EPS 失敗', e);
      state = state.copyWith(error: ErrorDisplay.message(e), isLoading: false);
    }
  }

  /// 設定產業篩選（null = 全部）
  void setIndustryFilter(String? industry) {
    state = state.copyWith(selectedIndustry: industry);
  }

  /// 清除錯誤訊息（用於關閉錯誤 banner）
  void clearError() => state = state.copyWith(error: null);
}

// ==================================================
// Provider
// ==================================================

final industryEpsProvider =
    NotifierProvider.autoDispose<IndustryEpsNotifier, IndustryEpsState>(
      IndustryEpsNotifier.new,
    );
