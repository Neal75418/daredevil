import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/l10n/app_strings.dart';

/// 供給預先讀好的翻譯 map（避開 rootBundle 在 fake async 下不 resolve）
class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

/// 自選與個股新聞的新文案，以真實 zh-TW 翻譯斷言整句（2026-10-06，路線圖第 3 項）。
///
/// 一般測試的 `.tr()` 只回 key，看不到參數有沒有代進「有 {count} 個…」；
/// 參數名或翻譯的佔位字拼錯，畫面會直接露出「{count}」。真實翻譯會寫進
/// 全域狀態，所以獨立成一個檔案。
void main() {
  late Map<String, dynamic> zhTw;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
    zhTw =
        json.decode(await File('assets/translations/zh-TW.json').readAsString())
            as Map<String, dynamic>;
  });

  testWidgets('新文案 11 條整句正確', (tester) async {
    final texts = <String>[];
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'TW')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh', 'TW'),
        startLocale: const Locale('zh', 'TW'),
        assetLoader: _PreloadedAssetLoader(zhTw),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Builder(
              builder: (context) {
                texts
                  ..clear()
                  ..addAll([
                    S.newsFetchAllFailed,
                    S.newsFetchPartialFailed(2),
                    S.newsFilterMine,
                    S.newsMineEmptyNoStocks,
                    S.newsMineEmptyNoNews,
                    S.stockDetailTabNews,
                    S.stockNewsNoteMatched,
                    S.stockNewsNoteExcluded,
                    S.stockNewsNoteNotListed,
                    S.stockNewsEmpty,
                    S.stockNewsRefresh,
                  ]);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(texts, [
      '新聞來源都抓取失敗，顯示的是先前的新聞',
      '有 2 個新聞來源抓取失敗',
      '自選',
      '還沒有自選股或持股',
      '近 7 天沒有自選股或持股的相關新聞',
      '新聞',
      '依標題中的股票代號與公司名稱比對，可能包含同名詞；公告只收上市公司的自選與持股',
      '這檔簡稱是常見詞，只依代號比對；公告只收上市公司的自選與持股',
      '這檔不在目前的股票清單，只依代號比對；公告只收上市公司的自選與持股',
      '近 30 天沒有找到這檔的新聞',
      '重新整理新聞',
    ]);
  });
}
