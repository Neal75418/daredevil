/// 盤中即時報價(TWSE MIS `getStockInfo.jsp`,2026-08-08)。
///
/// 這支 API 的欄位名極短且**無成交時價格欄是 `'-'`**——盤前、冷門股、
/// 剛開盤那幾秒都會遇到。價格取用順序 z(成交)→ pz(試撮)→ o(開盤)
/// → y(昨收),寧可回昨收也不要回 0(0 會讓所有「跌破」提醒瞬間觸發)。
class IntradayQuote {
  const IntradayQuote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.previousClose,
    this.open,
    this.high,
    this.low,
    this.volume,
    this.time,
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
      final price =
          _num(row['z']) ?? _num(row['pz']) ?? _midOrSide(row['b'], row['a']);
      if (price == null) continue;

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
      );
    }
    return result;
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

  /// MIS 用 `'-'` 表示「無此值」,parse 失敗與非正數一律當缺值
  static double? _num(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty || s == '-') return null;
    final d = double.tryParse(s);
    return (d != null && d > 0) ? d : null;
  }
}
