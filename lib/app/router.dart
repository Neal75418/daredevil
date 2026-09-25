import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/extensions/router_extensions.dart';

import 'package:daredevil/presentation/screens/alerts/alerts_screen.dart';
import 'package:daredevil/presentation/screens/onboarding/disclaimer_screen.dart';
import 'package:daredevil/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:daredevil/presentation/screens/industry/industry_overview_screen.dart';
import 'package:daredevil/presentation/screens/market/market_overview_screen.dart';
import 'package:daredevil/presentation/screens/news/news_screen.dart';
import 'package:daredevil/presentation/screens/portfolio/portfolio_tab.dart';
import 'package:daredevil/presentation/screens/scan/scan_screen.dart';
import 'package:daredevil/presentation/screens/settings/settings_screen.dart';
import 'package:daredevil/presentation/screens/comparison/comparison_screen.dart';
import 'package:daredevil/presentation/screens/calendar/event_calendar_screen.dart';
import 'package:daredevil/presentation/screens/institutional/institutional_ranking_screen.dart';
import 'package:daredevil/presentation/screens/quarterly/quarterly_report_overview_screen.dart';
import 'package:daredevil/presentation/screens/revenue/revenue_overview_screen.dart';
import 'package:daredevil/presentation/screens/short_sell/short_sell_ranking_screen.dart';
import 'package:daredevil/presentation/screens/industry/industry_eps_screen.dart';
import 'package:daredevil/presentation/screens/portfolio/position_detail_screen.dart';
import 'package:daredevil/presentation/screens/stock_detail/stock_detail_screen.dart';
import 'package:daredevil/presentation/screens/today/today_screen.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_screen.dart';
import 'package:daredevil/presentation/widgets/app_shell.dart';

/// 導航分支 key
final _todayNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'today');
final _scanNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'scan');
final _watchlistNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'watchlist',
);

/// 快取 onboarding 完成狀態，避免重複 async 讀取
bool _onboardingComplete = false;

/// 快取免責聲明同意狀態
bool _disclaimerAccepted = false;

/// 標記 [initOnboardingStatus] 是否已被呼叫過
bool _onboardingStatusInitialized = false;

/// 預載 onboarding 與免責同意狀態（須在 router 使用前呼叫）
Future<void> initOnboardingStatus() async {
  final prefs = await SharedPreferences.getInstance();
  _onboardingComplete = prefs.getBool(OnboardingScreen.completedKey) ?? false;
  _disclaimerAccepted = prefs.getBool(DisclaimerScreen.acceptedKey) ?? false;
  _onboardingStatusInitialized = true;
}

/// 標記 onboarding 已完成（更新快取 + 持久化）
Future<void> completeOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(OnboardingScreen.completedKey, true);
  _onboardingComplete = true;
}

/// 目前快取的免責同意狀態（供測試驗證 [initOnboardingStatus] 有讀到）
@visibleForTesting
bool get isDisclaimerAccepted => _disclaimerAccepted;

/// 記錄使用者已同意免責聲明（持久化 + 更新快取）。
///
/// 🚨 呼叫端必須 await 完才能 `go`：redirect 讀的是快取，先 go 會被
/// 踢回同意頁。
Future<void> acceptDisclaimer() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(DisclaimerScreen.acceptedKey, true);
  _disclaimerAccepted = true;
}

/// 進入 App 的閘門：引導 → 免責聲明同意 → 主畫面。
///
/// 🚨 免責同意是獨立旗標而非引導的一部分：既有安裝早已完成引導，
/// 若只放進引導頁，它們永遠不會看到、也不會按同意。
@visibleForTesting
String? resolveEntryRedirect({
  required bool onboardingComplete,
  required bool disclaimerAccepted,
  required String location,
}) {
  final String? gate = !onboardingComplete
      ? AppRoutes.onboarding
      : !disclaimerAccepted
      ? AppRoutes.disclaimer
      : null;
  if (gate != null) return location == gate ? null : gate;
  if (location == AppRoutes.onboarding || location == AppRoutes.disclaimer) {
    return AppRoutes.home;
  }
  return null;
}

/// App 路由設定
final router = GoRouter(
  initialLocation: AppRoutes.home,
  redirect: (context, state) {
    assert(
      _onboardingStatusInitialized,
      'initOnboardingStatus() must be awaited before router is used. '
      'Ensure main() calls await initOnboardingStatus() before _runApp().',
    );
    return resolveEntryRedirect(
      onboardingComplete: _onboardingComplete,
      disclaimerAccepted: _disclaimerAccepted,
      location: state.matchedLocation,
    );
  },
  routes: [
    // Onboarding（全螢幕，無底部導航）
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.disclaimer,
      name: 'disclaimer',
      builder: (context, state) => DisclaimerScreen(
        onAccept: () async {
          await acceptDisclaimer();
          if (context.mounted) context.go(AppRoutes.home);
        },
      ),
    ),
    // 含底部導航的 Shell 路由
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: [
        // 今日分頁
        StatefulShellBranch(
          navigatorKey: _todayNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.home,
              name: 'today',
              builder: (context, state) => const TodayScreen(),
            ),
          ],
        ),

        // 掃描分頁
        StatefulShellBranch(
          navigatorKey: _scanNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.scan,
              name: 'scan',
              builder: (context, state) => const ScanScreen(),
            ),
          ],
        ),

        // 自選股分頁
        StatefulShellBranch(
          navigatorKey: _watchlistNavigatorKey,
          routes: [
            GoRoute(
              path: AppRoutes.watchlist,
              name: 'watchlist',
              builder: (context, state) => const WatchlistScreen(),
            ),
          ],
        ),
      ],
    ),

    // 新聞（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.news,
      name: 'news',
      builder: (context, state) => const NewsScreen(),
    ),

    // 投資組合（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.portfolio,
      name: 'portfolio',
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text('portfolio.title'.tr())),
        body: const PortfolioTab(),
      ),
    ),

    // 個股詳情（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.stockDetailTemplate,
      name: 'stockDetail',
      builder: (context, state) {
        final symbol = state.pathParameters['symbol'] ?? '';
        return StockDetailScreen(symbol: symbol);
      },
    ),

    // 設定（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      builder: (context, state) => const SettingsScreen(),
    ),

    // 價格警示（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.alerts,
      name: 'alerts',
      builder: (context, state) => const AlertsScreen(),
    ),

    // 產業總覽（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.industry,
      name: 'industry',
      builder: (context, state) => const IndustryOverviewScreen(),
    ),

    // 大盤總覽（全螢幕，Shell 外；今日頁摘要條進入）
    GoRoute(
      path: AppRoutes.market,
      name: 'market',
      builder: (context, state) => const MarketOverviewScreen(),
    ),

    // 股票比較（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.compare,
      name: 'comparison',
      builder: (context, state) {
        return ComparisonScreen(initialSymbols: state.symbolsExtra);
      },
    ),

    // 持股詳情（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.positionDetailTemplate,
      name: 'positionDetail',
      builder: (context, state) {
        final symbol = state.pathParameters['symbol'] ?? '';
        return PositionDetailScreen(symbol: symbol);
      },
    ),

    // 行事曆（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.calendar,
      name: 'eventCalendar',
      builder: (context, state) => const EventCalendarScreen(),
    ),

    // 融券賣出排行（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.institutionalRanking,
      name: 'institutionalRanking',
      builder: (context, state) => const InstitutionalRankingScreen(),
    ),
    GoRoute(
      path: AppRoutes.revenueOverview,
      name: 'revenueOverview',
      builder: (context, state) => const RevenueOverviewScreen(),
    ),
    GoRoute(
      path: AppRoutes.quarterlyOverview,
      name: 'quarterlyOverview',
      builder: (context, state) => const QuarterlyReportOverviewScreen(),
    ),
    GoRoute(
      path: AppRoutes.shortSellRanking,
      name: 'shortSellRanking',
      builder: (context, state) => const ShortSellRankingScreen(),
    ),

    // 產業別 EPS 排名（全螢幕，Shell 外）
    GoRoute(
      path: AppRoutes.industryEps,
      name: 'industryEps',
      builder: (context, state) => const IndustryEpsScreen(),
    ),
  ],
);
