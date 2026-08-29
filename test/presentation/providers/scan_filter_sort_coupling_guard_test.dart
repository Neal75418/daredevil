// 掃描頁「篩選必然重排」的守門(2026-08-29 domain 稽核 C1)
//
// `ScanFilterService` 的兩個方法有**相反的 mutation 契約**:
//   applyFilter → 回傳全新 list(純函數)
//   applySort   → 就地排序(文件明寫「就地排序」)
// 於是每一次 applyFilter 都會丟掉上一次的排序結果。三個呼叫點裡有兩個
// 記得補 applySort、setIndustryFilter 漏了,而症狀是**清單看起來很正常**
// ——只是換了一個排序鍵。排序籤仍顯示使用者選的鍵。
//
// 實測 2026-08-28 掃描主清單(422 檔 = 276 訊號 + 146 風控可見):點一下
// 產業籤,第一頁 top-20 只剩 2 檔重疊、中位排名位移 103 名;落點是 DAO 的
// `ORDER BY score DESC`,
// 正是 ScanSort 文件記載「corr ≈ 0.17 近乎無鑑別力」的那個鍵。
//
// 行為本身由 scan_provider_test.dart 的『產業篩選必須保留排序』測到;
// 這裡守的是**結構**:未來新增的呼叫點不能再繞過排序。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/presentation/providers/scan_provider.dart',
  ).readAsStringSync();

  test('🚨 applyFilter 只能在 _applyFilterAndSort 這個單一入口呼叫', () {
    // 切出 _applyFilterAndSort 的方法體(到下一個同層成員宣告為止)
    final start = source.indexOf('void _applyFilterAndSort(');
    expect(start, greaterThan(0), reason: '單一入口被改名了——請一併更新本守門');
    final nextMember = RegExp(
      r'\n  (?:[A-Za-z_<][\w<>?,\s]*\s)?_?\w+\(',
    ).firstMatch(source.substring(start + 10));
    final body = source.substring(
      start,
      nextMember == null ? source.length : start + 10 + nextMember.start,
    );

    final total = '_service.applyFilter('.allMatches(source).length;
    final inside = '_service.applyFilter('.allMatches(body).length;

    expect(total, 1, reason: '有第 2 處直接呼叫 applyFilter——它會繞過排序');
    expect(inside, 1, reason: '唯一那處不在 _applyFilterAndSort 裡');
    expect(body, contains('_applyGlobalSort('), reason: '單一入口自己忘了排序,守門就失去意義');
  });

  test('sanity:掃描器真的看得到這些字面(防假綠)', () {
    // 上面那條是「找不到違規就過」——字串改名會讓它靜默變成套套邏輯。
    expect(source, contains('_service.applyFilter('));
    expect(source, contains('void _applyGlobalSort('));
    expect(
      '_applyFilterAndSort('.allMatches(source).length,
      greaterThanOrEqualTo(4),
      reason: '3 個呼叫點 + 1 個宣告;數量驟減 = 可能有人拆回去了',
    );
  });
}
