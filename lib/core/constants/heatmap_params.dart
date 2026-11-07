import 'package:daredevil/core/constants/api_endpoints.dart';

/// 大盤熱力圖參數（設計見 `docs/plans/2026-10-07-market-heatmap-design.md`）
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

  /// 即時模式登記的個股上限：報價中心一輪兩批，扣掉該市場指數佔的一檔
  static const int liveTileLimit = ApiEndpoints.misBatchSize * 2 - 1;

  /// 頁面可見期間比對內容指紋的間隔
  static const Duration fingerprintPollInterval = Duration(minutes: 1);

  /// 產業區塊之間的間隔（頁面底色）；明顯比格子間隔寬，才看得出產業分界
  static const double industryGap = 4.0;

  /// 格子之間的間隔
  static const double tileGap = 1.0;

  /// 產業標題列高度
  static const double industryHeaderHeight = 16.0;

  /// 產業區塊（內縮後）寬、高都達到才畫標題列；寬 40 扣掉左右空白放得下
  /// 「兩個字＋…」（11px 字約 33px，標題放不下時名稱最短縮到這樣）
  static const double industryHeaderMinWidth = 40.0;
  static const double industryHeaderMinHeight = 40.0;

  /// 小格子合併：個股在產業內的預期面積（市值占比 × 格子區面積）小於
  /// 「[foldMinSide]² × [foldAspectAllowance]」就合併成一塊「其他」。24 是
  /// 無障礙規範的最小點擊目標；乘上形狀放寬倍數，長寬比 2 以內的格子短邊仍有
  /// 24。用預期面積而非排版後的邊長判斷，同樣資料每次結果相同。
  static const double foldMinSide = 24.0;
  static const double foldAspectAllowance = 2.0;

  /// 小產業合併：產業的預期面積（市值占比 × 圖區面積）小於
  /// 「[industryFoldMinSide]² × [foldAspectAllowance]」就在全市場圖上合成
  /// 一塊「其他 N 個產業」。放不下標題列的產業認不出是哪個產業，格子多半也
  /// 寫不下字；邊長＝標題列門檻加上四邊各半個產業間隔。
  static const double industryFoldMinSide =
      industryHeaderMinWidth + industryGap;

  /// 標題列的字級，也是格子字級的下限
  static const double labelFontSize = 11.0;

  /// 格子字級的上限：格子越大字越大，取「寬 ÷ [tileFontWidthRatio]」與
  /// 「高 ÷ [tileFontHeightRatio]」較小者，夾在 [labelFontSize]～這個值
  static const double tileFontSizeMax = 22.0;
  static const double tileFontWidthRatio = 8.0;
  static const double tileFontHeightRatio = 5.0;

  /// 文字左右各留的空白（格子文字、標題列）
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
