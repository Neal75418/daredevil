/// 盤後資料是否已定案（設計見 docs/plans/2026-09-26-market-data-finality-design.md §4.1）
///
/// 交易所在收盤後一段時間內會更新當日數字（例如 17:30–18:00 才併入鉅額
/// 交易），而「隔天以後才抓到的值」經稽核全面與官方一致，所以只有抓取
/// 日期晚於資料日才算定案。
///
/// [fetchedAtTaipei] 是台北牆鐘時間（`AppClock.now()`）。這裡刻意只比
/// 年月日欄位、不做時區換算：兩個值都是以台北日曆記錄的，換算反而會在
/// 裝置時區不是台北時算錯。
bool isFetchFinal({
  required DateTime dataDate,
  required DateTime fetchedAtTaipei,
}) {
  final data = DateTime.utc(dataDate.year, dataDate.month, dataDate.day);
  final fetched = DateTime.utc(
    fetchedAtTaipei.year,
    fetchedAtTaipei.month,
    fetchedAtTaipei.day,
  );
  return fetched.isAfter(data);
}
