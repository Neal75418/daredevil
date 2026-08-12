import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/models/industry_ranking.dart';
import 'package:daredevil/domain/services/analysis/industry_ranking_service.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 族群排行（今日頁族群 section），family 參數 = 動能視窗（今日/20日/5日）
///
/// 全市場選定視窗動能中位數 + 外資/投信近 3 交易日方向，動能 DESC 取前
/// [SectorParams.rankingTopN]。純 DB 讀取、無 API 呼叫；資料更新後由
/// [dataUpdateEpochProvider] 觸發重算。各視窗各自快取（family），
/// 切換不重複查 DB。
final industryRankingProvider =
    FutureProvider.family<List<IndustryRanking>, RankingWindow>((
      ref,
      window,
    ) async {
      ref.watch(dataUpdateEpochProvider);

      final db = ref.read(databaseProvider);
      final marketRepo = ref.read(marketDataRepositoryProvider);

      final latestDate = await marketRepo.getLatestDataDate();
      if (latestDate == null) return const [];
      final analysisDate = DateContext.normalize(latestDate);

      final priceHistories = await db.getAllPricesInRange(
        startDate: analysisDate.subtract(
          const Duration(days: SectorParams.rankingHistoryCalendarDays),
        ),
        endDate: analysisDate,
      );

      final stocks = await db.getAllActiveStocks();

      // 法人近 3 交易日：回看 20 日曆天（CNY 連假 margin，見常數 doc）
      final institutional = await db.getAllInstitutionalInRange(
        startDate: analysisDate.subtract(
          const Duration(days: SectorParams.rankingInstitutionalCalendarDays),
        ),
        endDate: analysisDate,
      );

      // 法人佔比的分母：與法人窗同長（rankingInstitutionalDays 個交易日）的
      // 成交量。priceHistories 已含 volume，不需另外查。
      final volumeBySymbol = <String, double>{};
      for (final e in priceHistories.entries) {
        final recent = e.value.reversed
            .take(SectorParams.rankingInstitutionalDays)
            .toList();
        if (recent.length < SectorParams.rankingInstitutionalDays) continue;
        var v = 0.0;
        var complete = true;
        for (final p in recent) {
          final vol = p.volume;
          if (vol == null) {
            complete = false;
            break;
          }
          v += vol;
        }
        if (complete) volumeBySymbol[e.key] = v;
      }

      return IndustryRankingService().rank(
        priceHistories: priceHistories,
        industries: {for (final s in stocks) s.symbol: s.industry},
        names: {for (final s in stocks) s.symbol: s.name},
        institutionalHistories: institutional,
        window: window,
        volumeBySymbol: volumeBySymbol,
        marketReturnPct: await _marketReturnPct(db, window),
      );
    });

/// 族群「轉向」——比較 20 日與 5 日的名次,而非水準值。
///
/// 與 [industryRankingProvider] 共用同一份 DB 讀取邏輯,但**不傳法人**:
/// 轉向卡片刻意不顯示法人佔比(版面已有躍升、兩窗口報酬、強者榜檔數,
/// 再加會爆炸),法人留在點進去的 sheet 裡。少查一次 DB。
///
/// 註:`rankRotation` 內部會對同一份 priceHistories 跑兩次 `rank()`,
/// 那是純函數運算,無額外 DB 往返。
final industryRotationProvider = FutureProvider<List<IndustryRotation>>((
  ref,
) async {
  ref.watch(dataUpdateEpochProvider);

  final db = ref.read(databaseProvider);
  final marketRepo = ref.read(marketDataRepositoryProvider);

  final latestDate = await marketRepo.getLatestDataDate();
  if (latestDate == null) return const [];
  final analysisDate = DateContext.normalize(latestDate);

  try {
    final priceHistories = await db.getAllPricesInRange(
      startDate: analysisDate.subtract(
        const Duration(days: SectorParams.rankingHistoryCalendarDays),
      ),
      endDate: analysisDate,
    );
    final stocks = await db.getAllActiveStocks();
    return IndustryRankingService().rankRotation(
      priceHistories: priceHistories,
      industries: {for (final s in stocks) s.symbol: s.industry},
      names: {for (final s in stocks) s.symbol: s.name},
    );
  } catch (e, st) {
    AppLogger.error('IndustryRotation', '族群轉向計算失敗', e, st);
    return const [];
  }
});

/// 大盤（加權指數）在**與族群同一視窗**的報酬（%），供超額報酬使用。
///
/// 口徑必須與 `PriceCalculator.ret20d` / `ret5d` 一致：取最新收盤與第
/// 21／6 筆前收盤相比。差一格會讓超額值系統性偏移。
///
/// 查不到足夠指數歷史時回 null——caller 據此不顯示超額，不得當成 0
/// （0 等於宣稱「大盤沒漲跌」，把缺資料講成事實）。
Future<double?> _marketReturnPct(AppDatabase db, RankingWindow window) async {
  final need = window.minHistoryRows;
  try {
    final hist = await db.getIndexHistoryBatch([
      MarketIndexNames.taiex,
    ], days: SectorParams.rankingHistoryCalendarDays);
    final rows = hist[MarketIndexNames.taiex];
    if (rows == null || rows.length < need) return null;
    final sorted = rows.toList()..sort((a, b) => a.date.compareTo(b.date));
    final latest = sorted.last.close;
    final old = sorted[sorted.length - need].close;
    if (old == 0) return null;
    return (latest - old) / old * 100;
  } catch (e) {
    AppLogger.warning('IndustryRankingProvider', '載入大盤同窗報酬失敗', e);
    return null;
  }
}
