import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/industry_names.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/request_deduplicator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/repositories/stock_repository.dart';

/// 股票主檔 Repository
class StockRepository implements IStockRepository {
  StockRepository({
    required AppDatabase database,
    required FinMindClient finMindClient,
    required TwseClient twseClient,
  }) : _db = database,
       _client = finMindClient,
       _twseClient = twseClient;

  final AppDatabase _db;
  final FinMindClient _client;

  /// 上市官方產業別來源（t187ap03_L）。
  ///
  /// **required(2026-08-02)**:原為 optional「測試便利」,結果
  /// update_service_factory 這個第三建構點漏傳、null 靜默跳過——更新
  /// 管線的官方覆蓋+殭屍清理從未執行,且無任何 log(三輪 force 實機
  /// 才定位)。改 required 讓「新建構點漏傳」直接編譯失敗,不再靠
  /// 人肉掃描;測試注入 mock 並 stub 空 map 即得舊 fallback 行為。
  final TwseClient _twseClient;

  /// Request deduplicator for getAllStocks
  final _stockListDedup = RequestDeduplicator<List<StockMasterEntry>>();

  /// 取得所有上市中的股票
  ///
  /// 使用 Request Deduplication 防止同時多次查詢
  @override
  Future<List<StockMasterEntry>> getAllStocks() {
    return _stockListDedup.call('all_stocks', () => _db.getAllActiveStocks());
  }

  /// 依代碼取得股票
  @override
  Future<StockMasterEntry?> getStock(String symbol) {
    return _db.getStock(symbol);
  }

  /// 取得產業股票數量統計
  @override
  Future<Map<String, int>> getIndustryStockCounts() {
    return _db.getIndustryStockCounts();
  }

  /// 從 FinMind API 同步股票清單
  ///
  /// 建議定期執行（如每週一次）以更新股票清單
  /// 僅同步有效股票代碼（4 位數一般股票 + 00 開頭 ETF）
  @override
  Future<int> syncStockList() async {
    try {
      final stocks = await _client.getStockList();

      // TWSE 官方產業別（免額度）：FinMind 上市電子股多塌陷泛用
      // 「電子工業」（2026-08-01 實測 305 檔 active，台積電在內——
      // 上市半導體/光電細分卡整組失真），官方 t187ap03_L 才有細分碼。
      // fail-soft：抓不到就沿用 FinMind 分類，同步不中斷。
      var officialCodes = const <String, String>{};
      try {
        officialCodes = await _twseClient.fetchIndustryCodes();
      } catch (e) {
        AppLogger.warning('StockRepo', 'TWSE 官方產業別取得失敗，沿用 FinMind 分類', e);
      }

      // 過濾有效股票代碼：4 位數字（一般股票）或 00 開頭（ETF）
      // 排除 6 位數權證、TDR 等非股票代碼
      final validStockPattern = RegExp(r'^(\d{4}|00\d{3,4})$');

      // FinMind 同一 symbol 可能回多列（細分＋泛用「電子工業」各一），
      // 直灌 upsert 會讓贏家隨回傳順序漂移——去重且細分優先。
      final bySymbol = <String, FinMindStockInfo>{};
      for (final stock in stocks) {
        if (!validStockPattern.hasMatch(stock.stockId)) continue;
        final prev = bySymbol[stock.stockId];
        final prevGeneric = prev?.industryCategory == '電子工業';
        final currGeneric = stock.industryCategory == '電子工業';
        // 勝者規則(2026-08-05 複審補定序):細分 > 泛用;兩列皆細分時
        // 取分類名字典序小者——原本「首列贏」讓勝者隨 API 回傳順序
        // 週際漂移,產業歸屬跳動。
        final replace =
            prev == null ||
            (prevGeneric && !currGeneric) ||
            (!prevGeneric &&
                !currGeneric &&
                stock.industryCategory.compareTo(prev.industryCategory) < 0);
        if (replace) {
          bySymbol[stock.stockId] = stock;
        }
      }

      // 殭屍清理:FinMind 持續回傳已下市股(華亞科 2016 下市仍 type=twse,
      // 2026-08-01 實測 135 檔 active 殭屍、全部近月零價格),
      // deactivateStocksNotIn 永遠排除不到——官方名單缺席=下市。
      // 三重防護:(1) sanity floor 擋部分回應的大規模誤殺;
      // (2) DR(91xx)自校準守衛——官方名單實測涵蓋交易中 DR(9103/9105
      // 在冊,欄位名「TDR原股發行股數」為結構性佐證),但仍以「當輪名單
      // 含任一 91xx」為前提,上游哪天移除 DR 涵蓋即自動跳過;
      // (3) ETF(00 開頭)/上櫃不在官方公司名單範圍,一律不清。
      // 重上市自癒:回到名單即恢復 active(upsert 覆寫)。
      final officialUsable =
          officialCodes.length >= ApiConfig.twseOfficialListSanityFloor;
      // 名冊縮水警報(2026-08-15 改參考點):比對**DB 既有的存活規模**,
      // 而非絕對 floor。floor 是災難下限,不是正常值——拿它當參考點會
      // (1) 在 floor 貼近實際家數後必然響、噪音化;(2) 對上面註解自承的
      // 「floor 過了但名單仍缺漏」盲區完全無感,而那才是缺席者被誤判
      // 下市的實際成因。DB 本身就是上一輪的結果,不必另外持久化 state。
      if (officialUsable) {
        final known = await _db.countActiveOfficialUniverse();
        final threshold = known * ApiConfig.twseOfficialRosterShrinkWarnRatio;
        if (known > 0 && officialCodes.length < threshold) {
          final shrink = (1 - officialCodes.length / known) * 100;
          AppLogger.warning(
            'StockRepo',
            '官方名冊 ${officialCodes.length} 家，較既有 $known 家縮水 '
                '${shrink.toStringAsFixed(1)}% —— 名單雖過 sanity floor '
                '(${ApiConfig.twseOfficialListSanityFloor})，缺席者仍會被判下市',
          );
        }
      }
      final officialCoversDr = officialCodes.keys.any(
        (s) => s.startsWith('91'),
      );

      // 三態判定(2026-08-05 複審修正):原本「跳過清理」被實作成
      // 「寫入 isActive=true」——fail-soft/floor/DR 守衛任一觸發時,
      // 上一輪已停用的 135 檔殭屍整輪復活(死股無成交,價格步救不回,
      // 持續到下次成功輪最長一週)。防護的正確語意是**保持現狀**:
      // 未知一律回 null → companion 該欄 absent → Drift DoUpdate 不寫入。
      // industry 同理:官方權威範圍內狀態未知時不得以 FinMind taxonomy
      // 降級覆寫上一輪的官方分類(產業卡組成會週際翻覆)。
      //
      // 官方權威範圍=上市 4 碼非 ETF;範圍外(上櫃/ETF)的存活語意
      // 仍是「FinMind 名單有=活」(其停用由 deactivateStocksNotIn 承接)。
      bool inOfficialUniverse(FinMindStockInfo stock) {
        final id = stock.stockId;
        return stock.market == MarketCode.twse &&
            id.length == 4 &&
            !id.startsWith('00');
      }

      // true=存活(自癒復活)、false=下市、null=未知(不寫入)
      bool? officialVerdict(FinMindStockInfo stock) {
        if (!inOfficialUniverse(stock)) return true;
        if (!officialUsable) return null;
        final id = stock.stockId;
        if (id.startsWith('91') && !officialCoversDr) return null;
        return officialCodes.containsKey(id) ? true : false;
      }

      final delisted = <String>[];
      final entries = bySymbol.values.map((stock) {
        final verdict = officialVerdict(stock);
        if (verdict == false) delisted.add(stock.stockId);

        final Value<String> industryValue;
        if (!inOfficialUniverse(stock)) {
          industryValue = Value(_normalizeIndustry(stock.industryCategory));
        } else if (verdict == null) {
          industryValue = const Value.absent();
        } else {
          industryValue = Value(
            IndustryNames.nameForTwseCode(officialCodes[stock.stockId] ?? '') ??
                _normalizeIndustry(stock.industryCategory),
          );
        }

        return StockMasterCompanion.insert(
          symbol: stock.stockId,
          name: stock.stockName,
          market: stock.market,
          industry: industryValue,
          isActive: verdict == null ? const Value.absent() : Value(verdict),
        );
      }).toList();

      if (delisted.isNotEmpty) {
        AppLogger.info(
          'StockRepo',
          '官方名單缺席標記下市: ${delisted.length} 檔'
              '(如 ${delisted.take(5).join(", ")})',
        );
      }

      // upsert + deactivate 應為原子操作，避免中途失敗造成不一致
      int deactivated = 0;
      await _db.transaction(() async {
        await _db.upsertStocks(entries);

        // 將不在 API 回傳清單中的股票標記為下市
        final activeSymbols = entries.map((e) => e.symbol.value).toSet();
        deactivated = await _db.deactivateStocksNotIn(activeSymbols);
      });
      if (deactivated > 0) {
        AppLogger.info('StockRepo', '標記 $deactivated 檔股票為下市');
      }

      return entries.length;
    } on RateLimitException catch (e) {
      AppLogger.warning('StockRepo', '股票清單同步觸發 API 速率限制', e);
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync stock list', e);
    }
  }

  /// 正規化產業名稱（FinMind API 回傳的名稱有不一致）
  ///
  /// 例如 TPEx 同一產業可能出現：「其他電子業」與「其他電子類」、
  /// 「居家生活」與「居家生活類」等重複命名。
  /// 對照表定義於 [IndustryNames.normalizationMap]。
  static String _normalizeIndustry(String raw) => IndustryNames.normalize(raw);

  /// 依名稱或代碼搜尋股票（Database 層級過濾）
  @override
  Future<List<StockMasterEntry>> searchStocks(String query) {
    return _db.searchStocks(query);
  }

  /// 依市場篩選股票（Database 層級過濾）
  @override
  Future<List<StockMasterEntry>> getStocksByMarket(String market) {
    return _db.getStocksByMarket(market);
  }
}
