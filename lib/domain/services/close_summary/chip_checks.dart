/// 收盤摘要的籌碼條件（v3 籌碼章與對做）。
///
/// 交易日以價格日線為準：某個價格日沒有該股的法人列，代表那天外資、投信都
/// 是 0（資料庫不存三方都是 0 的列），所以會中斷連買。
library;

import 'package:daredevil/core/constants/close_summary_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 外資或投信
enum ChipParty { foreign, trust }

/// 一檔股票在資料日的籌碼狀態
class ChipCheck {
  const ChipCheck({
    required this.foreignNetShares,
    required this.trustNetShares,
    required this.foreignStreak,
    required this.trustStreak,
    required this.sealedBy,
    required this.opposed,
  });

  /// 資料日外資買賣超（股）；沒有該股的法人列時為 0
  final double foreignNetShares;

  /// 資料日投信買賣超（股）；沒有該股的法人列時為 0
  final double trustNetShares;

  /// 外資連買天數為正、連賣為負，含資料日，不設下限；資料日為 0 時是 0
  final int foreignStreak;

  /// 投信連買天數為正、連賣為負，含資料日，不設下限；資料日為 0 時是 0
  final int trustStreak;

  /// 籌碼章成立的一方：資料日與前 2 個交易日每天買超都達到當天成交量的
  /// `CloseSummaryParams.chipMinVolumeShare`；兩方都成立取外資
  final ChipParty? sealedBy;

  /// 對做（v3 的單日大額反向）：籌碼章那 3 天裡，另一方有一天的賣超
  /// ≥ 籌碼章那一方 3 天的買超合計，也就是一天就賣掉對方三天買的量
  final bool opposed;

  bool get sealed => sealedBy != null;
}

/// [bars] 為升冪日線、最後一根是資料日。[institutionalReady] 為 false
/// （該股所屬市場資料日的法人還沒寫入）時回 null，不拿前一日頂替。
ChipCheck? checkChip({
  required List<DailyInstitutionalEntry> institutional,
  required List<DailyPriceEntry> bars,
  required bool institutionalReady,
}) {
  if (!institutionalReady || bars.isEmpty) return null;
  final byDate = {
    for (final row in institutional) DateContext.normalize(row.date): row,
  };

  double netOf(ChipParty party, DateTime date) {
    final row = byDate[DateContext.normalize(date)];
    if (row == null) return 0;
    return switch (party) {
      ChipParty.foreign => row.foreignNet ?? 0,
      ChipParty.trust => row.investmentTrustNet ?? 0,
    };
  }

  int streakOf(ChipParty party) {
    final last = netOf(party, bars.last.date);
    if (last == 0) return 0;
    final buying = last > 0;
    var count = 0;
    for (var i = bars.length - 1; i >= 0; i--) {
      final net = netOf(party, bars[i].date);
      if (net == 0 || (net > 0) != buying) break;
      count++;
    }
    return buying ? count : -count;
  }

  const days = CloseSummaryParams.chipStreakDays;
  final window = bars.length < days
      ? const <DailyPriceEntry>[]
      : bars.sublist(bars.length - days);

  bool sealedFor(ChipParty party) {
    if (window.isEmpty) return false;
    for (final bar in window) {
      final volume = bar.volume;
      final net = netOf(party, bar.date);
      if (volume == null ||
          net <= 0 ||
          net < volume * CloseSummaryParams.chipMinVolumeShare) {
        return false;
      }
    }
    return true;
  }

  final sealedBy = sealedFor(ChipParty.foreign)
      ? ChipParty.foreign
      : sealedFor(ChipParty.trust)
      ? ChipParty.trust
      : null;

  var opposed = false;
  if (sealedBy != null) {
    final other = sealedBy == ChipParty.foreign
        ? ChipParty.trust
        : ChipParty.foreign;
    final bought = window.fold<double>(
      0,
      (sum, bar) => sum + netOf(sealedBy, bar.date),
    );
    opposed = window.any((bar) {
      final net = netOf(other, bar.date);
      return net < 0 && -net >= bought;
    });
  }

  return ChipCheck(
    foreignNetShares: netOf(ChipParty.foreign, bars.last.date),
    trustNetShares: netOf(ChipParty.trust, bars.last.date),
    foreignStreak: streakOf(ChipParty.foreign),
    trustStreak: streakOf(ChipParty.trust),
    sealedBy: sealedBy,
    opposed: opposed,
  );
}
