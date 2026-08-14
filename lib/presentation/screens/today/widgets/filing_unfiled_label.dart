import 'package:daredevil/core/constants/stock_patterns.dart';

/// 公布期「沉默點名」的名單字串(2026-08-14)。
///
/// 設計討論(2026-08-05)寫過「壓線的沉默也是資訊」——這裡把沉默者點名:
/// 自選中尚未申報的前 [maxNames] 檔以頓號串接,超出以「+N」收尾。
/// 全數已交回 null(呼叫端隱藏該行)。
///
/// 兩條紀律:
/// - ETF 不點名:0050 之流永遠沒有月營收/季報,不是沉默是無此義務——
///   放行會佔掉點名名額,把真正的沉默者擠出畫面(同
///   fundamental_syncer 的排除理由)
/// - 依代碼穩定排序:點名的語意是「誰沉默」,若跟著自選頁排序模式走,
///   排序切到漲跌幅時名單天天洗牌,連續觀察就不可比了
String? unfiledNamesLabel({
  required List<({String symbol, String? name})> watchlistItems,
  required Set<String> filedSymbols,
  int maxNames = 3,
}) {
  final unfiled = [
    for (final it in watchlistItems)
      if (!StockPatterns.isEtfCode(it.symbol) &&
          !filedSymbols.contains(it.symbol))
        it,
  ]..sort((a, b) => a.symbol.compareTo(b.symbol));
  if (unfiled.isEmpty) return null;
  final names = [for (final it in unfiled) it.name ?? it.symbol];
  final shown = names.take(maxNames).join('、');
  final rest = names.length - maxNames;
  return rest > 0 ? '$shown +$rest' : shown;
}
