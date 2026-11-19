import 'package:daredevil/core/constants/api_endpoints.dart';

/// 大盤熱力圖參數（設計見 `docs/plans/2026-10-07-market-heatmap-design.md`；
/// 圖上只畫市值前幾檔的部分見
/// `docs/plans/2026-11-19-market-heatmap-top30-design.md`）
abstract final class HeatmapParams {
  /// 不畫的產業：產業別含 `ETF`（上市 `ETF`、上櫃 `上櫃ETF`，與
  /// `isEtfIndustry` 同判準）或等於 [_depositaryReceipt]
  static bool isExcludedIndustry(String? industry) =>
      industry != null &&
      (industry.contains('ETF') || industry == _depositaryReceipt);

  static const String _depositaryReceipt = '存託憑證';

  /// 上櫃兩個股數來源最新一筆的差距上限（以較大的一方為分母），超過就不畫
  static const double shareMismatchRatio = 0.10;

  /// 色階分界，比的是 [roundPercent] 後的漲跌幅絕對值（%）：第 1 階 (0, 0.5)、
  /// 第 2 階 [0.5, 1.5)、…、第 6 階 ≥ 9.5；四捨五入後為 0 是平盤（第 0 階）
  static const List<double> stepBounds = [0.5, 1.5, 3.0, 5.0, 9.5];

  /// 漲跌幅（%）四捨五入到小數 2 位。分階（[stepOf]）與畫面顯示的數字都用
  /// 它，看到的數字與顏色才會是同一個值；浮點誤差也不會讓 9.499999… 掉到
  /// 前一階。
  static double roundPercent(double percent) => (percent * 100).round() / 100;

  /// 漲跌幅（%）對應的色階 0..6。[percent] 必須是有限值：NaN／Infinity 沒有
  /// 合理的色階，呼叫端應當成「無漲跌資料」。
  static int stepOf(double percent) {
    assert(percent.isFinite, '漲跌幅必須是有限值，得到 $percent');
    final abs = roundPercent(percent).abs();
    if (abs == 0) return 0;
    var step = 1;
    for (final bound in stepBounds) {
      if (abs >= bound) step++;
    }
    return step;
  }

  /// 圖上畫的檔數：每個市場市值最大的幾檔。不得超過 [liveTileLimit]，圖上
  /// 每一檔才都登記得到即時報價
  static const int topTileCount = 30;

  /// 即時登記的個股上限：報價中心兩批的檔數，扣掉該市場指數佔的一檔。圖上的
  /// 檔數（[topTileCount]）不超過它；登記清單另以它為保險上限
  static const int liveTileLimit = ApiEndpoints.misBatchSize * 2 - 1;

  /// 盤中一檔進入登記清單時，往前放寬多久內抓到的報價也算數。熱力圖頁可見時
  /// 只有它自己登記（被蓋住的頁面、沒在看的分頁都取消登記），報價中心一輪約
  /// 15 秒；放寬兩輪＝一輪加上約一輪的離開時間：離開熱力圖頁很快回來時，上
  /// 一輪抓到的價格照樣上色，更早抓到的仍當成未即時
  static const Duration liveRegistrationGrace = Duration(seconds: 30);

  /// 頁面可見期間比對內容指紋的間隔
  static const Duration fingerprintPollInterval = Duration(minutes: 1);

  /// 格子之間的間隔（露出頁面底色）
  static const double tileGap = 1.0;

  /// 格子字級的下限
  static const double labelFontSize = 11.0;

  /// 格子字級的上限：格子越大字越大，取「寬 ÷ [tileFontWidthRatio]」與
  /// 「高 ÷ [tileFontHeightRatio]」較小者，夾在 [labelFontSize]～這個值
  static const double tileFontSizeMax = 22.0;
  static const double tileFontWidthRatio = 8.0;
  static const double tileFontHeightRatio = 5.0;

  /// 格子文字左右各留的空白
  static const double textPadding = 2.0;

  /// 提示與指標的距離
  static const double tooltipOffset = 12.0;

  /// 圖例色塊的邊長
  static const double legendSwatchSize = 12.0;

  /// 格子小於這個寬高就不量文字（預篩；寫不寫以量出來的文字寬高為準）
  static const double tileTextMinWidth = 24.0;
  static const double tileTextMinHeight = 10.0;

  /// 格子短邊小於此值時照畫，但不回應點擊與滑鼠
  static const double minInteractiveSide = 4.0;
}
