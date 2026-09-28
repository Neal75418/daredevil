import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/domain/services/alert/intraday_poll_schedule.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/alert/alert_target_calculator.dart';

/// 快捷提醒鈕(2026-08-07)。
///
/// 存在理由:使用者要的是「**觸價後開始觀察**再自己決定」,不是每次手打
/// 價位。所以 app 把 5MA / 10MA / 月線 / 20 日高 / 守門價都算好放著——
/// **只算不決定**,點哪個、要不要點,主動權 100% 在使用者。
///
/// 建立動作刻意交給 [onSelected] 的呼叫端:這個 widget 不碰 provider,
/// 純顯示+回報,單元測試不需要 Riverpod harness。
class AlertQuickSet extends StatelessWidget {
  const AlertQuickSet({
    super.key,
    required this.bars,
    required this.onSelected,
    this.currentPrice,
    this.existingTargets = const {},
    this.now,
  });

  /// 日線(依日期升冪,最後一筆最新)
  final List<Ohlc> bars;

  final void Function(AlertKind kind, AlertTarget target) onSelected;

  /// 現價;給定時用來停用「條件已成立」的種類——設了會立刻觸發一次
  /// 就結束,是純噪音(2026-08-07 實機:緯創 183.5 已在 5MA 189.4 之下、
  /// 月線 166.3 之上,兩顆按鈕形同陷阱)。null=不臆測,全部可點。
  final double? currentPrice;

  /// 本檔已存在的提醒目標價。命中者停用——同一顆點兩次會建出兩筆一模
  /// 一樣的提醒(2026-08-08 實機重現),而兩筆都會各叫一次。
  /// 已存在的提醒,以 **(方向, 目標價)** 成對比對。
  ///
  /// 🚨 只比價格會出事(2026-08-08 三次審查):`breakBelowMa20` 與
  /// `breakAboveMa20` 的目標價**完全相同**(都是 ma20),只有方向不同。
  /// 用 `Set<double>` 去重時,建了停損型的「跌破月線」就會把語意完全
  /// 相反的「突破月線」(回榜資格)一起停用,而且標籤還謊稱「已設定」。
  final Set<(String, double)> existingTargets;

  /// 判斷「是否盤中」用的時間。**僅供測試注入**——寫死 `TaiwanTime.now()`
  /// 的話,那條盤中提示的測試結果會取決於跑測試的當下(2026-08-08:
  /// 心跳測試已經犯過一次同樣的日期依賴)。
  final DateTime? now;

  /// 盤中警語的定位鍵——測試環境不載入翻譯資產(既有測試只驗數字),
  /// 用文字內容找會抓到原始 key,改用 Key 才穩定。
  static const staleWarningKey = Key('alertQuickSet.staleDuringMarket');

  /// DB 價格列 → 計算用單位。**明確依日期升冪排序**,不假設 DAO 的
  /// 回傳方向(2026-08-07 實機 bug:接線處誤以為是降冪而多 reversed 一次,
  /// 均線改用最舊的幾根算出來——緯創現價 183.5 卻顯示 5MA 122.8、
  /// 「20 日高」128.0 低於現價)。OHLC 任一缺值或收盤 ≤0 的列略過(停牌)。
  static List<Ohlc> toOhlc(List<DailyPriceEntry> history) {
    final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
    return [
      for (final p in sorted)
        if (p.high != null && p.low != null && p.close != null && p.close! > 0)
          Ohlc(high: p.high!, low: p.low!, close: p.close!),
    ];
  }

  /// 顯示順序:由緊到鬆的支撐,再到突破,守門價殿後(它是風控不是機會)
  static const _order = [
    AlertKind.breakBelowMa5,
    AlertKind.breakBelowMa10,
    AlertKind.breakBelowMa20,
    AlertKind.breakAboveMa20,
    AlertKind.breakAbove20DayHigh,
    AlertKind.stopGate,
  ];

  /// 已有同價位的提醒?浮點比較用 0.005 容差(顯示精度是兩位小數)
  bool _alreadySet(AlertTarget t) => existingTargets.any(
    (e) => e.$1 == t.alertTypeValue && (e.$2 - t.price).abs() < 0.005,
  );

  /// 是否處於台股盤中——只在這段期間顯示「以昨收判斷」的提示,
  /// 盤後與盤前的資料本來就是最新的,不需要打擾使用者。
  bool get _isMarketHours =>
      IntradayPollSchedule.isMarketHours(now ?? TaiwanTime.now());

  /// 條件是否已成立(向上型:現價已在目標之上;向下型:已在其下)
  bool _isAlreadyMet(AlertTarget t) {
    final p = currentPrice;
    if (p == null) return false;
    return t.isUpward ? p >= t.price : p <= t.price;
  }

  @override
  Widget build(BuildContext context) {
    final targets = AlertTargetCalculator.compute(bars);
    if (targets.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'alert.quickSet.hint'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        // 盤中提示(2026-08-08):這排按鈕的均線與「已成立」判斷都來自
        // **最後一根日線**(每日更新 15:30 才跑),對今天盤中的走勢一無所知。
        // 盤中設提醒時,一個已經跌破的價位看起來仍可點,點下去會在 5 分鐘
        // 內立刻觸發、把一次性提醒燒掉。
        //
        // 刻意**不**讓 UI 去抓即時報價來修正:MIS 的限流是伺服器端按 IP
        // 算的,而 launchd 的盤中檢查(55 次/交易日)靠同一個額度活著——
        // 為了讓守門更準而消耗它,等於讓被守的東西更脆弱。標示限制即可,
        // 而 v3.4 的流程本來就是「條件單前一晚寫好」。
        if (_isMarketHours) ...[
          const SizedBox(height: DesignTokens.spacing4),
          Text(
            key: staleWarningKey,
            'alert.quickSet.staleDuringMarket'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: DesignTokens.spacing8),
        Wrap(
          spacing: DesignTokens.spacing8,
          runSpacing: DesignTokens.spacing8,
          children: [
            for (final kind in _order)
              if (targets[kind] case final t?)
                Builder(
                  builder: (context) {
                    final met = _isAlreadyMet(t);
                    final dup = _alreadySet(t);
                    return ActionChip(
                      avatar: Icon(
                        (met || dup)
                            ? Icons.check_circle_outline
                            : (t.isUpward
                                  ? Icons.trending_up
                                  : Icons.trending_down),
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      label: Text(
                        dup
                            ? '${'alert.quickSet.${kind.name}'.tr()} '
                                  '${t.price.toStringAsFixed(2)} · '
                                  '${'alert.quickSet.alreadySet'.tr()}'
                            : met
                            ? '${'alert.quickSet.${kind.name}'.tr()} '
                                  '${t.price.toStringAsFixed(2)} · '
                                  '${'alert.quickSet.alreadyMet'.tr()}'
                            : '${'alert.quickSet.${kind.name}'.tr()} '
                                  '${t.price.toStringAsFixed(2)}',
                      ),
                      // 條件已成立 → 停用。標籤仍顯示,讓這排按鈕同時
                      // 是「現價相對各條線在哪」的狀態讀數。
                      onPressed: (met || dup)
                          ? null
                          : () => onSelected(kind, t),
                    );
                  },
                ),
          ],
        ),
      ],
    );
  }
}
