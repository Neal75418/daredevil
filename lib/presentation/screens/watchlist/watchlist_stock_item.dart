import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/stock_card.dart';

/// 自選股列表項目（含左右滑動操作）
///
/// - 右滑：查看詳情
/// - 左滑：從自選移除
/// - 前 10 筆項目附帶交錯入場動畫
class WatchlistStockItem extends StatelessWidget {
  const WatchlistStockItem({
    super.key,
    required this.item,
    required this.index,
    required this.showLimitMarkers,
    required this.onView,
    required this.onRemove,
    required this.onLongPress,
  });

  final WatchlistItemData item;
  final int index;
  final bool showLimitMarkers;

  /// 查看詳情回呼（導航至股票詳情頁）
  final VoidCallback onView;

  /// 從自選移除回呼（不含 haptic，由 widget 內部處理）
  final VoidCallback onRemove;

  /// 長按回呼（顯示預覽底部表單）
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final card = RepaintBoundary(
      child: Slidable(
        key: ValueKey(item.symbol),
        // 向右滑動（startActionPane）→ 查看詳情
        startActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) {
                HapticFeedback.lightImpact();
                onView();
              },
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              icon: Icons.visibility_outlined,
              label: 'watchlist.view'.tr(),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
          ],
        ),
        // 向左滑動（endActionPane）→ 從自選股移除
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) {
                HapticFeedback.mediumImpact();
                onRemove();
              },
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'watchlist.remove'.tr(),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ],
        ),
        child: _buildCard(),
      ),
    );

    // 前 10 項的交錯入場動畫
    if (index < 10) {
      return card
          .animate()
          .fadeIn(
            delay: Duration(milliseconds: 50 * index),
            duration: AnimDurations.moderate,
          )
          .slideX(
            begin: 0.05,
            duration: AnimDurations.moderate,
            curve: AnimCurves.smooth,
          );
    }
    return card;
  }

  StockCard _buildCard() {
    return StockCard(
      symbol: item.symbol,
      stockName: item.stockName,
      market: item.market,
      latestClose: item.latestClose,
      priceChange: item.priceChange,
      score: item.score,
      reasons: item.reasons,
      trendState: item.trendState,
      isInWatchlist: true,
      recentPrices: item.recentPrices,
      warningType: item.warningType,
      showLimitMarkers: showLimitMarkers,
      onTap: onView,
      onLongPress: onLongPress,
      onWatchlistTap: () {
        HapticFeedback.lightImpact();
        onRemove();
      },
    );
  }
}

/// Grid 佈局用的自選股卡片（無 Slidable，改用長按選單）
///
/// 前 20 筆項目附帶交錯縮放入場動畫。
class WatchlistStockGridItem extends StatelessWidget {
  const WatchlistStockGridItem({
    super.key,
    required this.item,
    required this.index,
    required this.showLimitMarkers,
    required this.onView,
    required this.onRemove,
    required this.onLongPress,
  });

  final WatchlistItemData item;
  final int index;
  final bool showLimitMarkers;
  final VoidCallback onView;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final card = RepaintBoundary(
      child: StockCard(
        symbol: item.symbol,
        stockName: item.stockName,
        market: item.market,
        latestClose: item.latestClose,
        priceChange: item.priceChange,
        score: item.score,
        reasons: item.reasons,
        trendState: item.trendState,
        isInWatchlist: true,
        recentPrices: item.recentPrices,
        warningType: item.warningType,
        showLimitMarkers: showLimitMarkers,
        onTap: onView,
        onLongPress: onLongPress,
        onWatchlistTap: () {
          HapticFeedback.lightImpact();
          onRemove();
        },
      ),
    );

    // Grid 動畫：前 20 筆項目使用交錯進場
    if (index < 20) {
      return card
          .animate()
          .fadeIn(
            delay: Duration(milliseconds: 30 * index),
            duration: AnimDurations.normal,
          )
          .scale(
            begin: const Offset(0.95, 0.95),
            duration: AnimDurations.normal,
            curve: AnimCurves.smooth,
          );
    }
    return card;
  }
}
