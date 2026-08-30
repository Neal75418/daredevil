// 價格斷點截斷的單一入口守門(2026-08-30 領域稽核 C3)
//
// `contiguousSuffix()` 只在 batch_data_loader 組 pricesMap 時套一次,而那份
// map 同時餵給 isolate 評分路徑與主執行緒 fallback——兩條都經過同一個入口。
//
// 這正是本專案反覆踩到的形狀:契約掛在 N 個履行點中的 1 個,其餘看起來完全
// 正常。這裡把它固定成**結構**:若日後有人新增第二個 pricesMap 組裝點、
// 或把這次的呼叫拿掉,本測試轉紅。
//
// 為什麼不接在指標函式裡:那是 12 個履行點(11 個規則檔各自讀 data.prices
// 算自己的窗 + calculateTechnicalIndicators),而入口只有 1 個。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final loader = File(
    'lib/domain/services/update/batch_data_loader.dart',
  ).readAsStringSync();
  final replay = File('tool/replay_calibrator.dart').readAsStringSync();

  test('🚨 batch_data_loader 的 pricesMap 必須經過 contiguousSuffix', () {
    expect(
      loader,
      contains('contiguousSuffix()'),
      reason: '評分鏈的價格入口若不截斷,跨水位位移的長窗指標會回到 ma60=506 那種值',
    );
    expect(
      loader,
      contains('rawPricesMap'),
      reason: '截斷後的變數名要與原始 map 分開,避免有人不小心用到未截斷的那份',
    );
    expect(
      RegExp(r'pricesMap:\s*rawPricesMap').hasMatch(loader),
      isFalse,
      reason: '未截斷的原始 map 不得被當成 ScoringBatchData.pricesMap',
    );
  });

  test('🚨 replay 的評分視窗同樣要截斷(否則校準語料與生產分岔)', () {
    expect(
      replay,
      contains('contiguousSuffix()'),
      reason: 'replay 不截斷 = 校準語料含生產不會那樣算的 stock-day',
    );
    // point-in-time:必須先 sublist 再截斷,反過來會用未來的除權息截過去
    expect(
      replay,
      contains('prices.sublist(0, i + 1).contiguousSuffix()'),
      reason: '順序反了就是 lookahead',
    );
  });

  test('🚨 截斷導致不足門檻時必須有運維可見性', () {
    // 那個計數混在 insufficientData 裡就與「新上市」分不開;除息旺季
    // 會有自選股落進「不足 21 根」的視窗,卡片少掉趨勢與評分需要看得見。
    expect(loader, contains('價格水位斷點'));
    expect(loader, contains('不足分析門檻'));
  });

  test('sanity:掃描器看得到這些字面(防假綠)', () {
    expect(loader, contains('ScoringBatchData'));
    expect(loader, contains('pricesMap'));
    expect(replay, contains('pricesUpToDay'));
  });
}
