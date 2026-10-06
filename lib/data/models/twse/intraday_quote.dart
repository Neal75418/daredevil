/// [IntradayQuote.price] 取自哪個欄位(盤中即時報價判斷顯示來源與收盤報價用)
enum QuotePriceSource {
  /// 當輪成交價 `z`
  trade,

  /// 漲跌停鎖住、當輪沒有成交:取漲跌停價(見 `_lockedPrice`)
  locked,

  /// 試撮價 `pz`
  trial,

  /// 最佳一檔買賣中價或單邊
  book,
}

/// 盤中即時報價(TWSE MIS `getStockInfo.jsp`,2026-08-08)。
///
/// 這支 API 的欄位名極短且**無成交時價格欄是 `'-'`**——盤前、冷門股、
/// 剛開盤那幾秒都會遇到。價格取用順序 z(成交)→ pz(試撮)→ 漲跌停鎖住時
/// 的漲跌停價(見 [_lockedPrice])→ 最佳一檔買賣的中價(只有一側時取該
/// 側);都沒有就不回傳這檔,不回 0(0 會讓所有「跌破」提醒瞬間觸發),也
/// 不退回開盤價(理由見 [parseResponse] 內註解)。
class IntradayQuote {
  const IntradayQuote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.previousClose,
    required this.priceSource,
    this.open,
    this.high,
    this.low,
    this.volume,
    this.time,
    this.date,
    this.lastTradePrice,
    this.lastTradeTime,
    this.limitUp,
    this.limitDown,
    required this.hasBid,
    required this.hasAsk,
  });

  final String symbol;
  final String name;

  /// 現價(見類別註解的退回順序)
  final double price;
  final double previousClose;
  final double? open;
  final double? high;
  final double? low;

  /// 累計成交量(張)
  final int? volume;

  /// 報價時刻(HH:mm:ss)
  final String? time;

  /// [price] 的來源
  final QuotePriceSource priceSource;

  /// 報價日期(`d`,yyyyMMdd);格式不符為 null。即時報價只有等於今天才可顯示
  final DateTime? date;

  /// 最後一筆成交價與時間(`trade.z`／`trade.t`,非官方欄位)。
  ///
  /// 當輪 `z='-'` 時仍記著最後一筆成交(2026-10-05 12:13 實測:2330 當輪
  /// z='-'、trade.z=2560 @ 12:13:25)。**只供顯示**,不參與 [price]——盤中
  /// 提醒的比價維持原規則。指數列與收盤後的回應沒有這個物件,為 null。
  final double? lastTradePrice;
  final String? lastTradeTime;

  /// 漲停價、跌停價(`u`／`w`);指數沒有這兩欄,為 null
  final double? limitUp;
  final double? limitDown;

  /// 買方、賣方五檔是否有任何正數價位(首格 0 是市價委託,不算)
  final bool hasBid;
  final bool hasAsk;

  /// 鎖漲停:價格等於漲停價且沒有賣單(不論當輪有無成交)
  bool get isLimitUpLocked => limitUp != null && price == limitUp && !hasAsk;

  /// 鎖跌停:價格等於跌停價且沒有買單
  bool get isLimitDownLocked =>
      limitDown != null && price == limitDown && !hasBid;

  double get changePercent =>
      previousClose > 0 ? (price / previousClose - 1) * 100 : 0;

  /// 解析整份回應 → symbol 對報價。rtcode 非 0000 或格式異常一律回空
  /// ——**把失敗當成沒有報價,而不是當成某個價格**。
  static Map<String, IntradayQuote> parseResponse(Map<String, dynamic> json) {
    if (json['rtcode'] != '0000') return const {};
    final rows = json['msgArray'];
    if (rows is! List) return const {};

    final result = <String, IntradayQuote>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final symbol = row['c']?.toString().trim() ?? '';
      if (symbol.isEmpty) continue;

      final prevClose = _num(row['y']);
      if (prevClose == null || prevClose <= 0) continue;

      // 🚨 **不可退回開盤價**(2026-08-10 實機):MIS 在沒有成交時 z='-',
      // 而這是**常態不是例外**——盤中 12:26 的一次乾淨請求裡,金像電、
      // 台積電、鴻海的 z 全是 '-'。舊版退回 `o`(開盤價),於是金像電被
      // 讀成 985,而市場實際在 917,**差 7.4%**;整份自選最大誤差 ±8.9%。
      //
      // 後果是提醒的比價基準整天停在開盤價:該觸發的不觸發、不該觸發的
      // 觸發。當時使用者有 7 筆盤中提醒正在監控。
      //
      // 正解是用**買賣五檔的中價**——那才是「現在的市場」。真的連五檔都
      // 沒有(盤前、暫停交易)就視為無報價,不要猜:漏一輪(5 分鐘後
      // 再查)遠比觸發錯誤安全。
      final (price, priceSource) = switch ((
        _num(row['z']),
        _num(row['pz']),
        _lockedPrice(row),
      )) {
        (final z?, _, _) => (z, QuotePriceSource.trade),
        (_, final pz?, _) => (pz, QuotePriceSource.trial),
        (_, _, final locked?) => (locked, QuotePriceSource.locked),
        _ => (_midOrSide(row['b'], row['a']), QuotePriceSource.book),
      };
      if (price == null) continue;

      // 最後一筆成交(非官方的 trade 物件):只供顯示,不參與 price
      final (lastTradePrice, lastTradeTime) = switch (row['trade']) {
        final Map<dynamic, dynamic> t when _num(t['z']) != null => (
          _num(t['z']),
          t['t']?.toString(),
        ),
        _ => (null, null),
      };

      result[symbol] = IntradayQuote(
        symbol: symbol,
        name: row['n']?.toString() ?? '',
        price: price,
        previousClose: prevClose,
        open: _num(row['o']),
        high: _num(row['h']),
        low: _num(row['l']),
        volume: int.tryParse(row['v']?.toString() ?? ''),
        time: row['t']?.toString(),
        priceSource: priceSource,
        date: _date(row['d']),
        lastTradePrice: lastTradePrice,
        lastTradeTime: lastTradeTime,
        limitUp: _num(row['u']),
        limitDown: _num(row['w']),
        hasBid: _firstPositive(row['b']) != null,
        hasAsk: _firstPositive(row['a']) != null,
      );
    }
    return result;
  }

  /// 漲跌停鎖住、當輪沒有成交時的價格;不是鎖住就回 null 交給五檔中價。
  ///
  /// 🚨 2026-10-05 實測(12:13,加權大漲逾千點):川湖、台光電、聯茂漲停
  /// 鎖住,z、pz 都是 '-',買方五檔是 `0.0000_13355.0000_…`(首格 0 是
  /// 市價委託,第二格才是漲停價),賣方 '-'。[_midOrSide] 只看首格 → 判為
  /// 無報價、整檔丟掉。z 只在快照剛好碰到成交時有值,所以鎖住期間只有
  /// 那幾輪拿得到價格;成交稀少的鎖跌停股,「跌破」可能整段鎖住期間都
  /// 不響(鎖漲停的「突破」同理)。
  ///
  /// 只認「買方第一個正數價位**等於漲停價**、賣方沒有任何正數價位」
  /// (跌停為鏡像)。不把「第一個正數」一律當價格:無賣單、有市價買單、
  /// 外加一筆遠低的限價買單時,那筆限價不是現在的市場,當價格會讓
  /// 「跌破」誤觸發。其餘情況維持 [_midOrSide] 原行為。
  static double? _lockedPrice(Map<dynamic, dynamic> row) {
    final limitUp = _num(row['u']);
    final limitDown = _num(row['w']);
    final bid = _firstPositive(row['b']);
    final ask = _firstPositive(row['a']);
    if (limitUp != null && ask == null && bid == limitUp) return limitUp;
    if (limitDown != null && bid == null && ask == limitDown) return limitDown;
    return null;
  }

  /// 買賣五檔取中價;只有單邊就用那一邊,兩邊皆無回 null。
  ///
  /// 欄位格式是 `價1_價2_價3_價4_價5_`(底線分隔、結尾也有底線),
  /// 第一格就是最佳檔位。⚠️ 這些欄位在無報價時可能是 `0.0000_...`,
  /// 所以一律經 [_num] 過濾非正數。
  static double? _midOrSide(Object? bidField, Object? askField) {
    double? best(Object? f) {
      final parts = (f?.toString() ?? '').split('_');
      return parts.isEmpty ? null : _num(parts.first);
    }

    final bid = best(bidField);
    final ask = best(askField);
    if (bid != null && ask != null) return (bid + ask) / 2;
    return bid ?? ask;
  }

  /// 五檔欄位裡第一個正數價位;首格 0(市價委託)與 '-' 都跳過
  static double? _firstPositive(Object? field) {
    for (final part in (field?.toString() ?? '').split('_')) {
      final v = _num(part);
      if (v != null) return v;
    }
    return null;
  }

  /// MIS 用 `'-'` 表示「無此值」,parse 失敗與非正數一律當缺值
  static double? _num(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty || s == '-') return null;
    final d = double.tryParse(s);
    return (d != null && d > 0) ? d : null;
  }

  /// `d`(yyyyMMdd)→ 當天午夜;格式不符回 null
  static DateTime? _date(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.length != 8) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(4, 6));
    final d = int.tryParse(s.substring(6));
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }
}
