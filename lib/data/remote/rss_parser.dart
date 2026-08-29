import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/models/news_feed.dart';

// Re-export domain value objects so existing data-layer callers can keep
// importing them via this file.
export 'package:daredevil/domain/models/news_feed.dart'
    show NewsFeedError, NewsFeedSource;

/// 台灣財經新聞 RSS feed 解析器
class RssParser {
  RssParser({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: ApiConfig.rssConnectTimeoutSec),
        receiveTimeout: const Duration(seconds: ApiConfig.rssReceiveTimeoutSec),
        headers: {'User-Agent': 'Daredevil/1.0'},
      ),
    );
  }

  /// 從 URL 解析 RSS feed
  Future<List<RssNewsItem>> parseFeed(NewsFeedSource source) async {
    try {
      final response = await _dio.get(source.url);

      if (response.statusCode == 200) {
        final xmlString = response.data.toString();
        return _parseXml(xmlString, source);
      }

      throw ApiException(
        'Failed to fetch RSS feed: ${source.name}',
        response.statusCode,
      );
    } on DioException catch (e) {
      throw NetworkException('Failed to fetch RSS: ${source.name}', e);
    } on XmlException catch (e) {
      throw ParseException('Failed to parse RSS XML: ${source.name}', e);
    }
  }

  /// 並行解析多個 feeds
  ///
  /// 回傳包含解析結果和錯誤的 [RssParseResult]
  Future<RssParseResult> parseAllFeeds(List<NewsFeedSource> sources) async {
    final results = <RssNewsItem>[];
    final errors = <NewsFeedError>[];

    // 並行擷取 feeds，單一失敗不影響其他
    final futures = sources.map((source) async {
      try {
        return (items: await parseFeed(source), error: null, source: source);
      } catch (e) {
        // 擷取錯誤詳情供除錯用
        return (items: <RssNewsItem>[], error: e.toString(), source: source);
      }
    });

    final feedResults = await Future.wait(futures);
    for (final result in feedResults) {
      results.addAll(result.items);
      if (result.error != null) {
        errors.add(
          NewsFeedError(
            sourceName: result.source.name,
            url: result.source.url,
            error: result.error!,
            timestamp: DateTime.now(),
          ),
        );
      }
    }

    // 依發布日期排序，最新的在前
    results.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    return RssParseResult(items: results, errors: errors);
  }

  List<RssNewsItem> _parseXml(String xmlString, NewsFeedSource source) {
    final document = XmlDocument.parse(xmlString);
    final items = <RssNewsItem>[];

    // 先嘗試 RSS 2.0 格式
    final rssItems = document.findAllElements('item');
    for (final item in rssItems) {
      final newsItem = _parseRssItem(item, source);
      if (newsItem != null) {
        items.add(newsItem);
      }
    }

    // 若無 RSS 項目則嘗試 Atom 格式
    if (items.isEmpty) {
      final atomEntries = document.findAllElements('entry');
      for (final entry in atomEntries) {
        final newsItem = _parseAtomEntry(entry, source);
        if (newsItem != null) {
          items.add(newsItem);
        }
      }
    }

    return items;
  }

  RssNewsItem? _parseRssItem(XmlElement item, NewsFeedSource source) {
    final title = _getElementText(item, 'title');
    final link = _getElementText(item, 'link');
    final pubDate = _getElementText(item, 'pubDate');
    final guid = _getElementText(item, 'guid') ?? link;

    // 抓取內文：優先 content:encoded，其次 description
    final contentEncoded = _getElementText(item, 'content:encoded');
    final description = _getElementText(item, 'description');
    final rawContent = contentEncoded ?? description;
    final content = rawContent != null ? _stripHtml(rawContent) : null;

    if (title == null || link == null) return null;

    return RssNewsItem(
      id: _generateId(guid ?? link, source: source.name),
      source: source.name,
      title: title,
      content: content,
      url: link,
      publishedAt: _parseDate(pubDate) ?? DateTime.now(),
      category: source.category,
    );
  }

  RssNewsItem? _parseAtomEntry(XmlElement entry, NewsFeedSource source) {
    final title = _getElementText(entry, 'title');
    final linkElement = entry.findElements('link').firstOrNull;
    final link = linkElement?.getAttribute('href');
    final published =
        _getElementText(entry, 'published') ??
        _getElementText(entry, 'updated');
    final id = _getElementText(entry, 'id') ?? link;

    // 抓取內文：優先 content，其次 summary
    final contentText = _getElementText(entry, 'content');
    final summary = _getElementText(entry, 'summary');
    final rawContent = contentText ?? summary;
    final content = rawContent != null ? _stripHtml(rawContent) : null;

    if (title == null || link == null) return null;

    return RssNewsItem(
      id: _generateId(id ?? link, source: source.name),
      source: source.name,
      title: title,
      content: content,
      url: link,
      publishedAt: _parseDate(published) ?? DateTime.now(),
      category: source.category,
    );
  }

  String? _getElementText(XmlElement parent, String name) {
    final element = parent.findElements(name).firstOrNull;
    final text = element?.innerText.trim();
    // 空字串回傳 null（例如自閉合標籤 <guid/>）
    return (text == null || text.isEmpty) ? null : text;
  }

  /// 移除 HTML 標籤並清理內文
  ///
  /// 處理 RSS 內文中常見的 HTML 和 CDATA 包裝
  String _stripHtml(String html) {
    // 移除 CDATA 包裝
    var text = html.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
    // 移除 HTML 標籤
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    // 解碼常見 HTML entities
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // 移除多餘空白
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 限制長度（節省空間）
    if (text.length > ApiConfig.newsContentMaxLength) {
      text = '${text.substring(0, ApiConfig.newsContentMaxLength - 3)}...';
    }
    return text;
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null) return null;

    // 嘗試 RFC 822 格式（RSS）
    try {
      return _parseRfc822(dateStr);
    } on FormatException catch (e) {
      AppLogger.debug('RssParser', 'RFC 822 解析失敗: ${e.message}');
    }

    // 嘗試 ISO 8601 格式（Atom）
    try {
      return DateTime.parse(dateStr);
    } on FormatException catch (e) {
      AppLogger.debug('RssParser', 'ISO 8601 解析失敗: ${e.message}');
    }

    AppLogger.debug('RssParser', '日期解析失敗: $dateStr');
    return null;
  }

  /// 時區偏移量（小時）
  static const _timezoneOffsets = {
    'GMT': 0,
    'UTC': 0,
    'UT': 0,
    'EST': -5,
    'EDT': -4,
    'CST': -6,
    'CDT': -5,
    'MST': -7,
    'MDT': -6,
    'PST': -8,
    'PDT': -7,
  };

  /// 月份對照表（不區分大小寫）
  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  DateTime _parseRfc822(String dateStr) {
    // RFC 822 解析器（支援時區）
    // 格式: "Mon, 01 Jan 2026 12:00:00 +0800" 或 "Mon, 01 Jan 2026 12:00:00 GMT"
    // 也支援: "01 Jan 26 12:00:00 +08:00"（2 位數年份，時區含冒號）

    // 移除選擇性的星期前綴
    var cleanedDate = dateStr.trim();
    if (cleanedDate.contains(',')) {
      cleanedDate = cleanedDate.substring(cleanedDate.indexOf(',') + 1).trim();
    }

    final parts = cleanedDate.split(RegExp(r'\s+'));
    if (parts.length < 4) {
      throw const FormatException('Invalid RFC 822 date: insufficient parts');
    }

    // 解析日（1-31）
    final day = int.tryParse(parts[0]);
    if (day == null || day < 1 || day > 31) {
      throw FormatException('Invalid RFC 822 date: invalid day "${parts[0]}"');
    }

    // 解析月（不區分大小寫）
    final monthStr = parts[1].toLowerCase();
    final month = _months[monthStr];
    if (month == null) {
      throw FormatException(
        'Invalid RFC 822 date: invalid month "${parts[1]}"',
      );
    }

    // 解析年（處理 2 位數和 4 位數）
    var year = int.tryParse(parts[2]);
    if (year == null) {
      throw FormatException('Invalid RFC 822 date: invalid year "${parts[2]}"');
    }
    // 將 2 位數年份轉換為 4 位數（RFC 822 允許 2 位數年份）
    // 00-49 → 2000-2049，50-99 → 1950-1999
    if (year < 100) {
      year = year < 50 ? 2000 + year : 1900 + year;
    }

    var hour = 0;
    var minute = 0;
    var second = 0;
    var tzOffsetMinutes = 0;

    if (parts.length >= 4 && parts[3].contains(':')) {
      final timeParts = parts[3].split(':');
      hour = _clamp(int.tryParse(timeParts[0]) ?? 0, 0, 23);
      minute = _clamp(
        int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0,
        0,
        59,
      );
      second = _clamp(
        int.tryParse(timeParts.length > 2 ? timeParts[2] : '0') ?? 0,
        0,
        59,
      );

      // 解析時區（如有）
      if (parts.length >= 5) {
        tzOffsetMinutes = _parseTimezone(parts[4]);
      }
    }

    // 驗證特定月份的日期
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final validDay = day <= daysInMonth ? day : daysInMonth;

    // 建立 UTC 日期時間並調整時區
    final utc = DateTime.utc(year, month, validDay, hour, minute, second);
    return utc.subtract(Duration(minutes: tzOffsetMinutes));
  }

  /// 將時區字串解析為分鐘偏移量
  ///
  /// 支援: +0800, -0500, +08:00, -05:00, GMT, EST, PST 等
  int _parseTimezone(String tz) {
    if (tz.startsWith('+') || tz.startsWith('-')) {
      final sign = tz.startsWith('+') ? 1 : -1;
      var tzValue = tz.substring(1);

      // 處理含冒號格式（+08:00 → 0800）
      if (tzValue.contains(':')) {
        tzValue = tzValue.replaceAll(':', '');
      }

      if (tzValue.length >= 4) {
        final tzHours = int.tryParse(tzValue.substring(0, 2)) ?? 0;
        final tzMins = int.tryParse(tzValue.substring(2, 4)) ?? 0;
        return sign * (tzHours * 60 + tzMins);
      } else if (tzValue.length >= 2) {
        // 處理短格式如 +08（僅小時）
        final tzHours = int.tryParse(tzValue.substring(0, 2)) ?? 0;
        return sign * tzHours * 60;
      }
    } else if (_timezoneOffsets.containsKey(tz.toUpperCase())) {
      // 具名時區如 GMT、EST、PST
      return _timezoneOffsets[tz.toUpperCase()]! * 60;
    }
    return 0;
  }

  /// 將值限制在範圍內
  int _clamp(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// 使用更好的雜湊演算法產生唯一 ID
  ///
  /// 使用 FNV-1a 雜湊搭配來源資訊以減少碰撞
  String _generateId(String input, {String? source}) {
    // FNV-1a 雜湊參數
    const fnvPrime = 0x01000193;
    const fnvOffset = 0x811c9dc5;

    // 結合來源與輸入以提升唯一性
    final combined = source != null ? '$source:$input' : input;
    final bytes = utf8.encode(combined);

    var hash = fnvOffset;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }

    // 回傳補零的十六進位字串以維持一致長度
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 釋放底層 Dio HTTP 連線資源。
  ///
  /// RssParser 不持有 cache，僅關閉 Dio。由 Riverpod provider 的
  /// `ref.onDispose` 呼叫；ad-hoc 流程亦應在 `try/finally` 中呼叫。
  void close() {
    _dio.close(force: false);
  }
}

/// RSS 新聞項目
class RssNewsItem {
  const RssNewsItem({
    required this.id,
    required this.source,
    required this.title,
    this.content,
    required this.url,
    required this.publishedAt,
    required this.category,
  });

  final String id;
  final String source;
  final String title;
  final String? content; // 內文摘要（從 description 抓取，可能為空）
  final String url;
  final DateTime publishedAt;
  final String category;

  /// 從標題擷取可能的股票代碼
  ///
  /// 支援 4-6 位數代碼：一般股票（4 位）、ETF/權證（5-6 位）。
  ///
  /// **4 位數（非 0 開頭）一律要求明確股票上下文**（括號包覆或 -TW 後綴，
  /// 如「凌通(4952)」「聯電(2303-TW)」）：裸寫的 4 位數與年份（2027年）、
  /// 加權指數點數（漲1467點）、金額（賣超2102億）全面衝突，且台積電股價
  /// 進入 2xxx 區間後（「台積電大漲95元報2505」）連 ≥2100 的代號空間也
  /// 天天被行情文撞——對全量新聞語料重放驗證：正確關聯幾乎全帶括號/TW
  /// 格式，強制上下文零誤殺。0 開頭 4 位數（0050 等 ETF 命名空間）與
  /// 5-6 位數不受影響。
  List<String> extractStockCodes() {
    final regex = RegExp(r'\b(\d{4,6})\b');
    final codes = <String>[];
    for (final m in regex.allMatches(title)) {
      final code = m.group(1)!;
      if (code.length == 4 && !code.startsWith('0')) {
        final hasStockContext = RegExp(
          '[（(]$code[)）]|$code-?TW',
        ).hasMatch(title);
        if (!hasStockContext) continue;
      }
      codes.add(code);
    }
    return codes;
  }
}

/// 多個 RSS feeds 的解析結果
class RssParseResult {
  const RssParseResult({required this.items, required this.errors});

  final List<RssNewsItem> items;
  final List<NewsFeedError> errors;

  /// 是否有任何 feed 解析失敗
  bool get hasErrors => errors.isNotEmpty;

  /// 成功解析的項目數
  int get successCount => items.length;
}

// `NewsFeedSource` / `NewsFeedError` 已搬至 `domain/models/news_feed.dart`，
// 由此檔頂部 `export` 再對外供應（避免 domain 層直接 import data 層、
// 同時保持 data 層既有 import path 可用）。
