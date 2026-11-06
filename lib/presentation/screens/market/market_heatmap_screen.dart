import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_layout.dart';
import 'package:daredevil/presentation/providers/app_visibility_provider.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_industry_group_sheet.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_legend.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_other_sheet.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_view.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

/// 大盤熱力圖（收盤後）：上市、上櫃各一張，依產業分區、面積是市值、顏色是
/// 當日漲跌。從大盤總覽頁標題列進入。
class MarketHeatmapScreen extends ConsumerStatefulWidget {
  const MarketHeatmapScreen({super.key});

  @override
  ConsumerState<MarketHeatmapScreen> createState() =>
      _MarketHeatmapScreenState();
}

class _MarketHeatmapScreenState extends ConsumerState<MarketHeatmapScreen> {
  /// 產業選單的「全市場」（產業 key 可能是空字串，不能拿字串當哨兵值）
  static const _wholeMarket = Object();

  String _market = MarketCode.twse;
  String? _zoom;
  HeatmapPaintLabels? _labels;
  Locale? _labelsLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 依語系建一次並保存：每次 build 新建，painter 的比較會一直要求重畫
    final locale = Localizations.localeOf(context);
    if (_labels == null || locale != _labelsLocale) {
      _labelsLocale = locale;
      _labels = HeatmapPaintLabels(
        uncategorized: 'marketHeatmap.uncategorized'.tr(),
        industrySemantics: _industrySemantics,
        tileSemantics: _tileSemantics,
        otherLabel: _otherLabel,
        otherShortLabel: 'marketHeatmap.otherShort'.tr(),
        wholeLabel: _wholeLabel,
        otherSemantics: _otherSemantics,
        groupLabel: _groupLabel,
        groupShortLabel: 'marketHeatmap.groupShort'.tr(),
        groupSemantics: _groupSemantics,
      );
    }
  }

  void _selectMarket(String market) => setState(() {
    _market = market;
    _zoom = null;
  });

  void _zoomTo(String industryKey) => setState(() => _zoom = industryKey);

  void _clearZoom() => setState(() => _zoom = null);

  void _openStock(String symbol) => context.push(AppRoutes.stockDetail(symbol));

  /// 「其他 N 檔」的成員清單；點一檔先收起清單再進個股頁
  void _showOther(HeatmapIndustryLayout industry, HeatmapOtherLayout other) {
    final name = industry.industry.name ?? 'marketHeatmap.uncategorized'.tr();
    showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, controller) => HeatmapOtherSheet(
          title: '$name · ${_otherLabel(other.members.length)}',
          other: other,
          scrollController: controller,
          onStockTap: (symbol) {
            Navigator.of(sheetContext).pop();
            _openStock(symbol);
          },
        ),
      ),
    );
  }

  /// 「其他 N 個產業」的產業清單；點一個先收起清單再放大該產業
  void _showSmallIndustries(HeatmapIndustryGroupLayout group) {
    showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, controller) => HeatmapIndustryGroupSheet(
          title: _groupLabel(group.members.length),
          group: group,
          scrollController: controller,
          onIndustryTap: (key) {
            Navigator.of(sheetContext).pop();
            _zoomTo(key);
          },
        ),
      ),
    );
  }

  /// 重讀後放大中的產業不在了：回到全市場（之後它再出現也不自己放大）
  void _dropMissingZoom(MarketHeatmapState next) {
    final zoom = _zoom;
    if (zoom == null) return;
    final industries = next.markets[_market]?.industries ?? const [];
    if (!industries.any((i) => i.key == zoom)) _clearZoom();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marketHeatmapProvider);
    ref.listen(marketHeatmapProvider, (_, next) => _dropMissingZoom(next));
    final overview = ref.watch(marketOverviewProvider);
    // 登記的「是否已有今天正式資料」跟現在有關：跨過午夜等邊界時重算
    ref.watch(liveQuoteBoundaryProvider);
    final live = ref.watch(marketLiveIndicesProvider);
    final data = state.markets[_market];
    final zoom = _zoom;
    return Scaffold(
      appBar: AppBar(
        title: zoom == null
            ? Text('marketHeatmap.title'.tr())
            : TextButton(
                onPressed: _clearZoom,
                // 按鈕的 Material 會蓋掉標題列的單行設定：自己限一行
                child: Text(
                  'marketHeatmap.backToWhole'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        actions: [
          _marketSelector(),
          _industryMenu(data),
          const SizedBox(width: DesignTokens.spacing8),
        ],
      ),
      body: LiveQuoteScope(
        registrations: marketIndexRegistrations(
          overview,
          ref.read(appClockProvider).now(),
        ),
        // 包住所有狀態：空狀態、錯誤卡片也要輪詢，才等得到背景的第一次寫入
        child: _HeatmapVisibility(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IndexHeader(
                market: _market,
                overview: overview,
                live: live,
                dataDate: data?.dataDate,
              ),
              Expanded(child: _content(state, data, zoom)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
    MarketHeatmapState state,
    HeatmapMarketData? data,
    String? zoom,
  ) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (data != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing16,
              vertical: DesignTokens.spacing4,
            ),
            child: HeatmapLegend(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing8,
                vertical: DesignTokens.spacing4,
              ),
              child: HeatmapView(
                data: data,
                zoomIndustryKey: zoom,
                onIndustryTap: _zoomTo,
                onTileTap: _openStock,
                onOtherTap: _showOther,
                onSmallIndustriesTap: _showSmallIndustries,
                labels: _labels!,
              ),
            ),
          ),
          if (data.excludedForShares > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacing16,
                0,
                DesignTokens.spacing16,
                DesignTokens.spacing8,
              ),
              child: Text(
                'marketHeatmap.footerExcluded'.tr(
                  namedArgs: {'count': '${data.excludedForShares}'},
                ),
                style: muted,
              ),
            ),
        ],
      );
    }
    if (state.isLoading && state.markets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // 兩個市場都讀取失敗時 provider 另設 error，此時兩個市場都在
    // failedMarkets 裡，看這個就夠
    if (state.failedMarkets.contains(_market)) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacing16),
          child: Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: Text('marketHeatmap.loadError'.tr()),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(marketHeatmapProvider.notifier).reload(),
                child: Text('common.retry'.tr()),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacing32),
      child: Text(
        'marketHeatmap.empty'.tr(),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 上市／上櫃切換（樣式同大盤總覽手機版，但不顯示選取勾勾：放在標題列，
  /// 窄螢幕要把寬度留給標題）
  Widget _marketSelector() => SegmentedButton<String>(
    showSelectedIcon: false,
    segments: [
      for (final (market, key) in const [
        (MarketCode.twse, 'marketOverview.twse'),
        (MarketCode.tpex, 'marketOverview.tpex'),
      ])
        ButtonSegment(
          value: market,
          label: Text(
            key.tr(),
            style: const TextStyle(fontSize: DesignTokens.fontSizeSm),
          ),
        ),
    ],
    selected: {_market},
    onSelectionChanged: (selection) => _selectMarket(selection.first),
    style: ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing12,
          vertical: DesignTokens.spacing6,
        ),
      ),
    ),
  );

  /// 產業選單：第一項全市場，其餘依市值排序並帶市值加權漲跌。小產業在全市場
  /// 圖上合成「其他 N 個產業」，也可以從這裡直接放大。
  Widget _industryMenu(HeatmapMarketData? data) {
    final industries = [...?data?.industries]
      ..sort((a, b) {
        final byCap = b.marketCap.compareTo(a.marketCap);
        return byCap != 0 ? byCap : a.key.compareTo(b.key);
      });
    final uncategorized = 'marketHeatmap.uncategorized'.tr();
    return PopupMenuButton<Object>(
      tooltip: 'marketHeatmap.industryMenu'.tr(),
      enabled: industries.isNotEmpty,
      icon: const Icon(Icons.category_outlined),
      onSelected: (value) {
        if (value is String) {
          _zoomTo(value);
        } else {
          _clearZoom();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<Object>(
          value: _wholeMarket,
          child: Text('marketHeatmap.wholeMarket'.tr()),
        ),
        for (final industry in industries)
          PopupMenuItem<Object>(
            value: industry.key,
            child: Text(
              '${industry.name ?? uncategorized} '
              '${switch (industry.weightedChangePercent) {
                final pct? => formatHeatmapPercent(pct),
                null => '—',
              }}',
            ),
          ),
      ],
    );
  }
}

/// 漲跌方向的翻譯 key（依分階用的同一個四捨五入值）
String _directionKey(double percent) {
  final rounded = HeatmapParams.roundPercent(percent);
  if (rounded > 0) return 'marketHeatmap.dirUp';
  if (rounded < 0) return 'marketHeatmap.dirDown';
  return 'marketHeatmap.dirFlat';
}

/// 無障礙描述用的漲跌幅：方向另外唸，這裡不帶正負號
String _unsignedPercent(double percent) =>
    '${HeatmapParams.roundPercent(percent).abs().toStringAsFixed(2)}%';

String _industrySemantics(HeatmapIndustryLayout layout) {
  final industry = layout.industry;
  final name = industry.name ?? 'marketHeatmap.uncategorized'.tr();
  final count = '${industry.tiles.length}';
  final pct = industry.weightedChangePercent;
  if (pct == null) {
    return 'marketHeatmap.semIndustryNoChange'.tr(
      namedArgs: {'name': name, 'count': count},
    );
  }
  return 'marketHeatmap.semIndustry'.tr(
    namedArgs: {
      'name': name,
      'dir': _directionKey(pct).tr(),
      'pct': _unsignedPercent(pct),
      'count': count,
    },
  );
}

String _otherLabel(int count) =>
    'marketHeatmap.otherLabel'.tr(namedArgs: {'count': '$count'});

String _groupLabel(int count) =>
    'marketHeatmap.groupLabel'.tr(namedArgs: {'count': '$count'});

/// 小產業合併塊的描述：「其他 N 個產業」、共幾檔（標籤以產業為單位，後面的
/// 家數是檔，先說總檔數才聽得懂）、市值加權漲跌與漲跌家數；含自選或持股時
/// 補上檔數。全是空心時的句型本來就寫檔數，不重複。
String _groupSemantics(HeatmapIndustryGroupLayout group) {
  final label = _groupLabel(group.members.length);
  final percent = group.weightedChangePercent;
  return _withMine(
    _foldSemantics(
      label: percent == null
          ? label
          : 'marketHeatmap.semGroupLabel'.tr(
              namedArgs: {'label': label, 'count': '${group.stockCount}'},
            ),
      count: group.stockCount,
      percent: percent,
      breadth: group.breadth,
    ),
    group.mineCount,
  );
}

String _wholeLabel(int count) =>
    'marketHeatmap.tooltipStocks'.tr(namedArgs: {'count': '$count'});

/// 合併塊的描述：標籤（整個產業時是產業名稱）、市值加權漲跌與漲跌家數；
/// 含自選或持股時補上檔數（畫面上是自選框）
String _otherSemantics(HeatmapIndustryLayout layout, HeatmapOtherLayout other) {
  final label = other.wholeIndustry
      ? layout.industry.name ?? 'marketHeatmap.uncategorized'.tr()
      : _otherLabel(other.members.length);
  return _withMine(
    _foldSemantics(
      label: label,
      count: other.members.length,
      percent: other.weightedChangePercent,
      breadth: other.breadth,
    ),
    other.mineCount,
  );
}

/// 合併塊共用的描述句：標籤、市值加權漲跌、漲跌家數（全是空心時寫檔數）
String _foldSemantics({
  required String label,
  required int count,
  required double? percent,
  required HeatmapBreadth breadth,
}) {
  final pct = percent;
  if (pct == null) {
    return 'marketHeatmap.semOtherNoChange'.tr(
      namedArgs: {'label': label, 'count': '$count'},
    );
  }
  final b = breadth;
  final args = {
    'label': label,
    'dir': _directionKey(pct).tr(),
    'pct': _unsignedPercent(pct),
    'up': '${b.up}',
    'down': '${b.down}',
    'flat': '${b.flat}',
  };
  return b.hollow > 0
      ? 'marketHeatmap.semOtherWithHollow'.tr(
          namedArgs: {...args, 'hollow': '${b.hollow}'},
        )
      : 'marketHeatmap.semOther'.tr(namedArgs: args);
}

String _withMine(String base, int mineCount) => mineCount > 0
    ? 'marketHeatmap.semWithMine'.tr(
        namedArgs: {'base': base, 'count': '$mineCount'},
      )
    : base;

String _tileSemantics(HeatmapTileLayout layout) {
  final tile = layout.tile;
  return switch (tile.change) {
    TileChangeValue(:final percent) => 'marketHeatmap.semTile'.tr(
      namedArgs: {
        'name': tile.name,
        'dir': _directionKey(percent).tr(),
        'pct': _unsignedPercent(percent),
      },
    ),
    TileChangeHollow(:final reason) => 'marketHeatmap.semTileHollow'.tr(
      namedArgs: {
        'name': tile.name,
        'reason': switch (reason) {
          HollowReason.noChangeData => 'marketHeatmap.hollowNoChange'.tr(),
        },
      },
    ),
  };
}

/// 頁首：該市場指數（與大盤總覽同一來源、同一套非即時標示）與熱力圖的資料
/// 時間。兩者來源不同，各自標示。
class _IndexHeader extends StatelessWidget {
  const _IndexHeader({
    required this.market,
    required this.overview,
    required this.live,
    required this.dataDate,
  });

  final String market;
  final MarketOverviewState overview;
  final MarketLiveIndices live;
  final DateTime? dataDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final strong = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final shown = live.byMarket[market];
    final index = shown?.index ?? heroIndexOf(overview, market);
    final label =
        (market == MarketCode.twse
                ? 'marketOverview.summary.taiex'
                : 'marketOverview.summary.tpex')
            .tr();
    final date = dataDate;
    // 即時報價的狀態優先；否則指數比格子新時說明指數是哪天的收盤（右側的
    // 「M/D 收盤」是格子的日期）
    final closeOf = index == null || date == null
        ? null
        : indexCloseOfDate(
            index: index,
            isLive: shown?.isLive ?? false,
            compareDate: date,
          );
    final statusText =
        shown?.statusText ??
        (closeOf == null ? null : indexCloseOfText(closeOf));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing8,
        DesignTokens.spacing16,
        DesignTokens.spacing4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: index == null
                    ? Text(
                        '$label ${'marketOverview.noData'.tr()}',
                        style: muted,
                      )
                    : Wrap(
                        spacing: DesignTokens.spacing6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(label, style: muted),
                          PriceFlash(
                            // 切換市場時沿用同一個位置：沒有 key 會把另一個
                            // 指數的閃色事件當成變動重播
                            key: ValueKey(index.name),
                            flash: shown?.flash,
                            enabled: shown?.flashEnabled ?? true,
                            child: Text(
                              NumberFormat('#,##0.00').format(index.close),
                              style: strong,
                            ),
                          ),
                          Text(
                            indexChangePercentText(index),
                            style: strong?.copyWith(
                              color: context.priceColor(index.change),
                            ),
                          ),
                          // 備援值（非即時）不得與即時值同貌：帶資料日期
                          if (!(shown?.isLive ?? false) &&
                              overview.indexStaleNames.contains(
                                heroIndexName(market),
                              ))
                            Text(
                              'marketOverview.indexStale'.tr(
                                namedArgs: {
                                  'date':
                                      '${index.date.month}/${index.date.day}',
                                },
                              ),
                              style: muted?.copyWith(
                                color: theme.brightness == Brightness.light
                                    ? WarningColors.warningOnLight
                                    : WarningColors.warning,
                              ),
                            ),
                        ],
                      ),
              ),
              if (date != null)
                Text(
                  'marketHeatmap.closeOf'.tr(
                    namedArgs: {'date': '${date.month}/${date.day}'},
                  ),
                  style: muted,
                ),
            ],
          ),
          if (statusText != null)
            Text(
              statusText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// 頁面可見（沒被不透明頁蓋住、App 在前景）時才讓熱力圖輪詢內容指紋
class _HeatmapVisibility extends ConsumerStatefulWidget {
  const _HeatmapVisibility({required this.child});

  final Widget child;

  @override
  ConsumerState<_HeatmapVisibility> createState() => _HeatmapVisibilityState();
}

class _HeatmapVisibilityState extends ConsumerState<_HeatmapVisibility> {
  /// initState 先拿：dispose 時不能 ref.read（Riverpod 3 會拋 StateError）
  late final MarketHeatmapNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(marketHeatmapProvider.notifier);
    ref.listenManual(appVisibilityProvider, (_, _) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() => _notifier.setVisible(
    TickerMode.of(context) && ref.read(appVisibilityProvider),
  );

  @override
  void dispose() {
    _notifier.setVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
