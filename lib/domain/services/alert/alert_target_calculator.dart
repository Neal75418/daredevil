import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 計算用的最小日線單位(只取提醒需要的三個欄位)
class Ohlc {
  const Ohlc({required this.high, required this.low, required this.close});

  final double high;
  final double low;
  final double close;
}

/// 提醒種類。
///
/// 刻意**不含季線**:v3.3 無對應動作、與 8 日時間停損的時間尺度不匹配
/// (2026-08-07 設計討論)。突破月線的語意是「**回榜資格**」而非進場訊號
/// ——L1 入榜條件本來就寫著「站上 20MA」。
enum AlertKind {
  /// 跌破 5 日線——強勢股第一道撐
  breakBelowMa5,

  /// 跌破 10 日線——結構壞
  breakBelowMa10,

  /// 跌破月線——L1 除名線
  breakBelowMa20,

  /// 突破月線——回榜資格(非進場訊號)
  breakAboveMa20,

  /// 突破 20 日高——結構 C 觸發線
  breakAbove20DayHigh,

  /// 跌破守門價(k×ATR)——v3.3 §4.1 的停損線
  stopGate,

  /// 使用者自訂價位
  custom,
}

/// 一個觸發價與它的方向
class AlertTarget {
  const AlertTarget({required this.price, required this.isUpward});

  final double price;

  /// true=向上突破觸發、false=向下跌破觸發
  final bool isUpward;

  /// 對應既有警示系統的 alertType 值(`AlertEvaluationService` 以
  /// `price >= / <= targetValue` 判定,語意與此處完全一致——**刻意不自建
  /// 觸發判定**,免得兩套邏輯漂移)。
  String get alertTypeValue =>
      isUpward ? AlertParams.typeAbove : AlertParams.typeBelow;
}

/// 把「該盯哪個價位」算好放著——**app 只算不決定**,點哪個由使用者。
///
/// 守門價採 [AlertParams.stopGateAtrMultiple](=2.0),即 v3.3 §4.1 回測
/// 定案的 k:固定百分比停損落在飆股單日噪音之內(2026-08-07 回測:
/// 2% 停損被洗率 55.9%、2.0×ATR 降到 18.9%)。
abstract final class AlertTargetCalculator {
  /// [bars] 需依日期升冪,最後一筆為最新。資料不足的種類直接不給,不硬湊。
  static Map<AlertKind, AlertTarget> compute(List<Ohlc> bars) {
    if (bars.isEmpty) return const {};
    final closes = bars.map((b) => b.close).toList();
    final n = closes.length;
    final result = <AlertKind, AlertTarget>{};

    double ma(int period) =>
        closes.sublist(n - period).reduce((a, b) => a + b) / period;

    if (n >= 5) {
      result[AlertKind.breakBelowMa5] = AlertTarget(
        price: ma(5),
        isUpward: false,
      );
    }
    if (n >= 10) {
      result[AlertKind.breakBelowMa10] = AlertTarget(
        price: ma(10),
        isUpward: false,
      );
    }
    if (n >= 20) {
      final ma20 = ma(20);
      result[AlertKind.breakBelowMa20] = AlertTarget(
        price: ma20,
        isUpward: false,
      );
      result[AlertKind.breakAboveMa20] = AlertTarget(
        price: ma20,
        isUpward: true,
      );
      result[AlertKind.breakAbove20DayHigh] = AlertTarget(
        price: bars
            .sublist(n - 20)
            .map((b) => b.high)
            .reduce((a, b) => a > b ? a : b),
        isUpward: true,
      );
      final atr = simpleAtr(bars, AlertParams.stopGateAtrPeriod);
      if (atr != null && atr > 0) {
        result[AlertKind.stopGate] = AlertTarget(
          price: closes.last - atr * AlertParams.stopGateAtrMultiple,
          isUpward: false,
        );
      }
    }
    return result;
  }

  /// DB 價格列 → 計算用單位。**明確依日期升冪排序**,不假設 DAO 的回傳
  /// 方向:方向錯了,均線與 20 日高會用最舊的幾根算,價位會遠離現價。
  /// OHLC 任一缺值或收盤 ≤0 的列略過(停牌)。
  static List<Ohlc> ohlcFrom(List<DailyPriceEntry> history) {
    final sorted = [...history]..sort((a, b) => a.date.compareTo(b.date));
    return [
      for (final p in sorted)
        if (p.high != null && p.low != null && p.close != null && p.close! > 0)
          Ohlc(high: p.high!, low: p.low!, close: p.close!),
    ];
  }

  /// ATR(period):True Range 的**簡單平均**(非 Wilder 平滑)。
  ///
  /// ⚠️ 與 `TechnicalIndicatorService.calculateATR` **不同口徑**(那支用
  /// Wilder RMA:SMA seed 後遞迴平滑)——2026-08-08 code review 指出我原本
  /// 的註解誤稱兩者相同。這裡刻意用簡單平均,因為 **2026-08-07 的 k 值
  /// 回測就是用簡單平均跑的**(k=2.0 對應 ATR(20) 簡單平均,見 v3.3
  /// 〔註 I〕);換成 Wilder 會讓實際停損寬度與回測結論脫鉤。
  /// 若日後要統一口徑,必須連 k 一起重新回測。
  static double? simpleAtr(List<Ohlc> bars, int period) {
    if (bars.length < period + 1) return null;
    var sum = 0.0;
    for (var i = bars.length - period; i < bars.length; i++) {
      final b = bars[i];
      final prevClose = bars[i - 1].close;
      final tr = [
        b.high - b.low,
        (b.high - prevClose).abs(),
        (b.low - prevClose).abs(),
      ].reduce((a, c) => a > c ? a : c);
      sum += tr;
    }
    return sum / period;
  }
}
