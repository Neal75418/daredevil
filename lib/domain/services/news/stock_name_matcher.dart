// lib/domain/services/news/stock_name_matcher.dart
import 'package:daredevil/core/constants/news_heat_params.dart';
import 'package:daredevil/core/constants/news_link_params.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 某檔在比對器裡的名稱狀態（個股新聞分頁的說明文案依此選）
enum StockNameStatus {
  /// 有可比對的名稱
  matched,

  /// 在股票清單裡，但名稱全被排除（常見詞）或太短
  excluded,

  /// 不在建立比對器的股票清單裡（已下市等）
  notListed,
}

/// 從新聞標題匹配公司簡稱 → 股票代碼（純函數）
///
/// 兩種建法：
/// - [StockNameMatcher.fromStocks]（熱度分析與快照）：名稱長度 ≥ 3 全部納入；
///   長度 = 2 僅 [NewsHeatParams.twoCharNameWhitelist]
/// - [StockNameMatcher.forNewsLinks]（新聞顯示）：2 字名預設納入、擋
///   [NewsLinkParams.excludedNames]；非公司詞組先佔位；名稱去 `*`、有 `-`
///   後綴時另收基底名
///
/// 共同規則（依語料實證設計，見 spec）：
/// - 最長優先＋位置消耗：「長榮航」命中後佔用字元，「長榮」不重複計分
/// - 同篇多次出現計 1
///
/// ⚠️ 匹配結果僅供熱度分析、快照與新聞顯示，**不得寫入 news_stock_map**（不進評分）。
class StockNameMatcher {
  StockNameMatcher._(this._entries, this._universe);

  /// (名稱, 代碼)；代碼為 null 的是非公司詞組（只佔位、不對應股票）。
  /// 已排序：長度降冪 → 同長時非公司詞組優先 → 字典序
  final List<(String, String?)> _entries;

  /// 建立時傳入的股票代碼
  final Set<String> _universe;

  factory StockNameMatcher.fromStocks(List<StockMasterEntry> stocks) {
    // 別名覆蓋(2026-08-01):媒體通用簡稱與現行官方名稱不同字串時
    // (日月光→3711 日月光投控),別名指向本尊——殭屍同名代碼(2311)
    // 在冊期間不得吸走匹配,殭屍清理後裸名也不落空。目標不在宇宙時
    // 回退自然名,別名不得讓名稱憑空消失。
    final symbols = {for (final s in stocks) s.symbol};
    final activeAliases = {
      for (final e in NewsHeatParams.nameAliasToSymbol.entries)
        if (symbols.contains(e.value)) e.key: e.value,
    };

    final entries = <(String, String?)>[];
    for (final s in stocks) {
      final name = s.name.trim();
      if (activeAliases.containsKey(name)) continue; // 別名蓋過同名自然入口
      if (name.length >= 3 ||
          (name.length == 2 &&
              NewsHeatParams.twoCharNameWhitelist.contains(name))) {
        entries.add((name, s.symbol));
      }
    }
    activeAliases.forEach((name, symbol) => entries.add((name, symbol)));
    entries.sort(_compare);
    return StockNameMatcher._(entries, symbols);
  }

  /// 新聞顯示用（新聞頁「自選」與股票標籤、個股新聞分頁）
  ///
  /// 參數預設取 [NewsLinkParams]；測試傳入固定清單，不受清單定案影響。
  factory StockNameMatcher.forNewsLinks(
    List<StockMasterEntry> stocks, {
    Set<String> excludedNames = NewsLinkParams.excludedNames,
    Set<String> nonCompanyPhrases = NewsLinkParams.nonCompanyPhrases,
    Map<String, String> extraAliases = NewsLinkParams.displayNameAliases,
  }) {
    final symbols = {for (final s in stocks) s.symbol};
    final aliases = {
      for (final e in {
        ...NewsHeatParams.nameAliasToSymbol,
        ...extraAliases,
      }.entries)
        if (symbols.contains(e.value)) e.key: e.value,
    };
    bool eligible(String name) =>
        name.length >= NewsLinkParams.minNameLength &&
        !excludedNames.contains(name);

    final entries = <(String, String?)>{};
    for (final s in stocks) {
      for (final name in _displayNamesOf(s.name)) {
        if (aliases.containsKey(name)) continue; // 別名蓋過同名自然入口
        if (eligible(name)) entries.add((name, s.symbol));
      }
    }
    aliases.forEach((name, symbol) => entries.add((name, symbol)));
    for (final phrase in nonCompanyPhrases) {
      entries.add((phrase, null));
    }
    return StockNameMatcher._(entries.toList()..sort(_compare), symbols);
  }

  /// 顯示用名稱：去掉 `*`；有 `-` 後綴（-KY、-創、-KY創、-DR）時另收 `-` 前的基底名
  static Set<String> _displayNamesOf(String rawName) {
    final name = rawName.replaceAll('*', '').trim();
    final dash = name.indexOf('-');
    return {
      if (name.isNotEmpty) name,
      if (dash > 0) name.substring(0, dash).trim(),
    };
  }

  /// 長度降冪 → 同長時非公司詞組優先 → 字典序。熱度建法沒有詞組，排序與改版前相同
  static int _compare((String, String?) a, (String, String?) b) {
    final lenCmp = b.$1.length.compareTo(a.$1.length);
    if (lenCmp != 0) return lenCmp;
    final aIsPhrase = a.$2 == null;
    if (aIsPhrase != (b.$2 == null)) return aIsPhrase ? -1 : 1;
    return a.$1.compareTo(b.$1); // tie-break by dictionary order ascending
  }

  /// 回傳標題中提及的股票代碼集合
  Set<String> match(String title) => {for (final (_, s) in _claims(title)) s};

  /// 標題中提及的股票代碼，依第一次出現的位置排序（同一檔只列一次）
  List<String> matchInOrder(String title) {
    final claims = _claims(title)..sort((a, b) => a.$1.compareTo(b.$1));
    final seen = <String>{};
    return [
      for (final (_, s) in claims)
        if (seen.add(s)) s,
    ];
  }

  /// 比對器裡指向 [symbol] 的名稱（含別名、基底名）
  List<String> namesOf(String symbol) => [
    for (final (name, s) in _entries)
      if (s == symbol) name,
  ];

  StockNameStatus nameStatusOf(String symbol) {
    if (!_universe.contains(symbol)) return StockNameStatus.notListed;
    return _entries.any((e) => e.$2 == symbol)
        ? StockNameStatus.matched
        : StockNameStatus.excluded;
  }

  /// (起始位置, 代碼)，依掃描順序；非公司詞組佔位但不列入
  List<(int, String)> _claims(String title) {
    final claimed = List<bool>.filled(title.length, false);
    final result = <(int, String)>[];
    for (final (name, symbol) in _entries) {
      var from = 0;
      while (true) {
        final idx = title.indexOf(name, from);
        if (idx < 0) break;
        var free = true;
        for (var i = idx; i < idx + name.length; i++) {
          if (claimed[i]) {
            free = false;
            break;
          }
        }
        if (free) {
          for (var i = idx; i < idx + name.length; i++) {
            claimed[i] = true;
          }
          if (symbol != null) result.add((idx, symbol));
        }
        from = idx + 1;
      }
    }
    return result;
  }
}
