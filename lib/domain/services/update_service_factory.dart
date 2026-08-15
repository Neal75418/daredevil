import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/rss_parser.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
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
import 'package:daredevil/domain/services/rule_accuracy_service.dart';
import 'package:daredevil/domain/services/thesis/thesis_monitor_service.dart';
import 'package:daredevil/domain/services/update/news_mention_snapshot_service.dart';
import 'package:daredevil/domain/services/update_service.dart';
import 'package:daredevil/domain/services/update_service_deps.dart';

/// 集中組裝 [UpdateService] 與 10+ repository + RuleAccuracyService 依賴。
///
/// ## 動機
///
/// 過去 foreground (`updateServiceProvider` in providers.dart) 與 background
/// (`BackgroundUpdateService`) 兩條路徑各自手 wire 整套 repo + client +
/// service。任何 constructor 簽章變動需要兩處同步、容易漂移。已知案例：
///
/// - `analysisRepository` foreground 帶 `clock: appClockProvider`，
///   background 不帶（使用 default `SystemClock`）
/// - `fundamentalRepository` foreground 一度只給 finMindClient（修正後也
///   帶 twse/tpex），background 給齊
///
/// 抽出此 factory 後，新增/變動 repo 只需動一處。
///
/// ## 為什麼不是 Riverpod container
///
/// background 跑在 WorkManager 觸發的獨立 Dart isolate，ProviderContainer
/// 不能跨 isolate 共享；要重設一份 container 工程量遠大於 factory。
class UpdateServiceFactory {
  const UpdateServiceFactory._();

  /// 用 raw 依賴（DB + clients + parser）構造完整 UpdateService。
  ///
  /// caller 負責 client 生命週期（factory 不接管 close）。
  /// [clock] 預設 [SystemClock]，測試或 background 可注入 fake clock。
  /// [ruleAccuracyService] 預設 inline 構造；foreground 想共用 Riverpod
  /// 既有 instance 可從外部注入。
  static UpdateService build({
    required AppDatabase database,
    required FinMindClient finMindClient,
    required TwseClient twseClient,
    required TpexClient tpexClient,
    required TdccClient tdccClient,
    required RssParser rssParser,
    AppClock clock = const SystemClock(),
    RuleAccuracyService? ruleAccuracyService,
  }) {
    final stockRepo = StockRepository(
      database: database,
      finMindClient: finMindClient,
      twseClient: twseClient,
    );
    final priceRepo = PriceRepository(
      database: database,
      finMindClient: finMindClient,
      twseClient: twseClient,
      tpexClient: tpexClient,
      clock: clock,
    );
    final newsRepo = NewsRepository(
      database: database,
      rssParser: rssParser,
      twseClient: twseClient,
      clock: clock,
    );
    final analysisRepo = AnalysisRepository(database: database, clock: clock);
    final institutionalRepo = InstitutionalRepository(
      database: database,
      finMindClient: finMindClient,
      twseClient: twseClient,
      tpexClient: tpexClient,
      clock: clock,
    );
    final marketDataRepo = MarketDataRepository(
      database: database,
      finMindClient: finMindClient,
      clock: clock,
    );
    final tradingRepo = TradingRepository(
      database: database,
      twseClient: twseClient,
      tpexClient: tpexClient,
      clock: clock,
    );
    final shareholdingRepo = ShareholdingRepository(
      database: database,
      finMindClient: finMindClient,
      twseClient: twseClient,
      clock: clock,
    );
    final fundamentalRepo = FundamentalRepository(
      mops: MopsClient(),
      db: database,
      finMind: finMindClient,
      twse: twseClient,
      tpex: tpexClient,
      clock: clock,
    );
    final insiderRepo = InsiderRepository(
      database: database,
      twseClient: twseClient,
      tpexClient: tpexClient,
      clock: clock,
    );
    final warningRepo = WarningRepository(
      database: database,
      twseClient: twseClient,
      tpexClient: tpexClient,
      clock: clock,
    );

    return UpdateService(
      database: database,
      repositories: UpdateRepositories(
        stock: stockRepo,
        price: priceRepo,
        news: newsRepo,
        analysis: analysisRepo,
        institutional: institutionalRepo,
        marketData: marketDataRepo,
        trading: tradingRepo,
        shareholding: shareholdingRepo,
        fundamental: fundamentalRepo,
        insider: insiderRepo,
        warning: warningRepo,
      ),
      clients: UpdateClients(
        twse: twseClient,
        tpex: tpexClient,
        tdcc: tdccClient,
        finMind: finMindClient,
      ),
      services: UpdateServices(
        ruleAccuracy:
            ruleAccuracyService ?? RuleAccuracyService(database: database),
        thesisMonitor: ThesisMonitorService(database: database),
        newsMentionSnapshot: NewsMentionSnapshotService(
          database: database,
          newsRepository: newsRepo,
          clock: clock,
        ),
      ),
      clock: clock,
    );
  }
}
