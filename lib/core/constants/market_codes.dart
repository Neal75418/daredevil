/// 台灣股票市場代碼常數
///
/// 用於區分上市（TWSE）與上櫃（TPEx）股票。
/// 所有市場代碼比對應使用此常數，避免散落的魔術字串。
abstract final class MarketCode {
  /// 台灣證券交易所（上市）
  static const String twse = 'TWSE';

  /// 證券櫃檯買賣中心（上櫃）
  static const String tpex = 'TPEx';
}

/// 市場代碼 → 顯示標籤的 i18n key（`marketOverview.twse` / `marketOverview.tpex`）
///
/// 集中「代碼→key」判斷，避免多處各自重複 `market == MarketCode.twse ? ... :
/// ...` 三元判斷（曾同時出現在 `MarketDashboard._buildMarketHeader` 與
/// `SentimentGaugeSection` 兩處）。呼叫端仍需自行 `.tr()` — 本函式不依賴
/// `easy_localization`，保持 `core/constants` 層不引入 i18n/presentation 依賴。
String marketLabelKey(String market) {
  return market == MarketCode.twse
      ? 'marketOverview.twse'
      : 'marketOverview.tpex';
}

/// 判定「完整覆蓋交易日」的最低個股報價數門檻。
///
/// 本地資料庫部分日子僅同步候選子集（約半市場：TWSE ~531 / TPEx ~338），
/// 完整日為 TWSE ~1220 / TPEx ~876。市場 rolling 統計（成交額均量、情緒
/// 量能）若混入半套日會使均值嚴重失真（曾出現假性「5日均 +278%」），故
/// 須濾除半套日。門檻 700 介於半套（≤531）與完整（≥876）之間，可同時
/// 乾淨切開上市與上櫃兩市場。
const int kMinSymbolsForCompleteTradingDay = 700;

/// 52 週新高/新低的回看交易日數（一年約 252 個交易日）。
///
/// 用於 [getNewHighLowCountsByMarket]：以個股今日收盤對比 trailing-252
/// 日的最高/最低收盤，判定是否創 52 週新高（close ≥ 252 日內最高）或
/// 新低（close ≤ 252 日內最低），為廣度趨勢（market breadth trend）的
/// 經典指標。窗口固定 252，不受半套日影響（高低點本質上仍有效）。
const int kNewHighLowLookbackDays = 252;

/// 認列「52 週新高/新低」所需的最低歷史交易日數。
///
/// 用於 [getNewHighLowCountsByMarket]：window function 只比對 DB 內實際
/// 存在的交易日，故薄歷史個股（如新上市、僅 30~120 個交易日）會被誤判為
/// 創 52 週新高/新低——它根本沒交易滿 52 週。要求個股歷史筆數 ≥ 此門檻
/// 才納入計數，可剔除這類 over-count（DB 實測：要求 ≥200 後 TWSE 新低
/// 28→11、TPEx 新低 54→12）。設 200 而非滿 252，容許假日/停牌造成的少數
/// 缺漏，仍確保涵蓋約一年的交易歷史。
const int kNewHighLowMinHistoryDays = 200;

/// 產業表現統計納入排名所需的最低個股數。
///
/// 用於 [getIndustrySummaryByMarket]：單一/雙股「產業」（如 TPEx 電器電纜
/// 僅 1 檔風青）的平均漲跌幅就是那一兩檔的個別波動，不構成有意義的類股
/// 平均，卻會憑單檔接近漲停的走勢竄上排行第一。要求產業內個股數 ≥ 此門檻
/// 才納入，排除此類雜訊（DB 實測：各市場僅 1 個 <3 股的產業，恰為單股產業，
/// ≥3 門檻附帶損害最小）。
const int kIndustryMinStockCount = 3;

/// AD 騰落線（Advance-Decline Line）累積所回看的完整覆蓋交易日數。
///
/// 騰落線為每日 (上漲 − 下跌) 家數的累積running sum，需足夠天數才能呈現
/// 有意義的廣度趨勢 / 背離訊號。實際取得天數受完整覆蓋日濾除影響（半套日
/// 會被 [getRecentAdvanceDeclineByMarket] 排除），故設 60 個交易日為窗口。
const int kAdLineLookbackDays = 60;
