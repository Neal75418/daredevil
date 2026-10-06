/// 本地日期與 UTC 日期不同的一個時刻（驗「先轉本地再取日期」用）。
///
/// 時差為正：本地 00:00:30（UTC 還在前一天）；為負：本地 23:59:30（UTC 已是
/// 隔天）；UTC 時區回 null——驗不到，測試應 skip（CI 跑 UTC 會 skip）。
DateTime? crossDayLocal(int year, int month, int day) {
  final offset = DateTime(year, month, day, 12).timeZoneOffset;
  if (offset == Duration.zero) return null;
  return offset.isNegative
      ? DateTime(year, month, day, 23, 59, 30)
      : DateTime(year, month, day, 0, 0, 30);
}
