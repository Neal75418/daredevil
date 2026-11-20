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
import 'package:daredevil/presentation/providers/heatmap_live_provider.dart';
import 'package:daredevil/presentation/providers/market_heatmap_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_legend.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_text.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_view.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

/// 大盤熱力圖：上市、上櫃各一張，畫該市場市值最大的幾檔，面積是市值、顏色
/// 是當日漲跌（盤中與收盤後、盤後資料寫入前用即時報價上色，見
/// [heatmapLiveProvider]）。從大盤總覽頁標題列進入。
class MarketHeatmapScreen extends ConsumerStatefulWidget {
  const MarketHeatmapScreen({super.key});

  /// 指數列下方的狀態行（即時時段是熱力圖的即時狀態，其餘是指數的狀態）
  @visibleForTesting
  static const statusLineKey = ValueKey('marketHeatmap.statusLine');

  @override
  ConsumerState<MarketHeatmapScreen> createState() =>
      _MarketHeatmapScreenState();
}

class _MarketHeatmapScreenState extends ConsumerState<MarketHeatmapScreen> {
  /// 市場代碼與市場名稱的翻譯 key（切換鈕與圖例共用）
  static const _marketLabelKeys = [
    (MarketCode.twse, 'marketOverview.twse'),
    (MarketCode.tpex, 'marketOverview.tpex'),
  ];

  HeatmapPaintLabels? _labels;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 依語系建一次並保存；語系換了換一份帶新語系的，painter 才重建描述
    final locale = Localizations.localeOf(context);
    if (_labels?.locale != locale) {
      _labels = HeatmapPaintLabels(
        locale: locale,
        tileSemantics: _tileSemantics,
      );
    }
  }

  void _selectMarket(String market) =>
      ref.read(heatmapSelectionProvider.notifier).selectMarket(market);

  void _openStock(String symbol) => context.push(AppRoutes.stockDetail(symbol));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marketHeatmapProvider);
    final overview = ref.watch(marketOverviewProvider);
    final live = ref.watch(marketLiveIndicesProvider);
    final market = ref.watch(heatmapSelectionProvider);
    final view = ref.watch(heatmapLiveProvider);
    final data = view.data;
    return Scaffold(
      appBar: AppBar(
        title: Text('marketHeatmap.title'.tr()),
        actions: [
          _marketSelector(market),
          const SizedBox(width: DesignTokens.spacing8),
        ],
      ),
      // 登記的清單由 provider 交給報價中心：App 看不見時畫面不重畫，清單照樣
      // 跟著換（收盤後拿到報價的移出）
      body: LiveQuoteScope.listen(
        source: heatmapRegistrationsProvider,
        // 包住所有狀態：空狀態、錯誤卡片也要輪詢，才等得到背景的第一次寫入
        child: _HeatmapVisibility(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IndexHeader(
                market: market,
                overview: overview,
                live: live,
                dataDate: data?.dataDate,
                // 即時時段（含停市日退回）指數下方改寫熱力圖的即時狀態
                liveStatus: view.mode == null
                    ? null
                    : heatmapLiveStatusText(view),
                // 圖用即時上色時右側的「M/D 收盤」不是格子的日期；停市日
                // 退回正式資料時保留（看得出顏色是哪天的）
                showCloseOf: data?.liveMode == null,
              ),
              Expanded(child: _content(state, market, data)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
    MarketHeatmapState state,
    String market,
    HeatmapMarketData? data,
  ) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (data != null) {
      final marketLabelKey = _marketLabelKeys
          .firstWhere((entry) => entry.$1 == market)
          .$2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacing16,
              vertical: DesignTokens.spacing4,
            ),
            child: HeatmapLegend(
              tileCount: data.tiles.length,
              marketLabel: marketLabelKey.tr(),
              coverage: data.capCoverage,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing8,
                vertical: DesignTokens.spacing4,
              ),
              child: HeatmapView(
                data: data,
                onTileTap: _openStock,
                labels: _labels!,
                uncategorizedLabel: 'marketHeatmap.uncategorized'.tr(),
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
    if (state.failedMarkets.contains(market)) {
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
  Widget _marketSelector(String selected) => SegmentedButton<String>(
    showSelectedIcon: false,
    segments: [
      for (final (market, key) in _marketLabelKeys)
        ButtonSegment(
          value: market,
          label: Text(
            key.tr(),
            style: const TextStyle(fontSize: DesignTokens.fontSizeSm),
          ),
        ),
    ],
    selected: {selected},
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
      namedArgs: {'name': tile.name, 'reason': heatmapHollowReasonText(reason)},
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
    required this.liveStatus,
    required this.showCloseOf,
  });

  final String market;
  final MarketOverviewState overview;
  final MarketLiveIndices live;
  final DateTime? dataDate;

  /// 即時時段的狀態行（見 [heatmapLiveStatusText]；空字串是還沒有狀態：不寫
  /// 字，但先留一行）；這時指數列下方不寫指數自己的狀態與「指數為 M/D 收盤」
  /// （同一件事不寫兩次，收盤後總覽已有今天的指數時也不會寫出「指數為今天
  /// 收盤」）。不在即時時段為 null，沒有狀態時不留行
  final String? liveStatus;

  /// 右側寫格子的日期「M/D 收盤」
  final bool showCloseOf;

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
    final statusStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // 狀態行與佔位共用固定行高：空字串的行高只看主字型，有字的行還看備用
    // 字型（中文），系統字級不是 1 時兩者會差 1px
    final statusStrut = statusStyle == null
        ? null
        : StrutStyle.fromTextStyle(statusStyle, forceStrutHeight: true);
    final shown = live.byMarket[market];
    final index = shown?.index ?? heroIndexOf(overview, market);
    final label =
        (market == MarketCode.twse
                ? 'marketOverview.summary.taiex'
                : 'marketOverview.summary.tpex')
            .tr();
    final date = dataDate;
    final String? statusText;
    if (liveStatus case final text?) {
      statusText = text.isEmpty ? null : text;
    } else {
      // 即時報價的狀態優先；否則指數比格子新時說明指數是哪天的收盤（右側的
      // 「M/D 收盤」是格子的日期）
      final closeOf = index == null || date == null
          ? null
          : indexCloseOfDate(
              index: index,
              isLive: shown?.isLive ?? false,
              compareDate: date,
            );
      statusText =
          shown?.statusText ??
          (closeOf == null ? null : indexCloseOfText(closeOf));
    }
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
              if (date != null && showCloseOf)
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
              key: MarketHeatmapScreen.statusLineKey,
              // 窄螢幕最多兩行：暫停、限流放在句首，截掉的是後面的進度
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: statusStyle,
              strutStyle: statusStrut,
            )
          else if (liveStatus != null)
            // 即時時段先佔一行：第一輪報價回來、狀態行出現時圖區不變矮，
            // 格子不重排
            Text('', style: statusStyle, strutStyle: statusStrut),
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
