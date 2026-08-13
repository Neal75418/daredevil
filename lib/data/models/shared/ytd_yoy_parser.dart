/// 累計年增(%)的自洽解析(2026-08-13,月營收三來源共用)。
///
/// 政策與 MOPS CSV 單月欄的自洽檢核一致:API 同列給「當月累計/去年累計/
/// 前期比較增減(%)」,用前兩者重算第三者——欄序或語意哪天漂移,重算立刻
/// 對不上,**該欄設 null 不落庫**(單月欄不受影響,不整列拒收:累計欄壞
/// 不該拖累完好的單月資料)。
///
/// 回 null 的情況:任一輸入缺、去年累計 ≤ 0(新掛牌未滿年,除零)、
/// 重算與給定值差超過 [tolerancePp] 個百分點。
double? parseSelfCheckedYtdYoy({
  required double? ytdCurrent,
  required double? ytdPrior,
  required double? ytdPct,
  double tolerancePp = 0.5,
}) {
  if (ytdCurrent == null || ytdPrior == null || ytdPct == null) return null;
  if (ytdPrior <= 0) return null;
  final recomputed = (ytdCurrent - ytdPrior) / ytdPrior * 100;
  if ((recomputed - ytdPct).abs() > tolerancePp) return null;
  return ytdPct;
}
