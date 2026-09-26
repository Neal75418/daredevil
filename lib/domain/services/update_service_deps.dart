import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/data/repositories/market_data_repository.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/stock_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rule_accuracy_service.dart';
import 'package:daredevil/domain/services/thesis/thesis_monitor_service.dart';
import 'package:daredevil/domain/services/scoring_service.dart';
import 'package:daredevil/domain/services/update/market_day_refetcher.dart';
import 'package:daredevil/domain/services/update/news_mention_snapshot_service.dart';

/// [UpdateService] 的 Repository 依賴群組
class UpdateRepositories {
  const UpdateRepositories({
    required this.stock,
    required this.price,
    required this.news,
    required this.analysis,
    this.institutional,
    this.marketData,
    this.trading,
    this.shareholding,
    this.fundamental,
    this.insider,
    this.warning,
  });

  final StockRepository stock;
  final PriceRepository price;
  final NewsRepository news;
  final AnalysisRepository analysis;
  final InstitutionalRepository? institutional;
  final MarketDataRepository? marketData;
  final TradingRepository? trading;
  final ShareholdingRepository? shareholding;
  final FundamentalRepository? fundamental;
  final InsiderRepository? insider;
  final WarningRepository? warning;
}

/// [UpdateService] 的外部 API Client 依賴
class UpdateClients {
  const UpdateClients({this.twse, this.tpex, this.tdcc, this.finMind});

  final TwseClient? twse;
  final TpexClient? tpex;
  final TdccClient? tdcc;
  final FinMindClient? finMind;
}

/// [UpdateService] 的可選 Service 覆寫
class UpdateServices {
  const UpdateServices({
    this.analysis,
    this.ruleEngine,
    this.scoring,
    this.ruleAccuracy,
    this.thesisMonitor,
    this.newsMentionSnapshot,
    this.marketDayRefetcher,
  });

  final AnalysisService? analysis;
  final RuleEngine? ruleEngine;
  final ScoringService? scoring;
  final RuleAccuracyService? ruleAccuracy;

  /// 釘選論點監控（出場層 Phase 2）。null = 不檢查（測試預設）。
  final ThesisMonitorService? thesisMonitor;

  /// 每日提及數快照（新聞熱度發現層）。null = 不快照（測試預設）。
  final NewsMentionSnapshotService? newsMentionSnapshot;

  /// 未定案盤後資料重抓（spec §4.5(b)）。null 時由 [UpdateService] 用真實
  /// 依賴建立；測試注入用。
  final MarketDayRefetcher? marketDayRefetcher;
}
