import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/models/shared/ytd_yoy_parser.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';

/// MOPS(公開資訊觀測站,舊版 mopsov)月營收 CSV 的市場別
enum MopsMarket {
  /// 上市
  sii,

  /// 上櫃
  otc,
}

/// MOPS 月營收單筆資料
class MopsMonthlyRevenue {
  const MopsMonthlyRevenue({
    required this.code,
    required this.year,
    required this.month,
    required this.revenue,
    this.momGrowth,
    this.yoyGrowth,
    this.ytdYoyGrowth,
  });

  final String code;

  /// 西元年
  final int year;
  final int month;

  /// 當月營收(千元,與 TWSE openapi t187ap05_L 同單位——2026-08-03 以
  /// 台泥 6 月值逐位元對帳驗證)
  final double revenue;
  final double? momGrowth;
  final double? yoyGrowth;

  /// 累計年增率 %(CSV [10..12] 欄;自洽失配或舊版式缺欄為 null)
  final double? ytdYoyGrowth;
}

/// 公開資訊觀測站(舊版 `mopsov.twse.com.tw`)月營收 client。
///
/// **為什麼需要它**:TWSE openapi 彙總表(t187ap05_L)是月批式——申報期
/// (每月 1~10 日)結束後才切換到新月份;而 MOPS 的 t21sc03 CSV 在申報期
/// **逐日填充**(2026-08-03 晚間實測:7 月已 35 家上市)。接這個來源讓
/// 營收訊號在公布當晚觸發,不用等到 10 日後一次補考。
///
/// **已知風險與對策**:mopsov 是官方舊版過渡站,可能隨時關站——呼叫端
/// (FundamentalRepository)一律 fail-soft,掛了就退回等 openapi 的現狀,
/// 零下行。新版 MOPS 的靜態頁已下架(404),故只有舊版這條路。
///
/// **解析策略**:CSV 是 big5 編碼,但所需欄位(代號/年月/營收/增減率)
/// 全為 ASCII——以 latin-1 解碼(不會拋錯),中文欄(公司名稱/產業別)
/// 變亂碼但根本不讀,名稱 DB 主檔本來就有。零 big5 依賴,tool 鏈純 Dart
/// 安全。
class MopsClient {
  MopsClient({Dio? dio})
    : _dio =
          dio ??
          (MarketClientMixin.createDio(ApiConfig.mopsBaseUrl)
            ..options.responseType = ResponseType.bytes
            // 不帶瀏覽器 UA 會被 WAF 擋(回安全頁),2026-08-03 實測
            ..options.headers['User-Agent'] = ApiConfig.mopsUserAgent);

  final Dio _dio;

  static const _tag = 'MOPS';

  /// 取得申報期間的當月營收(已申報公司,逐日累積)
  Future<List<MopsMonthlyRevenue>> getInProgressRevenue({
    required int year,
    required int month,
    required MopsMarket market,
  }) {
    return MarketClientMixin.executeRequest(_tag, '公布期營收', () async {
      final rocYear = year - 1911;
      final path = '/nas/t21/${market.name}/t21sc03_${rocYear}_$month.csv';
      final response = await _dio.get<List<int>>(path);

      if (response.statusCode != 200 || response.data == null) {
        throw ApiException(
          '$_tag CSV error: ${response.statusCode}',
          response.statusCode,
        );
      }
      final rows = parseRevenueCsv(response.data!, year: year, month: month);
      AppLogger.info(
        _tag,
        '公布期營收 $year/$month(${market.name}): ${rows.length} 家已申報',
      );
      return rows;
    });
  }

  /// 解析 t21sc03 CSV(純函式,供測試直接餵 bytes)。
  ///
  /// 資料檢核(壞資料一律拒收,絕不寫入錯位值):
  /// 1. WAF 安全頁/HTML → [ApiException](整批拒收)
  /// 2. 逐列:欄數不足、資料年月 ≠ 目標月、代號非 4 位、營收非數字 → 剔除
  /// 3. **自洽檢核(主防線)**:每列用「當月/上月/去年同月營收」重算
  ///    MoM%/YoY% 與 CSV 給的值比對——欄序漂移時重算必對不上,失配列
  ///    超過容忍度即 [FormatException] 整批拒收。這驗的是語意不是形狀,
  ///    任何欄位錯位都逃不掉。
  @visibleForTesting
  static List<MopsMonthlyRevenue> parseRevenueCsv(
    List<int> bytes, {
    required int year,
    required int month,
  }) {
    final text = latin1.decode(bytes);
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('<') || text.contains('SECURITY REASONS')) {
      throw const ApiException(_mopsWafMessage, null);
    }

    final expectedYm = '${year - 1911}/$month';
    final byCode = <String, MopsMonthlyRevenue>{};
    var inconsistent = 0;
    var checked = 0;

    for (final line in text.split('\n')) {
      final fields = _splitQuotedCsvLine(line);
      if (fields.length < 10) continue;
      if (fields[1].trim() != expectedYm) continue;
      final code = fields[2].trim();
      if (!RegExp(r'^\d{4}$').hasMatch(code)) continue;
      final revenue = double.tryParse(fields[5]);
      if (revenue == null || revenue < 0) continue;

      final prevRevenue = double.tryParse(fields[6]);
      final lastYearRevenue = double.tryParse(fields[7]);
      final mom = double.tryParse(fields[8]);
      final yoy = double.tryParse(fields[9]);

      // 自洽檢核:重算增減率 vs CSV 給的值(容忍浮點誤差 0.5 個百分點)
      var rowInconsistent = 0;
      if (prevRevenue != null && prevRevenue > 0 && mom != null) {
        checked++;
        final expected = (revenue - prevRevenue) / prevRevenue * 100;
        if ((expected - mom).abs() > 0.5) rowInconsistent++;
      }
      if (lastYearRevenue != null && lastYearRevenue > 0 && yoy != null) {
        checked++;
        final expected = (revenue - lastYearRevenue) / lastYearRevenue * 100;
        if ((expected - yoy).abs() > 0.5) rowInconsistent++;
      }
      inconsistent += rowInconsistent;
      // 逐列剔除(2026-08-05 複審 Low #3):MoM 與 YoY **雙雙**失配的列
      // 自證損毀(欄序漂移打到該列),不落庫——補上批次拒收在小樣本
      // (失配 ≤2 筆)時的失守窗;單一失配仍容忍(個股特例)。
      if (rowInconsistent >= 2) continue;

      // 累計欄([10]當月累計/[11]去年累計/[12]前期比較增減%):
      // 自洽政策與單月欄一致,但失配只廢累計欄不廢整列——
      // 累計欄壞不該拖累完好的單月資料(舊版式 <13 欄= null)
      final double? ytdYoy = fields.length >= 13
          ? parseSelfCheckedYtdYoy(
              ytdCurrent: double.tryParse(fields[10]),
              ytdPrior: double.tryParse(fields[11]),
              ytdPct: double.tryParse(fields[12]),
            )
          : null;

      byCode.putIfAbsent(
        code,
        () => MopsMonthlyRevenue(
          code: code,
          year: year,
          month: month,
          revenue: revenue,
          momGrowth: mom,
          yoyGrowth: yoy,
          ytdYoyGrowth: ytdYoy,
        ),
      );
    }

    // 失配超過「2 筆且 5%」即整批拒收——單筆異常可能是個股特例,
    // 系統性失配只會是欄序漂移
    if (checked > 0 && inconsistent > 2 && inconsistent / checked > 0.05) {
      throw FormatException(
        'MOPS CSV 欄位自洽檢核失敗($inconsistent/$checked)——'
        '疑似欄序漂移,整批拒收',
      );
    }

    return byCode.values.toList();
  }

  static const _mopsWafMessage = 'MOPS 回應非 CSV(WAF 安全頁/HTML)';

  /// 解析一行 quoted CSV(欄值不含跳脫引號,MOPS 格式實測如此)
  static List<String> _splitQuotedCsvLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    fields.add(buf.toString());
    return fields;
  }
}
