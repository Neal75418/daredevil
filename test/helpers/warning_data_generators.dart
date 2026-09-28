import 'package:daredevil/data/database/app_database.dart';

/// 測試資料生成工具 - Warning
///
/// 提供共用的警示測試資料產生器。

// ==========================================
// 日期計算工具
// ==========================================

// ==========================================
// Warning 資料生成
// ==========================================

/// 建立單一 TradingWarningEntry
TradingWarningEntry createTestWarning({
  required String symbol,
  required DateTime date,
  String warningType = 'ATTENTION',
  String? reasonCode,
  String? reasonDescription,
  String? disposalMeasures,
  DateTime? disposalStartDate,
  DateTime? disposalEndDate,
  bool isActive = true,
}) {
  return TradingWarningEntry(
    symbol: symbol,
    date: date,
    warningType: warningType,
    reasonCode: reasonCode,
    reasonDescription: reasonDescription,
    disposalMeasures: disposalMeasures,
    disposalStartDate: disposalStartDate,
    disposalEndDate: disposalEndDate,
    isActive: isActive,
  );
}

/// 建立注意股票警示
TradingWarningEntry createAttentionWarning({
  required String symbol,
  DateTime? date,
  String reasonDescription = '成交量異常',
}) {
  return createTestWarning(
    symbol: symbol,
    date: date ?? DateTime.now(),
    warningType: 'ATTENTION',
    reasonDescription: reasonDescription,
    isActive: true,
  );
}

/// 建立處置股票警示
TradingWarningEntry createDisposalWarning({
  required String symbol,
  DateTime? date,
  String disposalMeasures = '分盤交易',
  DateTime? disposalStartDate,
  DateTime? disposalEndDate,
}) {
  final now = date ?? DateTime.now();
  return createTestWarning(
    symbol: symbol,
    date: now,
    warningType: 'DISPOSAL',
    disposalMeasures: disposalMeasures,
    disposalStartDate: disposalStartDate ?? now,
    disposalEndDate: disposalEndDate ?? now.add(const Duration(days: 30)),
    isActive: true,
  );
}

// ==========================================
// Insider Holding 資料生成
// ==========================================
