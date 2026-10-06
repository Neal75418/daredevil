# 自選與個股相關新聞 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新聞頁加「自選」篩選（自選∪持股相關的新聞）、個股頁加「新聞」分頁（這檔近 30 天的新聞）；新聞的相關股票改為「代號對應 ∪ 標題簡稱比對」，比對結果只供顯示、不寫入 `news_stock_map`；抓新聞抽成共用並在失敗時提示；順帶修正新聞分組與預覽時間未轉本地時間。

**Architecture:**
- **比對器**：`StockNameMatcher` 新增顯示用建法 `forNewsLinks`（2 字名預設收、排除名稱、非公司詞組佔位、名稱去 `*`／`-` 後綴另收基底名、同長時詞組優先）。熱度用的 `fromStocks` 輸出不變，以資料庫副本全量重放驗證。
- **純函式**：`NewsStockLinks.merge`（代號 ∪ 簡稱）、`NewsDedup.sameDayTitle`（從 `NewsState` 抽出，個股頁共用）。
- **資料層**：`getWatchlistAndHoldingSymbols()`（自選∪持股，`syncMaterialInfo` 改用它）、`getNewsCandidatesForStock()`（代號對應或標題含名稱，`instr()`，UTC 截止點）。
- **Provider**：`newsLinkMatcherProvider`（比對器快取，隨每日更新重建）、`newsFetcherProvider`（共用抓新聞＋去重＋結果）、`newsDataVersionProvider`（抓完遞增，新聞頁、熱度、個股新聞監聽）、`stockNewsProvider(symbol)`。
- **畫面**：新聞列表元件抽到 `widgets/news/` 共用並修時區；新聞頁篩選改成 `NewsFilter`（全部／自選／來源）；個股頁第 6 個分頁 `StockNewsTab`（lazy 清單、三種說明、重新整理按鈕）。

**Tech Stack:** Flutter／Dart 3.10、flutter_riverpod 3.3.1（riverpod 3.2.1）、go_router 17.1.0、drift 2.32.1、easy_localization、mocktail 1.0.4、flutter_test（版本以 `pubspec.lock` 為準；查套件原始碼看 `~/.pub-cache/hosted/pub.dev/<套件>-<版本>`）

**Spec:** `docs/plans/2026-10-06-stock-news-design.md`（a783ffae）。本計畫實作 spec 全部「設計」章節（§1–§6）與「驗證」。

## Global Constraints

- **比對結果不寫資料庫**：`news_stock_map` 的內容與寫入方式不變（評分 `NewsRule` 的輸入）。新程式碼不得出現 `NewsStockMapCompanion`、`insertNewsWithMappings`（Task 9 靜態守門）。
- **熱度不變**：`StockNameMatcher.fromStocks(...).match` 對全部標題的輸出逐則相同（Task 1 建基線、Task 1 與 Task 9 重放比對）；`NewsHeatParams` 不改、`dictionaryVersion` 不 bump。顯示專用設定一律放 `NewsLinkParams`。
- **CLI 編譯閉包純 Dart**：`StockNameMatcher` 在 launchd CLI 的閉包裡（快照服務），`news_link_params.dart`、`stock_name_matcher.dart`、`news_stock_links.dart`、`news_dedup.dart` 不得 import flutter／easy_localization；`.tr()` 只在 presentation。
- **Repository 介面**：新查詢放 DAO mixin，不加進 `INewsRepository`。
- **文案**：
  - 新字串 zh-TW、en 都要有，並在 `S`（`lib/core/l10n/app_strings.dart`）註冊（`app_strings_keys_test` 只掃 `S`）。
  - 不得出現 `no_investment_advice_copy_test` 的禁用詞。
  - 用詞一律「公告」（畫面上的篩選標籤就叫公告），不寫「重大訊息」。
  - 參數用具名 `{count}`。
- **公開 repo**：新測試的股票一律用虛構代碼（99xx）與虛構名稱；不得出現使用者的自選或持股。排除清單是全市場命中審查的結果，跟自選無關。
- **live DB 唯讀**：只用 `sqlite3 "file:$DB?mode=ro&immutable=1"` 讀（`DB` 是 App 容器裡的 `afterclose.sqlite`，容器路徑見 CLAUDE.md「命名邊界」），副本用 `VACUUM INTO` 放執行者的 scratchpad（下稱 `$SP`）。
- **暫存測試不提交**：`test/_scratch_news_test.dart` 只在本機搭配 `--dart-define` 跑，沒給參數時整檔 skip；Task 9 提交前刪除。
- **Bash 不保留環境變數**：每次呼叫都是新 shell，用到 `SP`、`DB` 的指令區塊開頭都要重設（`SP=<執行者的 scratchpad 目錄>/stocknews`；`DB="$HOME/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite"`）。副本約 660MB，兩份要留意磁碟空間。
- **提交**：
  - commit／push 只在使用者說「提交」時做。直接在 main，Conventional Commits、中文、純文字、不加 Co-Authored-By。
  - 每個 task 結尾「記錄進度」，整段在 Task 9 一次提交。
  - 不在 09:00–13:30 提交（post-commit hook 會重編 launchd CLI）。
- **測試行程**：跑 `flutter test` 前用 `ps -axo pid=,ppid=,etime=,comm= | grep -E '/(dart|flutter)$'` 確認沒有其他 `dart run`／`flutter test`／`flutter run`；IDEA 的 analysis server（ppid 是 idea）不算。
- **mutation**：在 scratchpad 的 repo 副本做，還原用備份檔、不用 git checkout；先確認副本基線全綠；先跑直接測試，存活者再跑全部消費者測試；編譯錯誤殺掉的不算。
- **審查者**：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。

## Review Focus

1. **斷網時在個股新聞分頁按重新整理**。預期：轉圈結束後跳「新聞來源都抓取失敗，顯示的是先前的新聞」，清單保留舊資料、不清空。測試在 Task 8。
2. **個股頁原地換股（巡檢翻頁）時新聞分頁正在載入**。預期：顯示新股票的新聞，不殘留上一檔。測試在 Task 8。
3. **台積電這種上千則的清單**。預期：只建構看得到的列，捲動不卡。測試在 Task 8（300 則只建構部分列）。
4. **標題用全形破折號寫 `-KY`（「戊己－KY」）**。預期：靠基底名照樣比對得到。測試在 Task 1。
5. **「自選」篩選開著時，從個股頁把最後一檔自選移除後返回**。預期：「自選」變 0 則、顯示「還沒有自選股或持股」。測試在 Task 7。

## 與 spec 的差異（核可計畫時一併確認）

- **排除名稱適用所有長度**：spec 說 3 字以上「原則上」用非公司詞組處理；實作上 `excludedNames` 不分長度，審查時照 spec 原則優先用詞組。
- **個股頁日期標題**：今天、昨天寫成「今天 10/6」「昨天 10/5」，其他日期「10/3」。
- **背景 isolate 判斷**：在測試模式（debug JIT，比 release 慢）量新聞頁比對耗時，≤ 100ms 就留在主 isolate（release 只會更快）。
- **個股新聞分頁不帶動外層收合**：`CustomScrollView(primary: false)`，與其他 5 個分頁一致（捲清單時上方報價區不收起）。
- **時區測試在 CI 會 skip**：CI 跑 UTC，「先轉本地再取日期」驗不到；這幾條在本機（台北）會跑。測試時刻依本機時差挑本地與 UTC 不同日的時刻（`test/helpers/time_zone_helpers.dart`）。

## 檔案結構

| 檔案 | 動作 | 責任 |
|:--|:--|:--|
| `lib/core/constants/news_link_params.dart` | 新增 | 排除名稱、非公司詞組、顯示專用別名、定案程序 |
| `lib/domain/services/news/stock_name_matcher.dart` | 修改 | `forNewsLinks`、`matchInOrder`、`namesOf`、`nameStatusOf`、`StockNameStatus` |
| `lib/domain/services/news/news_stock_links.dart` | 新增 | 代號 ∪ 簡稱合併（純函式） |
| `lib/domain/services/news/news_dedup.dart` | 新增 | 同日同標題去重（從 `NewsState` 抽出） |
| `lib/data/database/dao/user_dao.dart` | 修改 | `getWatchlistAndHoldingSymbols()` |
| `lib/data/database/dao/news_dao.dart` | 修改 | `getNewsCandidatesForStock()` |
| `lib/data/repositories/news_repository.dart` | 修改 | `syncMaterialInfo` 改用共用查詢 |
| `lib/presentation/providers/news_link_provider.dart` | 新增 | `newsLinkMatcherProvider` |
| `lib/presentation/providers/news_fetch_provider.dart` | 新增 | `newsDataVersionProvider`、`NewsFetchOutcome`、`NewsFetcher`、`newsFetcherProvider` |
| `lib/presentation/providers/news_heat_provider.dart` | 修改 | 監聽新聞資料版本 |
| `lib/presentation/providers/news_provider.dart` | 修改 | `NewsFilter`、相關股票、自選名單、共用抓新聞、載入世代 |
| `lib/presentation/providers/stock_news_provider.dart` | 新增 | `StockNews`、`stockNewsProvider` |
| `lib/presentation/widgets/news/news_grouping.dart` | 新增 | 三段分組、逐日分組（本地時間，純函式） |
| `lib/presentation/widgets/news/news_widgets.dart` | 新增 | 列表項目、股票標籤、區段標題、預覽、開連結、抓取回饋 |
| `lib/presentation/screens/news/news_screen.dart` | 修改 | 用共用元件、「自選」篩選、版本監聽、返回重讀自選 |
| `lib/presentation/screens/stock_detail/tabs/news_tab.dart` | 新增 | `StockNewsTab` |
| `lib/presentation/screens/stock_detail/stock_detail_screen.dart` | 修改 | 第 6 個分頁 |
| `lib/presentation/providers/stock_detail_state.dart` | 修改 | 刪 `recentNews` |
| `lib/core/l10n/app_strings.dart`、`assets/translations/{zh-TW,en}.json` | 修改 | 新字串 |
| `CHANGELOG.md` | 修改 | Added／Fixed |

---

### Task 1: 顯示用比對器與參數

**Files:**
- Create: `lib/core/constants/news_link_params.dart`
- Modify: `lib/domain/services/news/stock_name_matcher.dart`（整檔改寫）
- Test: `test/domain/services/news/stock_name_matcher_test.dart`（追加）、`test/core/constants/news_link_params_test.dart`（新增）
- Scratch（不提交）：`test/_scratch_news_test.dart`

**Interfaces:**
- Produces:
  - `enum StockNameStatus { matched, excluded, notListed }`
  - `StockNameMatcher.forNewsLinks(List<StockMasterEntry> stocks, {Set<String> excludedNames, Set<String> nonCompanyPhrases, Map<String, String> extraAliases})`
  - `Set<String> match(String title)`（語意不變）、`List<String> matchInOrder(String title)`、`List<String> namesOf(String symbol)`、`StockNameStatus nameStatusOf(String symbol)`
  - `abstract final class NewsLinkParams { excludedNames; nonCompanyPhrases; displayNameAliases; minNameLength }`

- [ ] **Step 1: 建資料庫副本與熱度基線（改程式前）**

```bash
SP=<執行者的 scratchpad 目錄>/stocknews   # 不放 repo、不放 /tmp
mkdir -p "$SP"
DB="$HOME/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite"
rm -f "$SP/replay.sqlite"
sqlite3 "file:$DB?mode=ro&immutable=1" "VACUUM INTO '$SP/replay.sqlite'"
```

建立 `test/_scratch_news_test.dart`（不提交）：

```dart
// 暫存：只在本機搭配 --dart-define 跑，不提交。
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';

const _db = String.fromEnvironment('NEWS_DB');
const _out = String.fromEnvironment('NEWS_OUT');

void main() {
  test(
    'heat replay dump',
    () async {
      // forToolFile 在路徑不存在時會建一個空資料庫——下限檢查防止在空資料上比出「一致」
      final db = AppDatabase.forToolFile(_db);
      final stocks = await db.getAllActiveStocks();
      final news = await (db.select(
        db.newsItem,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      expect(stocks.length, greaterThan(2000));
      final m = StockNameMatcher.fromStocks(stocks);
      final lines = [
        for (final n in news) '${n.id}\t${m.match(n.title).join(',')}',
      ];
      expect(
        lines.where((l) => !l.endsWith('\t')).length,
        greaterThan(1000),
        reason: '有比對結果的新聞太少，副本可能不對',
      );
      File(_out).writeAsStringSync('${lines.join('\n')}\n');
      await db.close();
    },
    timeout: Timeout.none,
    skip: _db.isEmpty ? '需要 --dart-define=NEWS_DB' : false,
  );
}
```

Run:
```bash
SP=<執行者的 scratchpad 目錄>/stocknews
flutter test test/_scratch_news_test.dart --plain-name 'heat replay dump' \
  --dart-define=NEWS_DB="$SP/replay.sqlite" --dart-define=NEWS_OUT="$SP/heat_before.tsv"
wc -l "$SP/heat_before.tsv"
```
Expected: PASS；行數等於副本的 `news_item` 列數（約 7,100）。注意 `match` 結果**不排序**直接 join：插入順序也要相同。

- [ ] **Step 2: 寫 `NewsLinkParams` 的守門測試（會因檔案不存在而失敗）**

`test/core/constants/news_link_params_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/news_link_params.dart';

void main() {
  test('排除名稱與非公司詞組至少 2 字、彼此不重疊', () {
    for (final n in [
      ...NewsLinkParams.excludedNames,
      ...NewsLinkParams.nonCompanyPhrases,
    ]) {
      expect(
        n.length,
        greaterThanOrEqualTo(NewsLinkParams.minNameLength),
        reason: n,
      );
    }
    expect(
      NewsLinkParams.excludedNames.intersection(
        NewsLinkParams.nonCompanyPhrases,
      ),
      isEmpty,
    );
  });
}
```

- [ ] **Step 3: 在 `stock_name_matcher_test.dart` 末尾（`main` 內最後）追加顯示用測試**

```dart
  test('熱度建法：match 與 matchInOrder 的命中集合相同', () {
    for (final t in ['長榮航與長榮海運齊漲', '台積電漲！台積電再創高', '今彩539頭獎開出']) {
      expect(matcher.matchInOrder(t).toSet(), matcher.match(t));
    }
  });

  group('forNewsLinks（新聞顯示用）', () {
    StockNameMatcher display(
      List<StockMasterEntry> stocks, {
      Set<String> excluded = const {},
      Set<String> phrases = const {},
    }) => StockNameMatcher.forNewsLinks(
      stocks,
      excludedNames: excluded,
      nonCompanyPhrases: phrases,
      extraAliases: const {},
    );

    test('2 字名稱預設比對得到（熱度建法比對不到）', () {
      final stocks = [stock('9901', '甲乙')];
      expect(display(stocks).match('甲乙營收創新高'), {'9901'});
      expect(StockNameMatcher.fromStocks(stocks).match('甲乙營收創新高'), isEmpty);
    });

    test('排除名稱比對不到', () {
      final m = display([stock('9902', '常見')], excluded: {'常見'});
      expect(m.match('常見問題一次看'), isEmpty);
    });

    test('非公司詞組只擋它涵蓋的位置：東南洋不算南洋、單獨的南洋照算', () {
      final m = display([stock('9911', '南洋')], phrases: {'東南洋'});
      expect(m.match('進軍東南洋布局'), isEmpty);
      expect(m.match('南洋營收創新高'), {'9911'});
    });

    test('詞組擋住跨界的 2 字名：東南洋航線不配洋航', () {
      final stocks = [stock('9912', '洋航')];
      expect(display(stocks, phrases: {'東南洋'}).match('東南洋航線運價'), isEmpty);
      // 對照：沒有詞組時會被洋航搶走
      expect(display(stocks).match('東南洋航線運價'), {'9912'});
    });

    test('同長重疊時非公司詞組優先（不靠字典序）', () {
      // 「南洋科」(U+5357) 字典序在「東南洋」(U+6771) 前；同長若依字典序，
      // 南洋科會先搶到位置
      final m = display([stock('9913', '南洋科')], phrases: {'東南洋'});
      expect(m.match('東南洋科技展'), isEmpty);
      expect(m.match('南洋科營收'), {'9913'});
    });

    test('更長的公司名蓋過較短的詞組', () {
      final m = display([stock('9914', '東南洋科技')], phrases: {'東南洋'});
      expect(m.match('東南洋科技公告'), {'9914'});
    });

    test('長名稱優先：測試電子不算測試', () {
      final m = display([stock('9907', '測試電子'), stock('9908', '測試')]);
      expect(m.match('測試電子營收'), {'9907'});
    });

    test('名稱去掉 *（熱度建法照原字串比對不到）', () {
      final stocks = [stock('9903', '丙丁*')];
      expect(display(stocks).match('丙丁股價大跌'), {'9903'});
      expect(StockNameMatcher.fromStocks(stocks).match('丙丁股價大跌'), isEmpty);
    });

    test('-KY 後綴另收基底名，全名照樣比對得到', () {
      final m = display([stock('9904', '戊己-KY')]);
      expect(m.match('戊己營收年增'), {'9904'});
      expect(m.match('戊己-KY 營收年增'), {'9904'});
    });

    test('標題用全形破折號寫後綴時，靠基底名比對得到', () {
      final m = display([stock('9904', '戊己-KY')]);
      expect(m.match('戊己－KY營收年增'), {'9904'});
    });

    test('* 與 -創 同時出現：去 * 後取基底名', () {
      final m = display([stock('9909', '辛壬*-創')]);
      expect(m.match('辛壬掛牌'), {'9909'});
    });

    test('基底名受排除清單約束，全名不受影響', () {
      final m = display([stock('9905', '常見-KY')], excluded: {'常見'});
      expect(m.match('常見問題一次看'), isEmpty);
      expect(m.match('常見-KY 公告'), {'9905'});
    });

    test('1 字名稱不比對', () {
      expect(display([stock('9906', '庚')]).match('庚公司公告'), isEmpty);
    });

    test('熱度別名照用：日月光指向 3711', () {
      final m = display([stock('3711', '日月光投控')]);
      expect(m.match('日月光法說會'), {'3711'});
    });

    test('matchInOrder 依標題出現位置排序、同檔只列一次', () {
      final m = display([stock('9901', '甲乙'), stock('9907', '測試電子')]);
      // 掃描順序是長名稱優先（9907 先），出現位置是甲乙在前——不排序會得到 [9907, 9901]
      expect(m.matchInOrder('甲乙與測試電子齊漲，甲乙再創高'), ['9901', '9907']);
    });

    test('namesOf 列出這檔的所有名稱（含基底名）', () {
      final m = display([stock('9904', '戊己-KY')]);
      expect(m.namesOf('9904').toSet(), {'戊己-KY', '戊己'});
      expect(m.namesOf('0000'), isEmpty);
    });

    test('nameStatusOf：有名稱／名稱全被排除／不在清單', () {
      final m = display([
        stock('9901', '甲乙'),
        stock('9902', '常見'),
      ], excluded: {'常見'});
      expect(m.nameStatusOf('9901'), StockNameStatus.matched);
      expect(m.nameStatusOf('9902'), StockNameStatus.excluded);
      expect(m.nameStatusOf('9999'), StockNameStatus.notListed);
    });
  });
```

- [ ] **Step 4: 跑測試確認失敗**

Run: `flutter test test/domain/services/news/stock_name_matcher_test.dart test/core/constants/news_link_params_test.dart`
Expected: 編譯失敗（`news_link_params.dart` 不存在、`forNewsLinks`／`matchInOrder`／`StockNameStatus` 未定義）。

- [ ] **Step 5: 建立 `lib/core/constants/news_link_params.dart`**

清單是 2026-10-06 粗擬版，Task 9 照定案程序審完後改寫成定案版（含審查紀錄）。

```dart
/// 新聞「相關股票」的顯示用簡稱比對參數（新聞頁「自選」篩選與股票標籤、
/// 個股頁「新聞」分頁）
///
/// 與熱度分析的 `NewsHeatParams` 分開：熱度排行要嚴（2 字名只收白名單），
/// 顯示清單可寬（2 字名預設收、只擋審過的誤配）。這裡的異動不影響熱度與
/// `news_mention_daily` 快照，不需 bump `NewsHeatParams.dictionaryVersion`。
/// 比對結果只供顯示，不得寫入 `news_stock_map`（評分的輸入）。
///
/// **定案程序**（調整清單時照做）：
/// 1. 對 App 資料庫副本（`VACUUM INTO`）以 `StockNameMatcher.forNewsLinks`
///    全量重跑標題比對，統計每檔命中數並抽樣標題。
/// 2. 2 字名稱：30 天內出現 3 次以上的全部審；3 字以上：命中前 30 名抽樣。
/// 3. 誤配來自更長詞彙的，把詞彙放 [nonCompanyPhrases]（優先，較精準）；
///    名稱本身就是常見詞、找不到可佔位的詞彙，才放 [excludedNames]。
/// 4. [nonCompanyPhrases] 不得包含任何 3 字以上有效公司名（會靜默吃掉那家
///    公司的比對），例外逐條註明理由。
/// 5. 審查日期、語料規模、處理的名稱記在下方與 commit 訊息。
abstract final class NewsLinkParams {
  /// 整個名稱不拿來比對（名稱本身是常見詞）。任何長度都適用，含 `-` 後綴的基底名
  static const Set<String> excludedNames = {
    '全台',
    '台南',
    '聯合',
    '冠軍',
    '數字',
    '新產',
    '新興',
    '大量',
    '全新',
    '綠電',
  };

  /// 非公司詞組：比對時先佔住字元位置、不對應任何股票
  static const Set<String> nonCompanyPhrases = {
    '東南亞',
    '海力士',
    '中華信評',
    '串聯亞',
    '北台灣',
  };

  /// 顯示專用別名（名稱 → 代碼），與 `NewsHeatParams.nameAliasToSymbol` 合併使用。
  /// 顯示要補別名加在這裡，不動熱度的別名表
  static const Map<String, String> displayNameAliases = {};

  /// 名稱至少幾個字才拿來比對
  static const int minNameLength = 2;
}
```

- [ ] **Step 6: 改寫 `lib/domain/services/news/stock_name_matcher.dart`**

```dart
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
```

- [ ] **Step 7: 跑測試確認通過**

Run: `flutter test test/domain/services/news/ test/core/constants/news_link_params_test.dart test/presentation/providers/news_heat_provider_test.dart test/domain/services/update/`
Expected: 全部 PASS（熱度既有 14 條一條不改）。

- [ ] **Step 8: 熱度全量重放比對**

```bash
SP=<執行者的 scratchpad 目錄>/stocknews
flutter test test/_scratch_news_test.dart --plain-name 'heat replay dump' \
  --dart-define=NEWS_DB="$SP/replay.sqlite" --dart-define=NEWS_OUT="$SP/heat_after.tsv"
cmp "$SP/heat_before.tsv" "$SP/heat_after.tsv" && echo IDENTICAL
```
Expected: `IDENTICAL`。有差異就是 `fromStocks` 行為變了，回頭查（不得改基線檔）。

- [ ] **Step 9: analyze 並記錄進度**

Run: `flutter analyze`
Expected: No issues found（`test/_scratch_news_test.dart` 也要乾淨）。記錄進度（不 commit）。

---

### Task 2: 相關股票合併與去重（domain 純函式）

**Files:**
- Create: `lib/domain/services/news/news_stock_links.dart`、`lib/domain/services/news/news_dedup.dart`
- Modify: `lib/presentation/providers/news_provider.dart`（`NewsState` 改呼叫 `NewsDedup`，刪掉搬走的私有成員）
- Test: `test/domain/services/news/news_stock_links_test.dart`、`test/domain/services/news/news_dedup_test.dart`（新增）
- Create（測試 helper）: `test/helpers/time_zone_helpers.dart`

**Interfaces:**
- Consumes: `StockNameMatcher.matchInOrder`（Task 1）
- Produces（測試用）: `DateTime? crossDayLocal(int year, int month, int day)`
- Produces:
  - `NewsStockLinks.merge({required List<NewsItemEntry> news, required Map<String, List<String>> codeMap, required StockNameMatcher matcher}) → Map<String, List<String>>`
  - `NewsDedup.sameDayTitle(List<NewsItemEntry> items) → List<NewsItemEntry>`（新到舊）

- [ ] **Step 1: 寫失敗的測試**

`test/domain/services/news/news_stock_links_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/news_stock_links.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';

NewsItemEntry news(String id, String title) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: title,
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: DateTime(2026, 10, 6, 9),
  fetchedAt: DateTime(2026, 10, 6, 9),
);

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  isActive: true,
  updatedAt: DateTime(2026, 10, 6),
);

void main() {
  final matcher = StockNameMatcher.forNewsLinks(
    [stock('9901', '甲乙'), stock('9907', '測試電子')],
    excludedNames: const {},
    nonCompanyPhrases: const {},
    extraAliases: const {},
  );

  Map<String, List<String>> merge(
    List<NewsItemEntry> items, [
    Map<String, List<String>> codeMap = const {},
  ]) => NewsStockLinks.merge(news: items, codeMap: codeMap, matcher: matcher);

  test('代號在前（依代號排序）、簡稱在後（依標題位置）', () {
    // 甲乙出現在前、但掃描順序是測試電子（較長）先
    final r = merge(
      [news('n1', '甲乙與測試電子齊漲')],
      {
        'n1': ['9920', '9910'],
      },
    );
    expect(r['n1'], ['9910', '9920', '9901', '9907']);
  });

  test('代號與名稱都命中同一檔只列一次', () {
    final r = merge(
      [news('n1', '甲乙(9901)營收')],
      {
        'n1': ['9901'],
      },
    );
    expect(r['n1'], ['9901']);
  });

  test('代號對應重複只列一次', () {
    final r = merge(
      [news('n1', '公告')],
      {
        'n1': ['9930', '9930'],
      },
    );
    expect(r['n1'], ['9930']);
  });

  test('只有代號對應（標題沒有名稱）照收', () {
    final r = merge(
      [news('n1', '公告一則')],
      {
        'n1': ['9930'],
      },
    );
    expect(r['n1'], ['9930']);
  });

  test('沒有任何相關股票的新聞不在結果裡', () {
    expect(merge([news('n1', '大盤收高')]).containsKey('n1'), isFalse);
  });
}
```

`test/helpers/time_zone_helpers.dart`：

```dart
/// 本地日期與 UTC 日期不同的一個時刻（驗「先轉本地再取日期」用）。
///
/// 時差為正：本地 00:00:30（UTC 還在前一天）；為負：本地 23:59:30（UTC 已是
/// 隔天）；UTC 時區回 null——驗不到，測試應 skip（CI 跑 UTC 會 skip）。
DateTime? crossDayLocal(int year, int month, int day) {
  final offset = DateTime(year, month, day, 12).timeZoneOffset;
  if (offset == Duration.zero) return null;
  return offset.isNegative
      ? DateTime(year, month, day, 23, 59, 30)
      : DateTime(year, month, day, 0, 0, 30);
}
```

`test/domain/services/news/news_dedup_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/news_dedup.dart';

import '../../../helpers/time_zone_helpers.dart';

NewsItemEntry item(String id, String title, DateTime publishedAt) =>
    NewsItemEntry(
      id: id,
      source: '鉅亨網',
      title: title,
      url: 'https://example.com/$id',
      category: 'OTHER',
      publishedAt: publishedAt,
      fetchedAt: publishedAt,
    );

void main() {
  test('同日同標題保留最早一筆、結果新到舊', () {
    final r = NewsDedup.sameDayTitle([
      item('late', '同一標題', DateTime(2026, 10, 6, 12)),
      item('early', '同一標題', DateTime(2026, 10, 6, 9)),
      item('other', '另一則', DateTime(2026, 10, 6, 10)),
    ]);
    expect(r.map((n) => n.id), ['other', 'early']);
  });

  test('不同天的同標題都保留', () {
    final r = NewsDedup.sameDayTitle([
      item('d1', '期貨行情', DateTime(2026, 10, 5, 9)),
      item('d2', '期貨行情', DateTime(2026, 10, 6, 9)),
    ]);
    expect(r, hasLength(2));
  });

  test('剝【…】前綴與全形空白後視為同一則', () {
    final r = NewsDedup.sameDayTitle([
      item('a', '【台股盤中】 加權指數　上漲', DateTime(2026, 10, 6, 10)),
      item('b', '加權指數 上漲', DateTime(2026, 10, 6, 9)),
    ]);
    expect(r.map((n) => n.id), ['b']);
  });

  final cross = crossDayLocal(2026, 10, 6);
  test(
    '以本地日期判斷同日（UTC 時間先轉本地）',
    () {
      // cross 與本地 12:00 同在本地 10/6，但 UTC 日期不同
      final a = item('a', '同一標題', cross!.toUtc());
      final b = item('b', '同一標題', DateTime(2026, 10, 6, 12).toUtc());
      expect(NewsDedup.sameDayTitle([a, b]), hasLength(1));
    },
    skip: cross == null ? 'UTC 時區驗不到跨日' : false,
  );
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/domain/services/news/news_stock_links_test.dart test/domain/services/news/news_dedup_test.dart`
Expected: 編譯失敗（檔案不存在）。

- [ ] **Step 3: 建立 `lib/domain/services/news/news_stock_links.dart`**

```dart
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';

/// 新聞的相關股票＝代號對應（news_stock_map）∪ 標題簡稱比對（顯示用）
///
/// 只供顯示：結果不得寫入 news_stock_map（評分的輸入）。
abstract final class NewsStockLinks {
  /// newsId → 相關股票代碼，不重複。順序：代號對應在前（依代號排序），
  /// 簡稱比對在後（依在標題出現的位置）。沒有任何相關股票的新聞不在 map 裡。
  static Map<String, List<String>> merge({
    required List<NewsItemEntry> news,
    required Map<String, List<String>> codeMap,
    required StockNameMatcher matcher,
  }) {
    final result = <String, List<String>>{};
    for (final n in news) {
      final codes = [...?codeMap[n.id]]..sort();
      final seen = <String>{};
      final symbols = [
        for (final s in codes)
          if (seen.add(s)) s,
        for (final s in matcher.matchInOrder(n.title))
          if (seen.add(s)) s,
      ];
      if (symbols.isNotEmpty) result[n.id] = symbols;
    }
    return result;
  }
}
```

- [ ] **Step 4: 建立 `lib/domain/services/news/news_dedup.dart`，並從 `NewsState` 搬出**

```dart
import 'package:daredevil/data/database/app_database.dart';

/// 新聞顯示去重（新聞頁與個股新聞分頁共用）
///
/// 規則：**正規化標題 + 發布日（本地時間）** 分組，保留組內最早發布的那筆
/// （原始媒體優先於聚合轉載）。「同日」約束必要——語料驗證顯示跨天的同標題
/// （如每日期貨行情欄目）是不同新聞，不可合併。僅影響顯示層，DB 與個股
/// 關聯評分不受影響。
abstract final class NewsDedup {
  /// 去重後依發布時間新到舊排序
  static List<NewsItemEntry> sameDayTitle(List<NewsItemEntry> items) {
    final best = <String, NewsItemEntry>{};
    for (final n in items) {
      final day = n.publishedAt.toLocal();
      final key =
          '${day.year}-${day.month}-${day.day}|${_normalizeTitle(n.title)}';
      final current = best[key];
      if (current == null || n.publishedAt.isBefore(current.publishedAt)) {
        best[key] = n;
      }
    }
    return best.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  /// 全形/半形空白（`\s` 不保證涵蓋 U+3000，故顯式列入）
  static final RegExp _whitespace = RegExp(r'[\s　]+');

  /// 聚合器品牌化前綴（如 Yahoo 轉載通訊社稿加掛的「【台股盤中】」
  /// 「【盤前焦點】」）——剝除後才能與原始稿合併去重。上限 12 字防
  /// 誤剝正文（語料實測前綴均 ≤ 6 字）。
  static final RegExp _brandPrefix = RegExp(r'^【[^】]{1,12}】');

  /// 標題正規化（僅用於去重 key，顯示仍用原標題）：
  /// 剝【…】前綴 → 全形/半形空白折疊為單一空格
  static String _normalizeTitle(String title) {
    return title
        .replaceFirst(_brandPrefix, '')
        .replaceAll(_whitespace, ' ')
        .trim();
  }
}
```

`news_provider.dart` 的 `NewsState`：
- 刪掉 `_deduplicate`、`_whitespace`、`_brandPrefix`、`_normalizeTitle`；
- `_dedupedBySource` 的 doc 改為「各檢視（全部／單一來源）去重後的清單，建構時算一次；規則見 `NewsDedup`。去重在來源過濾**之後**做：全部檢視隱藏轉載、單一來源檢視仍看得到該來源自己的那份。」；
- 其中 `_deduplicate(` 改 `NewsDedup.sameDayTitle(`，並 import `package:daredevil/domain/services/news/news_dedup.dart`。

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/domain/services/news/ test/presentation/providers/news_provider_test.dart`
Expected: 全部 PASS（`news_provider_test` 的去重測試一條不改照樣通過）。

- [ ] **Step 6: analyze 並記錄進度**

Run: `flutter analyze` → No issues found。記錄進度。

---

### Task 3: 資料層（自選∪持股、個股新聞候選、公告同步）

**Files:**
- Modify: `lib/data/database/dao/user_dao.dart`、`lib/data/database/dao/news_dao.dart`、`lib/data/repositories/news_repository.dart:115-154`
- Test: `test/data/database/dao/watchlist_holding_symbols_test.dart`（新增）、`test/data/database/dao/news_candidates_test.dart`（新增）、`test/data/repositories/news_repository_test.dart`（`syncMaterialInfo` 群組改寫）

**Interfaces:**
- Produces:
  - `Future<Set<String>> AppDatabase.getWatchlistAndHoldingSymbols()`
  - `Future<List<NewsItemEntry>> AppDatabase.getNewsCandidatesForStock({required String symbol, required List<String> names, required DateTime since})`（新到舊）

- [ ] **Step 1: 寫失敗的 DAO 測試**

`test/data/database/dao/watchlist_holding_symbols_test.dart`：

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9901', '9902', '9903', '9904'])
        StockMasterCompanion.insert(symbol: s, name: '測$s', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  Future<void> hold(String symbol, double quantity) =>
      db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: symbol,
          quantity: Value(quantity),
        ),
      );

  test('自選∪持股（數量 > 0），已清倉的持股不算', () async {
    await db.addToWatchlist('9901');
    await db.addToWatchlist('9904');
    await hold('9902', 1000);
    await hold('9903', 0);
    await hold('9904', 500);

    expect(await db.getWatchlistAndHoldingSymbols(), {'9901', '9902', '9904'});
  });

  test('都沒有時回空集合', () async {
    expect(await db.getWatchlistAndHoldingSymbols(), isEmpty);
  });
}
```

`test/data/database/dao/news_candidates_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final since = DateTime.utc(2026, 9, 6, 13);

  NewsItemCompanion row(String id, String title, DateTime at) =>
      NewsItemCompanion.insert(
        id: id,
        source: '鉅亨網',
        title: title,
        url: 'https://example.com/$id',
        category: 'OTHER',
        publishedAt: at,
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '9901', name: '甲乙', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9909', name: 'ABC', market: 'TWSE'),
    ]);
    await db.insertNewsWithMappings(
      [
        row('in-name', '甲乙營收創新高', since.add(const Duration(hours: 1))),
        row('in-code', '某公司(9901)公告', since.add(const Duration(hours: 2))),
        row('edge', '甲乙剛好在界線', since),
        row('old', '甲乙舊聞', since.subtract(const Duration(minutes: 1))),
        row('other', '丙丁營收', since.add(const Duration(hours: 3))),
        row('lower', 'abc 新產品', since.add(const Duration(hours: 4))),
      ],
      [NewsStockMapCompanion.insert(newsId: 'in-code', symbol: '9901')],
    );
  });

  tearDown(() => db.close());

  Future<List<String>> ids(String symbol, List<String> names, DateTime s) async =>
      [
        for (final n in await db.getNewsCandidatesForStock(
          symbol: symbol,
          names: names,
          since: s,
        ))
          n.id,
      ];

  test('代號對應或標題含名稱、截止點含當下、新到舊', () async {
    expect(await ids('9901', ['甲乙'], since), ['in-code', 'in-name', 'edge']);
  });

  test('截止點傳本地或 UTC 時間結果相同（drift 以 julianday 比較）', () async {
    expect(await ids('9901', ['甲乙'], since.toLocal()), [
      'in-code',
      'in-name',
      'edge',
    ]);
  });

  test('沒有名稱時只回代號對應', () async {
    expect(await ids('9901', const [], since), ['in-code']);
  });

  test('標題比對分大小寫、不吃萬用字元（instr，不是 LIKE）', () async {
    expect(await ids('9909', ['ABC'], since), isEmpty);
    expect(await ids('9909', ['%'], since), isEmpty);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/database/dao/watchlist_holding_symbols_test.dart test/data/database/dao/news_candidates_test.dart`
Expected: 編譯失敗（方法未定義）。

- [ ] **Step 3: 實作兩個 DAO 方法**

`lib/data/database/dao/user_dao.dart`（`UserDaoMixin` 內、`getWatchlist()` 之後）：

```dart
  /// 自選∪持股（數量 > 0）的股票代碼——新聞「自選」篩選與公告同步共用
  Future<Set<String>> getWatchlistAndHoldingSymbols() async {
    final watched =
        await (selectOnly(watchlist)..addColumns([watchlist.symbol]))
            .map((r) => r.read(watchlist.symbol)!)
            .get();
    final held =
        await (selectOnly(portfolioPosition)
              ..addColumns([portfolioPosition.symbol])
              ..where(portfolioPosition.quantity.isBiggerThanValue(0)))
            .map((r) => r.read(portfolioPosition.symbol)!)
            .get();
    return {...watched, ...held};
  }
```

`lib/data/database/dao/news_dao.dart`（`NewsDaoMixin` 內、`getNewsStockMappingsBatch` 之後）：

```dart
  /// 個股新聞的候選：[since] 之後、代號對應到 [symbol] 或標題含 [names] 任一者，新到舊
  ///
  /// 標題比對用 `instr()`（分大小寫、不吃 `%`／`_` 萬用字元）。時間比較由
  /// drift 換成 `julianday()` 兩邊比（DateTime 以文字儲存時的行為），截止點
  /// 傳本地或 UTC 時間結果相同。
  Future<List<NewsItemEntry>> getNewsCandidatesForStock({
    required String symbol,
    required List<String> names,
    required DateTime since,
  }) {
    final mappedIds = selectOnly(newsStockMap)
      ..addColumns([newsStockMap.newsId])
      ..where(newsStockMap.symbol.equals(symbol));
    Expression<bool> matches = newsItem.id.isInQuery(mappedIds);
    for (final name in names) {
      matches =
          matches |
          FunctionCallExpression<int>('instr', [
            newsItem.title,
            Variable<String>(name),
          ]).isBiggerThanValue(0);
    }
    return (select(newsItem)
          ..where((t) => t.publishedAt.isBiggerOrEqualValue(since) & matches)
          ..orderBy([(t) => OrderingTerm.desc(t.publishedAt)]))
        .get();
  }
```

- [ ] **Step 4: 跑 DAO 測試確認通過**

Run: `flutter test test/data/database/dao/watchlist_holding_symbols_test.dart test/data/database/dao/news_candidates_test.dart`
Expected: PASS。

- [ ] **Step 5: `syncMaterialInfo` 改用共用查詢——先改寫測試成真資料庫**

把 `test/data/repositories/news_repository_test.dart` 的 `group('syncMaterialInfo', ...)` 整組換成：

```dart
  group('syncMaterialInfo', () {
    late MockTwseClient client;
    late AppDatabase db;
    late NewsRepository repo2;

    TwseMaterialInfo mat({required String code, String subject = '公告'}) {
      return TwseMaterialInfo.fromJson({
        '發言日期': '1150723',
        '發言時間': '151812',
        '公司代號': code,
        '公司名稱': 'X',
        '主旨 ': subject,
        '說明': '',
      });
    }

    setUp(() async {
      client = MockTwseClient();
      db = AppDatabase.forTesting();
      await db.upsertStocks([
        for (final s in ['9901', '9902', '9903', '9904'])
          StockMasterCompanion.insert(symbol: s, name: '測$s', market: 'TWSE'),
      ]);
      repo2 = NewsRepository(
        database: db,
        rssParser: mockRssParser,
        twseClient: client,
      );
    });

    tearDown(() => db.close());

    test('只收自選∪持股（數量 > 0）、穩定 id、寫入新聞與股票關聯', () async {
      await db.addToWatchlist('9901');
      await db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: '9902',
          quantity: const Value(1000),
        ),
      );
      await db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: '9903',
          quantity: const Value(0),
        ),
      );
      when(() => client.getMaterialInformation()).thenAnswer(
        (_) async => [
          mat(code: '9901', subject: '受邀參加法人說明會'),
          mat(code: '9902', subject: '董事會決議'),
          mat(code: '9903', subject: '已清倉的公告'),
          mat(code: '9904', subject: '非自選公告'),
        ],
      );

      final count = await repo2.syncMaterialInfo();

      expect(count, 2);
      final items = await db.select(db.newsItem).get();
      expect(items.map((n) => n.id).toSet(), {
        'mops_9901_1150723_151812',
        'mops_9902_1150723_151812',
      });
      expect(items.every((n) => n.source == '重大訊息'), isTrue);
      final maps = await db.select(db.newsStockMap).get();
      expect(maps.map((m) => m.symbol).toSet(), {'9901', '9902'});
    });

    test('沒有自選也沒有持股時不打 API、回 0', () async {
      expect(await repo2.syncMaterialInfo(), 0);
      verifyNever(() => client.getMaterialInformation());
    });

    test('未注入 client 回 0', () async {
      final bare = NewsRepository(database: db, rssParser: mockRssParser);
      expect(await bare.syncMaterialInfo(), 0);
    });
  });
```

（`drift` 已以 `hide isNull, isNotNull` import，`Value` 可用。）

Run: `flutter test test/data/repositories/news_repository_test.dart --plain-name syncMaterialInfo`
Expected: PASS（現行實作行為相同；這一步確認新測試對現行碼成立）。

- [ ] **Step 6: 改 `syncMaterialInfo`**

`lib/data/repositories/news_repository.dart`，把

```dart
    final watchlistEntries = await _db.getWatchlist();
    final portfolioPositions = await _db.getPortfolioPositions();
    final symbols = <String>{
      ...watchlistEntries.map((e) => e.symbol),
      ...portfolioPositions.map((e) => e.symbol),
    };
    if (symbols.isEmpty) return 0;
```

換成

```dart
    final symbols = await _db.getWatchlistAndHoldingSymbols();
    if (symbols.isEmpty) return 0;
```

Run: `flutter test test/data/`
Expected: 全部 PASS。

- [ ] **Step 7: analyze 並記錄進度**

Run: `flutter analyze` → No issues found。記錄進度。

---

### Task 4: 比對器 provider、共用抓新聞、新聞資料版本

**Files:**
- Create: `lib/presentation/providers/news_link_provider.dart`、`lib/presentation/providers/news_fetch_provider.dart`
- Modify: `lib/presentation/providers/news_heat_provider.dart`
- Test: `test/presentation/providers/news_fetch_provider_test.dart`（新增）、`test/presentation/providers/news_link_provider_test.dart`（新增）、`test/presentation/providers/news_heat_provider_test.dart`（追加）

**Interfaces:**
- Consumes: `StockNameMatcher.forNewsLinks`（Task 1）
- Produces:
  - `final newsLinkMatcherProvider = FutureProvider<StockNameMatcher>`
  - `final newsDataVersionProvider = NotifierProvider<NewsDataVersion, int>`（`bump()`）
  - `class NewsFetchOutcome { int totalSources; int failedSources; bool allFailed; bool partiallyFailed }`
  - `class NewsFetcher { Future<NewsFetchOutcome> fetch() }`、`final newsFetcherProvider = Provider<NewsFetcher>`

- [ ] **Step 1: 寫失敗的測試**

`test/presentation/providers/news_fetch_provider_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/domain/models/news_feed.dart';
import 'package:daredevil/domain/repositories/news_repository.dart'
    show NewsSyncResult;
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class MockNewsRepository extends Mock implements NewsRepository {}

NewsFeedError feedError(String source) => NewsFeedError(
  sourceName: source,
  url: 'https://example.com/$source',
  error: 'timeout',
  timestamp: DateTime(2026, 10, 6),
);

void main() {
  late MockNewsRepository repo;
  late ProviderContainer container;
  final total = NewsFeedSource.defaultSources.length;

  setUp(() {
    repo = MockNewsRepository();
    container = ProviderContainer(
      overrides: [newsRepositoryProvider.overrideWithValue(repo)],
    );
  });

  tearDown(() => container.dispose());

  test('併發兩次只抓一次、拿到同一個結果、版本只遞增一次', () async {
    final gate = Completer<NewsSyncResult>();
    when(() => repo.syncNews()).thenAnswer((_) => gate.future);
    final fetcher = container.read(newsFetcherProvider);

    final a = fetcher.fetch();
    final b = fetcher.fetch();
    gate.complete(const NewsSyncResult(itemsAdded: 1, errors: []));

    final results = await Future.wait([a, b]);
    expect(identical(results[0], results[1]), isTrue);
    verify(() => repo.syncNews()).called(1);
    expect(container.read(newsDataVersionProvider), 1);
  });

  test('依序兩次就抓兩次、版本遞增兩次', () async {
    when(
      () => repo.syncNews(),
    ).thenAnswer((_) async => const NewsSyncResult(itemsAdded: 0, errors: []));
    final fetcher = container.read(newsFetcherProvider);

    await fetcher.fetch();
    await fetcher.fetch();

    verify(() => repo.syncNews()).called(2);
    expect(container.read(newsDataVersionProvider), 2);
  });

  test('部分來源失敗：同一來源多筆錯誤只算一個', () async {
    when(() => repo.syncNews()).thenAnswer(
      (_) async => NewsSyncResult(
        itemsAdded: 3,
        errors: [feedError('中央社'), feedError('中央社'), feedError('自由財經')],
      ),
    );

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.failedSources, 2);
    expect(o.partiallyFailed, isTrue);
    expect(o.allFailed, isFalse);
  });

  test('全部來源失敗', () async {
    when(() => repo.syncNews()).thenAnswer(
      (_) async => NewsSyncResult(
        itemsAdded: 0,
        errors: [
          for (final s in NewsFeedSource.defaultSources) feedError(s.name),
        ],
      ),
    );

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.allFailed, isTrue);
    expect(o.partiallyFailed, isFalse);
  });

  test('syncNews 拋例外：當成全部失敗，版本照樣遞增', () async {
    when(() => repo.syncNews()).thenThrow(Exception('db locked'));

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.failedSources, total);
    expect(o.allFailed, isTrue);
    expect(container.read(newsDataVersionProvider), 1);
  });

  test('全部成功：沒有失敗', () async {
    when(
      () => repo.syncNews(),
    ).thenAnswer((_) async => const NewsSyncResult(itemsAdded: 5, errors: []));

    final o = await container.read(newsFetcherProvider).fetch();

    expect(o.allFailed, isFalse);
    expect(o.partiallyFailed, isFalse);
  });
}
```

`test/presentation/providers/news_link_provider_test.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  isActive: true,
  updatedAt: DateTime(2026, 10, 6),
);

void main() {
  test('用有效股票建顯示用比對器，每日更新後重建', () async {
    final db = MockAppDatabase();
    when(
      () => db.getAllActiveStocks(),
    ).thenAnswer((_) async => [stock('9901', '甲乙')]);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(newsLinkMatcherProvider, (_, _) {});
    addTearDown(sub.close);

    final m = await container.read(newsLinkMatcherProvider.future);
    expect(m.match('甲乙營收'), {'9901'}); // 2 字名預設收＝顯示用建法

    container.read(dataUpdateEpochProvider.notifier).bump();
    await container.read(newsLinkMatcherProvider.future);
    verify(() => db.getAllActiveStocks()).called(2);
  });
}
```

`test/presentation/providers/news_heat_provider_test.dart` 末尾 `main` 內追加（沿用檔內既有的 `container`、`mockNewsRepo` 與 stub；若該檔的 `setUp` 未 stub `getRecentNews`，照檔內其他測試的寫法補 stub）：

```dart
  test('新聞資料版本遞增後重算熱度', () async {
    final sub = container.listen(newsHeatProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(newsHeatProvider.future);
    clearInteractions(mockNewsRepo);

    container.read(newsDataVersionProvider.notifier).bump();
    await container.read(newsHeatProvider.future);

    verify(
      () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
    ).called(1);
  });
```

（加 `import 'package:daredevil/presentation/providers/news_fetch_provider.dart';`）

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/providers/news_fetch_provider_test.dart test/presentation/providers/news_link_provider_test.dart test/presentation/providers/news_heat_provider_test.dart`
Expected: 編譯失敗（檔案不存在）。

- [ ] **Step 3: 建立 `lib/presentation/providers/news_link_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 新聞顯示用的簡稱比對器（新聞頁股票標籤與「自選」、個股新聞分頁共用）
///
/// 股票清單只在每日更新後變動，隨 [dataUpdateEpochProvider] 重建。
final newsLinkMatcherProvider = FutureProvider<StockNameMatcher>((ref) async {
  ref.watch(dataUpdateEpochProvider);
  final stocks = await ref.read(databaseProvider).getAllActiveStocks();
  return StockNameMatcher.forNewsLinks(stocks);
});
```

- [ ] **Step 4: 建立 `lib/presentation/providers/news_fetch_provider.dart`**

```dart
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/request_deduplicator.dart';
import 'package:daredevil/domain/models/news_feed.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 新聞資料版本：每次「抓新聞」完成（不論成敗）遞增。
///
/// 新聞頁畫面、熱度分析、個股新聞監聽它重讀——讓任一處觸發的抓取，其他
/// 開著的畫面都看得到新資料。
final newsDataVersionProvider = NotifierProvider<NewsDataVersion, int>(
  NewsDataVersion.new,
);

class NewsDataVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

/// 一次抓新聞的結果（給按重新整理的人看的回饋）
@immutable
class NewsFetchOutcome {
  const NewsFetchOutcome({
    required this.totalSources,
    required this.failedSources,
  });

  final int totalSources;
  final int failedSources;

  bool get allFailed => totalSources > 0 && failedSources >= totalSources;

  bool get partiallyFailed => failedSources > 0 && !allFailed;
}

/// 新聞頁與個股新聞分頁共用的「抓新聞」（只抓 RSS；公告由每日更新抓）
///
/// 同一時間只跑一次：併發呼叫拿到同一個進行中的結果。完成後遞增
/// [newsDataVersionProvider]。
class NewsFetcher {
  NewsFetcher(this._ref);

  final Ref _ref;
  final _dedup = RequestDeduplicator<NewsFetchOutcome>();

  Future<NewsFetchOutcome> fetch() => _dedup('rss', _run);

  Future<NewsFetchOutcome> _run() async {
    final total = NewsFeedSource.defaultSources.length;
    NewsFetchOutcome outcome;
    try {
      final result = await _ref.read(newsRepositoryProvider).syncNews();
      outcome = NewsFetchOutcome(
        totalSources: total,
        failedSources: {for (final e in result.errors) e.sourceName}.length,
      );
    } catch (e) {
      AppLogger.warning('NewsFetcher', 'RSS 同步失敗', e);
      outcome = NewsFetchOutcome(totalSources: total, failedSources: total);
    }
    _ref.read(newsDataVersionProvider.notifier).bump();
    return outcome;
  }
}

final newsFetcherProvider = Provider<NewsFetcher>(NewsFetcher.new);
```

- [ ] **Step 5: 熱度監聽版本**

`lib/presentation/providers/news_heat_provider.dart` 的 `newsHeatProvider` 開頭，`ref.watch(dataUpdateEpochProvider);` 下一行加 `ref.watch(newsDataVersionProvider);`，並 import `news_fetch_provider.dart`。provider doc 的「重新整理抓完 RSS 後 invalidate 本 provider 即同步」改為「抓完新聞後經 `newsDataVersionProvider` 重算」。

- [ ] **Step 6: 跑測試確認通過**

Run: `flutter test test/presentation/providers/news_fetch_provider_test.dart test/presentation/providers/news_link_provider_test.dart test/presentation/providers/news_heat_provider_test.dart`
Expected: PASS。

- [ ] **Step 7: analyze 並記錄進度**

Run: `flutter analyze` → No issues found。記錄進度。

---

### Task 5: 新聞頁狀態（篩選型別、相關股票、自選名單、共用抓新聞）

**Files:**
- Modify: `lib/presentation/providers/news_provider.dart`
- Modify（跟著改）: `lib/presentation/screens/news/news_screen.dart`（只改編譯所需：`setSourceFilter`→`setFilter`、`newsStockMap`→`relatedStocksOf`、`selectedSource`→`filter`、`_refresh` 回傳型別；畫面行為在 Task 7）、`test/presentation/screens/empty_state_layout_test.dart`（假 notifier 的 `refresh` 簽章）、`test/presentation/screens/news/news_screen_test.dart`（假 notifier 與 `newsStockMap` 改名）
- Test: `test/presentation/providers/news_provider_test.dart`

**Interfaces:**
- Consumes: `NewsStockLinks.merge`、`NewsDedup`（Task 2）、`getWatchlistAndHoldingSymbols`（Task 3）、`newsLinkMatcherProvider`、`newsFetcherProvider`、`NewsFetchOutcome`（Task 4）
- Produces:
  - `sealed class NewsFilter`（`NewsFilter.all`、`NewsFilter.mine`）、`MineNewsFilter`、`SourceNewsFilter(NewsSource source)`
  - `NewsState`：`relatedStocksByNewsId`、`mySymbols`、`filter`、`mineCount`、`relatedStocksOf(String newsId)`、`filteredNews`、`sourceCounts`
  - `NewsNotifier`：`Future<NewsFetchOutcome?> refresh({int days = 7})`、`loadData`、`setFilter(NewsFilter)`、`reloadMySymbols()`、`onNewsDataChanged()`

- [ ] **Step 1: 改寫 `news_provider_test.dart` 的既有用法並加新測試（先失敗）**

既有測試的機械性改名：
- `state.newsStockMap` → `state.relatedStocksByNewsId`；`NewsState(newsStockMap: …)` → `NewsState(relatedStocksByNewsId: …)`
- `selectedSource: NewsSource.x` → `filter: const SourceNewsFilter(NewsSource.x)`；`state.selectedSource` → `state.filter`；預設值斷言改 `expect(state.filter, NewsFilter.all)`
- `notifier.setSourceFilter(NewsSource.yahoo)` → `notifier.setFilter(const SourceNewsFilter(NewsSource.yahoo))`，斷言改 `expect(state.filter, const SourceNewsFilter(NewsSource.yahoo))`
- `setUp` 的 `container` overrides 加：
  ```dart
  newsLinkMatcherProvider.overrideWith(
    (ref) async => StockNameMatcher.forNewsLinks(
      [stock('9901', '甲乙'), stock('9902', '丙丁')],
      excludedNames: const {},
      nonCompanyPhrases: const {},
      extraAliases: const {},
    ),
  ),
  ```
  並在 `setUp` 加 `when(() => mockDb.getWatchlistAndHoldingSymbols()).thenAnswer((_) async => {});`
- 檔頭加 `stock()` helper（同 Task 2 測試）與 imports：`news_link_provider.dart`、`stock_name_matcher.dart`、`package:daredevil/domain/models/news_feed.dart`（不要加 `news_fetch_provider.dart`：測試沒用到它的名稱，會被 `unused_import` 擋）。

新增測試（`group('NewsState')` 內）：

```dart
    test('自選篩選：相關股票有自選或持股的新聞，去重後計數', () {
      final news = [
        createNewsEntry(id: 'a', title: '甲乙營收', source: '鉅亨網'),
        createNewsEntry(id: 'b', title: '甲乙營收', source: 'Yahoo財經'),
        createNewsEntry(id: 'c', title: '丙丁公告'),
        createNewsEntry(id: 'd', title: '大盤收高'),
      ];
      final state = NewsState(
        allNews: news,
        relatedStocksByNewsId: const {
          'a': ['9901'],
          'b': ['9901'],
          'c': ['9902'],
        },
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );

      expect(state.filteredNews.map((n) => n.id), hasLength(1));
      expect(state.mineCount, 1);
    });

    test('自選篩選可再疊加搜尋', () {
      final state = NewsState(
        allNews: [
          createNewsEntry(id: 'a', title: '甲乙營收'),
          createNewsEntry(id: 'b', title: '甲乙法說'),
        ],
        relatedStocksByNewsId: const {
          'a': ['9901'],
          'b': ['9901'],
        },
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
        searchQuery: '法說',
      );
      expect(state.filteredNews.map((n) => n.id), ['b']);
    });

    test('自選篩選下自選與持股的標籤排前，其他篩選維持原順序', () {
      const related = {
        'a': ['9902', '9903', '9901'],
      };
      final mine = NewsState(
        relatedStocksByNewsId: related,
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );
      final all = NewsState(
        relatedStocksByNewsId: related,
        mySymbols: const {'9901'},
      );
      expect(mine.relatedStocksOf('a'), ['9901', '9902', '9903']);
      expect(all.relatedStocksOf('a'), ['9902', '9903', '9901']);
      expect(all.relatedStocksOf('zzz'), isEmpty);
    });

    test('NewsFilter 相等性（篩選列每次 build 都新建實例，選中狀態靠 ==）', () {
      // 用非 const 實例：const 會被合併成同一物件，拿掉 == 覆寫也照樣相等
      final allSource = NewsSource.values.first;
      expect(SourceNewsFilter(allSource), NewsFilter.all);
      expect(
        SourceNewsFilter(NewsSource.values[2]),
        SourceNewsFilter(NewsSource.values[2]),
      );
      expect(
        SourceNewsFilter(NewsSource.values[2]),
        isNot(SourceNewsFilter(NewsSource.values[3])),
      );
      expect(NewsFilter.mine, isNot(NewsFilter.all));
    });
```

新增測試（`group('NewsNotifier')` 內）：

```dart
    test('loadData 合併代號對應與簡稱比對、讀自選名單', () async {
      when(() => mockNewsRepo.getRecentNews(days: any(named: 'days'))).thenAnswer(
        (_) async => [
          createNewsEntry(id: 'n1', title: '甲乙營收創新高'),
          createNewsEntry(id: 'n2', title: '某公司公告'),
        ],
      );
      when(() => mockDb.getNewsStockMappingsBatch(any())).thenAnswer(
        (_) async => {
          'n2': ['9930'],
        },
      );
      when(
        () => mockDb.getWatchlistAndHoldingSymbols(),
      ).thenAnswer((_) async => {'9901'});

      await container.read(newsProvider.notifier).loadData();

      final s = container.read(newsProvider);
      expect(s.relatedStocksByNewsId, {
        'n1': ['9901'],
        'n2': ['9930'],
      });
      expect(s.mySymbols, {'9901'});
    });

    test('reloadMySymbols 只重讀名單、不重抓新聞', () async {
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);
      final notifier = container.read(newsProvider.notifier);
      await notifier.loadData();
      when(
        () => mockDb.getWatchlistAndHoldingSymbols(),
      ).thenAnswer((_) async => {'9902'});
      clearInteractions(mockNewsRepo);

      await notifier.reloadMySymbols();

      expect(container.read(newsProvider).mySymbols, {'9902'});
      verifyNever(() => mockNewsRepo.getRecentNews(days: any(named: 'days')));
    });

    test('較早開始但較晚完成的載入不覆蓋較新的結果', () async {
      final first = Completer<List<NewsItemEntry>>();
      final second = Completer<List<NewsItemEntry>>();
      final answers = [first, second];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) => answers.removeAt(0).future);
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});
      final notifier = container.read(newsProvider.notifier);

      final f1 = notifier.loadData();
      final f2 = notifier.loadData();
      second.complete([createNewsEntry(id: 'new', title: '新')]);
      await f2;
      first.complete([createNewsEntry(id: 'old', title: '舊')]);
      await f1;

      expect(container.read(newsProvider).allNews.map((n) => n.id), ['new']);
    });

    test('較舊的載入回空清單也不覆蓋較新的結果', () async {
      final first = Completer<List<NewsItemEntry>>();
      final answers = [
        first,
        Completer<List<NewsItemEntry>>()
          ..complete([createNewsEntry(id: 'new', title: '新')]),
      ];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) => answers.removeAt(0).future);
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) async => {});
      final notifier = container.read(newsProvider.notifier);

      final f1 = notifier.loadData();
      await notifier.loadData();
      first.complete([]);
      await f1;

      expect(container.read(newsProvider).allNews.map((n) => n.id), ['new']);
    });

    test('較舊的載入已過第一道檢查、卡在對應查詢時被超越，也不覆蓋', () async {
      // 第一次載入的 getNewsStockMappingsBatch 卡住，期間第二次載入完成；
      // 釋放後第一次要被第二道世代檢查擋下
      final gate = Completer<Map<String, List<String>>>();
      final mapAnswers = [gate, Completer<Map<String, List<String>>>()..complete({})];
      final newsAnswers = [
        [createNewsEntry(id: 'old', title: '舊')],
        [createNewsEntry(id: 'new', title: '新')],
      ];
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => newsAnswers.removeAt(0));
      when(
        () => mockDb.getNewsStockMappingsBatch(any()),
      ).thenAnswer((_) => mapAnswers.removeAt(0).future);
      final notifier = container.read(newsProvider.notifier);

      final f1 = notifier.loadData();
      await pumpEventQueue(); // 讓第一次走到對應查詢
      verify(() => mockDb.getNewsStockMappingsBatch(any())).called(1);
      await notifier.loadData();
      gate.complete({});
      await f1;

      expect(container.read(newsProvider).allNews.map((n) => n.id), ['new']);
    });

    test('onNewsDataChanged：自己的 refresh 進行中不重複載入，其他時候載入', () async {
      final gate = Completer<NewsSyncResult>();
      when(() => mockNewsRepo.syncNews()).thenAnswer((_) => gate.future);
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);
      final notifier = container.read(newsProvider.notifier);

      final refreshing = notifier.refresh();
      notifier.onNewsDataChanged(); // refresh 進行中：略過
      gate.complete(const NewsSyncResult(itemsAdded: 0, errors: []));
      await refreshing;
      verify(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).called(1); // 只有 refresh 自己的那次

      notifier.onNewsDataChanged();
      await pumpEventQueue();
      verify(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).called(1);
    });

    test('refresh 回傳抓取結果（部分失敗）', () async {
      when(() => mockNewsRepo.syncNews()).thenAnswer(
        (_) async => NewsSyncResult(
          itemsAdded: 1,
          errors: [
            NewsFeedError(
              sourceName: '中央社',
              url: 'https://example.com',
              error: 'timeout',
              timestamp: DateTime(2026, 10, 6),
            ),
          ],
        ),
      );
      when(
        () => mockNewsRepo.getRecentNews(days: any(named: 'days')),
      ).thenAnswer((_) async => []);

      final o = await container.read(newsProvider.notifier).refresh();

      expect(o?.failedSources, 1);
      expect(o?.partiallyFailed, isTrue);
    });
```

（加 `import 'dart:async';`）

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/providers/news_provider_test.dart`
Expected: 編譯失敗（`NewsFilter`、`relatedStocksByNewsId` 等未定義）。

- [ ] **Step 3: 改寫 `news_provider.dart`**

保留 `NewsSource` enum 不動。其餘改成：

```dart
// ==================================================
// 新聞頁篩選
// ==================================================

/// 新聞頁的篩選（單選）：全部、自選，或單一來源
sealed class NewsFilter {
  const NewsFilter();

  static const all = SourceNewsFilter(NewsSource.all);
  static const mine = MineNewsFilter();
}

/// 相關股票有任一檔是自選或持股的新聞
final class MineNewsFilter extends NewsFilter {
  const MineNewsFilter();

  @override
  bool operator ==(Object other) => other is MineNewsFilter;

  @override
  int get hashCode => (MineNewsFilter).hashCode;
}

/// 單一來源（`NewsSource.all` 即全部）
final class SourceNewsFilter extends NewsFilter {
  const SourceNewsFilter(this.source);

  final NewsSource source;

  @override
  bool operator ==(Object other) =>
      other is SourceNewsFilter && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

// ==================================================
// 新聞狀態
// ==================================================

/// 新聞頁面狀態
class NewsState {
  NewsState({
    this.allNews = const [],
    this.relatedStocksByNewsId = const {},
    this.mySymbols = const {},
    this.isLoading = false,
    this.error,
    this.filter = NewsFilter.all,
    this.searchQuery = '',
  });

  final List<NewsItemEntry> allNews;

  /// newsId → 相關股票（代號對應 ∪ 簡稱比對，見 `NewsStockLinks`）。
  /// 只供顯示，不是 news_stock_map 的內容，不得寫回資料庫
  final Map<String, List<String>> relatedStocksByNewsId;

  /// 自選∪持股
  final Set<String> mySymbols;

  final bool isLoading;
  final String? error;
  final NewsFilter filter;
  final String searchQuery;

  /// 依篩選與搜尋關鍵字過濾的新聞（同日同標題去重後）
  List<NewsItemEntry> get filteredNews {
    var result = switch (filter) {
      MineNewsFilter() => _dedupedMine,
      SourceNewsFilter(:final source) =>
        _dedupedBySource[source] ?? const <NewsItemEntry>[],
    };
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result
          .where((n) => n.title.toLowerCase().contains(query))
          .toList();
    }
    return result;
  }

  /// 各來源檢視（全部／單一來源）去重後的清單，建構時算一次；規則見
  /// `NewsDedup`。去重在來源過濾**之後**做：全部檢視隱藏轉載、單一來源
  /// 檢視仍看得到該來源自己的那份。
  late final Map<NewsSource, List<NewsItemEntry>> _dedupedBySource = {
    for (final source in NewsSource.values)
      source: NewsDedup.sameDayTitle(
        source == NewsSource.all
            ? allNews
            : allNews.where((n) => source.matches(n.source)).toList(),
      ),
  };

  late final List<NewsItemEntry> _dedupedMine = NewsDedup.sameDayTitle([
    for (final n in allNews)
      if (relatedStocksByNewsId[n.id]?.any(mySymbols.contains) ?? false) n,
  ]);

  /// 各來源的新聞數量（與各檢視實際顯示的清單一致）
  late final Map<NewsSource, int> sourceCounts = {
    for (final e in _dedupedBySource.entries) e.key: e.value.length,
  };

  /// 「自選」的新聞數量（去重後）
  late final int mineCount = _dedupedMine.length;

  /// 這則新聞要顯示的股票標籤：「自選」篩選下自選與持股排前（各組維持原順序）
  List<String> relatedStocksOf(String newsId) {
    final related = relatedStocksByNewsId[newsId] ?? const <String>[];
    if (filter is! MineNewsFilter) return related;
    return [
      ...related.where(mySymbols.contains),
      ...related.where((s) => !mySymbols.contains(s)),
    ];
  }

  NewsState copyWith({
    List<NewsItemEntry>? allNews,
    Map<String, List<String>>? relatedStocksByNewsId,
    Set<String>? mySymbols,
    bool? isLoading,
    Object? error = sentinel,
    NewsFilter? filter,
    String? searchQuery,
  }) {
    return NewsState(
      allNews: allNews ?? this.allNews,
      relatedStocksByNewsId:
          relatedStocksByNewsId ?? this.relatedStocksByNewsId,
      mySymbols: mySymbols ?? this.mySymbols,
      isLoading: isLoading ?? this.isLoading,
      error: error == sentinel ? this.error : error as String?,
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

// ==================================================
// 新聞 Notifier
// ==================================================

class NewsNotifier extends Notifier<NewsState> {
  @override
  NewsState build() => NewsState();

  /// refresh 進行中旗標（防連點；抓取本身另由 `NewsFetcher` 去重）
  bool _isRefreshing = false;

  /// 載入世代：較早開始的載入較晚完成時，不覆蓋較新的結果
  int _loadGeneration = 0;

  /// 重新整理：先抓新聞（共用 `NewsFetcher`），再重讀本地資料
  ///
  /// 抓取失敗不阻擋本地重讀——離線時顯示既有新聞勝於整頁錯誤。回傳抓取
  /// 結果供畫面提示；已有 refresh 進行中時回 null。
  Future<NewsFetchOutcome?> refresh({int days = 7}) async {
    if (_isRefreshing) return null;
    _isRefreshing = true;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final outcome = await ref.read(newsFetcherProvider).fetch();
      await loadData(days: days);
      return outcome;
    } finally {
      _isRefreshing = false;
    }
  }

  /// 新聞資料版本遞增時由畫面呼叫：自己的 refresh 進行中會自行重讀，略過
  void onNewsDataChanged() {
    if (_isRefreshing) return;
    loadData();
  }

  /// 載入新聞資料
  Future<void> loadData({int days = 7}) async {
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final newsRepo = ref.read(newsRepositoryProvider);
      final db = ref.read(databaseProvider);

      final news = await newsRepo.getRecentNews(days: days);
      final mine = await db.getWatchlistAndHoldingSymbols();
      if (generation != _loadGeneration) return;

      if (news.isEmpty) {
        state = state.copyWith(
          allNews: [],
          relatedStocksByNewsId: {},
          mySymbols: mine,
          isLoading: false,
        );
        return;
      }

      final codeMap = await db.getNewsStockMappingsBatch([
        for (final n in news) n.id,
      ]);
      final matcher = await ref.read(newsLinkMatcherProvider.future);
      if (generation != _loadGeneration) return;

      state = state.copyWith(
        allNews: news,
        relatedStocksByNewsId: NewsStockLinks.merge(
          news: news,
          codeMap: codeMap,
          matcher: matcher,
        ),
        mySymbols: mine,
        isLoading: false,
      );
    } catch (e) {
      if (generation != _loadGeneration) return;
      AppLogger.warning('NewsNotifier', '載入新聞失敗', e);
      state = state.copyWith(error: ErrorDisplay.message(e), isLoading: false);
    }
  }

  /// 從新聞頁推出去的頁面返回後重讀自選∪持股（不重抓新聞、不重算相關股票）
  Future<void> reloadMySymbols() async {
    try {
      final mine = await ref
          .read(databaseProvider)
          .getWatchlistAndHoldingSymbols();
      state = state.copyWith(mySymbols: mine);
    } catch (e) {
      AppLogger.warning('NewsNotifier', '重讀自選與持股失敗', e);
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 設定篩選
  void setFilter(NewsFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// 設定搜尋關鍵字
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}
```

imports 增加：`news_dedup.dart`（Task 2 已加）、`news_stock_links.dart`、`news_link_provider.dart`、`news_fetch_provider.dart`。

- [ ] **Step 4: 跟著改的呼叫端（只求編譯與既有測試通過）**

`news_screen.dart`：
- `_refresh()` 改為：
  ```dart
  Future<void> _refresh() async {
    await ref.read(newsProvider.notifier).refresh();
    HapticFeedback.mediumImpact();
  }
  ```
  （刪除 `ref.invalidate(newsHeatProvider)` 與其註解：熱度已監聽新聞資料版本；刪 `news_heat_provider.dart` import 若已無用。）
- `_SourceFilterChips(selectedSource: state.selectedSource, …, onSelected: (s) => …setSourceFilter(s))` 暫改為 `selectedSource: switch (state.filter) { SourceNewsFilter(:final source) => source, MineNewsFilter() => NewsSource.all }`、`onSelected: (s) => ref.read(newsProvider.notifier).setFilter(SourceNewsFilter(s))`（Task 7 換成新的篩選列）。
- `_GroupedNewsList(newsStockMap: state.newsStockMap, …)` 改傳 `relatedStocksOf: state.relatedStocksOf`，`_GroupedNewsList` 欄位改 `final List<String> Function(String newsId) relatedStocksOf;`，`itemBuilder` 用 `relatedStocksOf(items[index].id)`。

`test/presentation/screens/news/news_screen_test.dart`：
- `FakeNewsNotifier` 的 `setSourceFilter` 覆寫改 `@override void setFilter(NewsFilter filter) {}`；加 `@override Future<NewsFetchOutcome?> refresh({int days = 7}) async => null;`（import `news_fetch_provider.dart`）。
- `NewsState(allNews: newsItems, newsStockMap: newsStockMap)` → `NewsState(allNews: newsItems, relatedStocksByNewsId: newsStockMap)`（兩處）。

`test/presentation/screens/empty_state_layout_test.dart` 的 `_FakeNewsNotifier.refresh`：

```dart
  @override
  Future<NewsFetchOutcome?> refresh({int days = 7}) async {
    refreshCalls++;
    return null;
  }
```

（import `news_fetch_provider.dart`）

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/presentation/providers/news_provider_test.dart test/presentation/screens/news/ test/presentation/screens/empty_state_layout_test.dart`
Expected: PASS。

- [ ] **Step 6: 量新聞頁比對耗時（決定是否改背景 isolate）**

在 `test/_scratch_news_test.dart` 追加：

```dart
  test('link timing', () async {
    final db = AppDatabase.forToolFile(_db);
    final stocks = await db.getAllActiveStocks();
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    final news = await (db.select(
      db.newsItem,
    )..where((t) => t.publishedAt.isBiggerOrEqualValue(cutoff))).get();
    final codeMap = await db.getNewsStockMappingsBatch([
      for (final n in news) n.id,
    ]);
    final sw1 = Stopwatch()..start();
    final matcher = StockNameMatcher.forNewsLinks(stocks);
    sw1.stop();
    final sw2 = Stopwatch()..start();
    final related = NewsStockLinks.merge(
      news: news,
      codeMap: codeMap,
      matcher: matcher,
    );
    sw2.stop();
    // ignore: avoid_print
    print(
      'news=${news.length} build=${sw1.elapsedMilliseconds}ms '
      'merge=${sw2.elapsedMilliseconds}ms linked=${related.length}',
    );
    await db.close();
  }, timeout: Timeout.none, skip: _db.isEmpty ? '需要 --dart-define=NEWS_DB' : false);
```

（import `news_stock_links.dart`）

Run: `flutter test test/_scratch_news_test.dart --plain-name 'link timing' --dart-define=NEWS_DB="$SP/replay.sqlite"`（連跑 3 次取最大值）
Expected: 印出 `news≈2000 build=…ms merge=…ms`。**判斷**：`build + merge ≤ 100ms` → 留在主 isolate，在進度紀錄寫下數字；> 100ms → 把 `loadData` 裡的 `NewsStockLinks.merge(...)` 改成 `await Isolate.run(() => NewsStockLinks.merge(news: news, codeMap: codeMap, matcher: matcher))`（`import 'dart:isolate';`），並在 `test/domain/services/news/news_stock_links_test.dart` 加真 spawn 的 sendability 測試：

```dart
  test('merge 的輸入可送進 isolate（Isolate.run 真 spawn）', () async {
    final items = [news('n1', '甲乙營收')];
    final codeMap = {
      'n1': ['9930'],
    };
    final r = await Isolate.run(
      () => NewsStockLinks.merge(news: items, codeMap: codeMap, matcher: matcher),
    );
    expect(r['n1'], ['9930', '9901']);
  });
```

- [ ] **Step 7: analyze 並記錄進度**

Run: `flutter analyze` → No issues found。記錄進度（含 Step 6 的耗時數字與判斷）。

---

### Task 6: 新聞列表共用元件與時區修正

**Files:**
- Create: `lib/presentation/widgets/news/news_grouping.dart`、`lib/presentation/widgets/news/news_widgets.dart`
- Modify: `lib/presentation/screens/news/news_screen.dart`（改用共用元件；刪除搬走的私有類別與方法）
- Test: `test/presentation/widgets/news/news_grouping_test.dart`（新增）、`test/presentation/widgets/news/news_widgets_test.dart`（新增）；`test/presentation/screens/news/news_screen_test.dart` 既有測試全部照樣通過

**Interfaces:**
- Produces:
  - `typedef NewsSection = ({String title, List<NewsItemEntry> items});`
  - `List<NewsSection> groupNewsTodayYesterdayEarlier(List<NewsItemEntry> news, DateTime now)`
  - `List<NewsSection> groupNewsByDay(List<NewsItemEntry> news, DateTime now)`
  - `String formatNewsFullTime(DateTime publishedAt)`（本地時間）
  - `class NewsListItem extends StatelessWidget { item, relatedStocks, onTap(NewsItemEntry, List<String>), onStockTap(String) }`
  - `List<Widget> newsSectionSlivers({required List<NewsSection> sections, required List<String> Function(String newsId) relatedStocksOf, required void Function(NewsItemEntry, List<String>) onTap, required ValueChanged<String> onStockTap})`
  - `void showNewsPreviewSheet(BuildContext context, {required NewsItemEntry item, required List<String> relatedStocks, required ValueChanged<String> onStockTap})`
  - `Future<void> openNewsUrl(BuildContext context, String url)`
  - `void showNewsFetchFeedback(BuildContext context, NewsFetchOutcome outcome)`（Task 7 加字串後才有內容；本 task 先建立並測試不顯示的情況）

- [ ] **Step 1: 寫失敗的分組測試**

`test/presentation/widgets/news/news_grouping_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/widgets/news/news_grouping.dart';

import '../../../helpers/time_zone_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

NewsItemEntry item(String id, DateTime at) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: id,
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: at,
  fetchedAt: at,
);

void main() {
  setUpAll(() async => setupTestLocalization());

  final now = DateTime(2026, 10, 6, 15);

  test('三段分組：今天／昨天／更早（空的段落不出現）', () {
    final r = groupNewsTodayYesterdayEarlier([
      item('t', DateTime(2026, 10, 6, 9)),
      item('e', DateTime(2026, 10, 1, 9)),
    ], now);
    expect(r.map((s) => s.items.single.id), ['t', 'e']);
    expect(r.first.title, 'news.today');
    expect(r.last.title, 'news.earlier');
  });

  test('逐日分組：今天、昨天標字，其他日期 M/d', () {
    final r = groupNewsByDay([
      item('a', DateTime(2026, 10, 6, 9)),
      item('b', DateTime(2026, 10, 5, 9)),
      item('c', DateTime(2026, 10, 3, 9)),
      item('d', DateTime(2026, 10, 3, 8)),
    ], now);
    expect(r.map((s) => s.title), ['news.today 10/6', 'news.yesterday 10/5', '10/3']);
    expect(r.last.items.map((n) => n.id), ['c', 'd']);
  });

  final cross = crossDayLocal(2026, 10, 6); // 本地 10/6、UTC 不同日的時刻

  test(
    '分組用本地日期（UTC 時間先轉本地）',
    () {
      final r = groupNewsByDay([item('x', cross!.toUtc())], now);
      expect(r.single.title, 'news.today 10/6');
      final r3 = groupNewsTodayYesterdayEarlier([item('x', cross.toUtc())], now);
      expect(r3.single.title, 'news.today');
    },
    skip: cross == null ? 'UTC 時區驗不到跨日' : false,
  );

  test(
    '預覽完整時間用本地時間',
    () {
      String two(int v) => v.toString().padLeft(2, '0');
      expect(
        formatNewsFullTime(cross!.toUtc()),
        '2026/10/6 ${two(cross.hour)}:${two(cross.minute)}',
      );
    },
    skip: cross == null ? 'UTC 時區驗不到時差' : false,
  );
}
```

`test/presentation/widgets/news/news_widgets_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/widgets/news/news_widgets.dart';

import '../../../helpers/time_zone_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

NewsItemEntry item(String id) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: '標題$id',
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: DateTime.now(),
  fetchedAt: DateTime.now(),
);

void main() {
  setUpAll(() async => setupTestLocalization());

  testWidgets('股票標籤最多 3 個，其餘收成 +N；點標籤回呼代碼', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      buildTestApp(
        NewsListItem(
          item: item('n1'),
          relatedStocks: const ['9901', '9902', '9903', '9904', '9905'],
          onTap: (_, _) {},
          onStockTap: tapped.add,
        ),
      ),
    );

    expect(find.text('9903'), findsOneWidget);
    expect(find.text('9904'), findsNothing);
    expect(find.text('+2'), findsOneWidget);
    await tester.tap(find.text('9902'));
    expect(tapped, ['9902']);
  });

  final now = DateTime.now();
  final old = now.subtract(const Duration(days: 10));
  final crossOld = crossDayLocal(old.year, old.month, old.day);

  testWidgets(
    '超過 7 天的列表日期用本地日期（個股頁 30 天清單會碰到）',
    (tester) async {
      final at = crossOld!.toUtc();
      await tester.pumpWidget(
        buildTestApp(
          NewsListItem(
            item: NewsItemEntry(
              id: 'o',
              source: '鉅亨網',
              title: '舊聞',
              url: 'https://example.com/o',
              category: 'OTHER',
              publishedAt: at,
              fetchedAt: at,
            ),
            relatedStocks: const [],
            onTap: (_, _) {},
            onStockTap: (_) {},
          ),
        ),
      );
      final expected = old.year == now.year
          ? '${old.month}/${old.day}'
          : '${old.year}/${old.month}/${old.day}';
      expect(find.text(expected), findsOneWidget);
    },
    skip: crossOld == null ? 'UTC 時區驗不到跨日' : false,
  );

  testWidgets('抓取全部成功時不跳提示', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNewsFetchFeedback(
              context,
              const NewsFetchOutcome(totalSources: 5, failedSources: 0),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
}
```

（`buildTestApp` 是 `widget_test_helpers.dart` 的 helper，會包 `MaterialApp`＋`Scaffold`，`ScaffoldMessenger` 可用。）

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/widgets/news/`
Expected: 編譯失敗（檔案不存在）。

- [ ] **Step 3: 建立 `lib/presentation/widgets/news/news_grouping.dart`**

```dart
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 一個帶標題的新聞段落
typedef NewsSection = ({String title, List<NewsItemEntry> items});

/// 新聞頁的三段分組：今天／昨天／更早（本地日期）；空的段落不出現
List<NewsSection> groupNewsTodayYesterdayEarlier(
  List<NewsItemEntry> news,
  DateTime now,
) {
  final today = DateContext.normalize(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final todayNews = <NewsItemEntry>[];
  final yesterdayNews = <NewsItemEntry>[];
  final earlierNews = <NewsItemEntry>[];
  for (final item in news) {
    final day = _localDay(item.publishedAt);
    if (day == today) {
      todayNews.add(item);
    } else if (day == yesterday) {
      yesterdayNews.add(item);
    } else {
      earlierNews.add(item);
    }
  }
  return [
    if (todayNews.isNotEmpty) (title: S.newsToday, items: todayNews),
    if (yesterdayNews.isNotEmpty) (title: S.newsYesterday, items: yesterdayNews),
    if (earlierNews.isNotEmpty) (title: S.newsEarlier, items: earlierNews),
  ];
}

/// 個股新聞的逐日分組（本地日期）：今天、昨天標字加日期，其他日期 M/d。
/// [news] 須已依時間新到舊排序
List<NewsSection> groupNewsByDay(List<NewsItemEntry> news, DateTime now) {
  final today = DateContext.normalize(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final sections = <NewsSection>[];
  DateTime? currentDay;
  for (final item in news) {
    final day = _localDay(item.publishedAt);
    if (day != currentDay) {
      currentDay = day;
      final md = '${day.month}/${day.day}';
      final title = day == today
          ? '${S.newsToday} $md'
          : day == yesterday
          ? '${S.newsYesterday} $md'
          : md;
      sections.add((title: title, items: <NewsItemEntry>[]));
    }
    sections.last.items.add(item);
  }
  return sections;
}

/// 預覽的完整時間（本地時間）
String formatNewsFullTime(DateTime publishedAt) {
  final dt = publishedAt.toLocal();
  return '${dt.year}/${dt.month}/${dt.day} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

DateTime _localDay(DateTime at) {
  final local = at.toLocal();
  return DateTime(local.year, local.month, local.day);
}
```

（`DateContext.normalize` 回傳本地日期零點，與 `_localDay` 可直接比較；若 `normalize` 對 UTC 輸入有不同語意，`now` 一律傳本地時間。）

- [ ] **Step 4: 建立 `lib/presentation/widgets/news/news_widgets.dart`**

把 `news_screen.dart` 的 `_SectionHeader`、`_NewsListItem`、`_StockChip`、`_showNewsPreview`、`_openUrl`、`_showOpenLinkError` 搬過來改成公開 API，內容照搬，只改以下幾點：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';
import 'package:daredevil/presentation/widgets/common/drag_handle.dart';
import 'package:daredevil/presentation/widgets/news/news_grouping.dart';

/// 新聞段落的 slivers（段落標題＋lazy 清單）
List<Widget> newsSectionSlivers({
  required List<NewsSection> sections,
  required List<String> Function(String newsId) relatedStocksOf,
  required void Function(NewsItemEntry, List<String>) onTap,
  required ValueChanged<String> onStockTap,
}) => [
  for (final s in sections) ...[
    SliverToBoxAdapter(
      child: NewsSectionHeader(title: s.title, count: s.items.length),
    ),
    SliverList.builder(
      itemCount: s.items.length,
      itemBuilder: (context, index) => NewsListItem(
        item: s.items[index],
        relatedStocks: relatedStocksOf(s.items[index].id),
        onTap: onTap,
        onStockTap: onStockTap,
      ),
    ),
  ],
];
```

- `NewsSectionHeader`（原 `_SectionHeader`，內容不變）。
- `NewsListItem`（原 `_NewsListItem`）：新增 `final ValueChanged<String> onStockTap;`，股票標籤的 `onTap: () => context.push(AppRoutes.stockDetail(symbol))` 改為 `onTap: () => onStockTap(symbol)`（不再 import go_router／app_routes）。`_formatTime` 改用本地時間（超過 7 天時顯示月／日，個股頁 30 天清單會碰到）：
  ```dart
  String _formatTime(DateTime publishedAt) {
    final now = DateTime.now();
    final dt = publishedAt.toLocal();
    final diff = now.difference(dt);

    if (diff.inMinutes < 60) {
      return S.newsMinutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return S.newsHoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return S.newsDaysAgo(diff.inDays);
    } else if (dt.year == now.year) {
      return '${dt.month}/${dt.day}';
    } else {
      return '${dt.year}/${dt.month}/${dt.day}';
    }
  }
  ```
- `NewsStockChip`（原 `_StockChip`，內容不變）。
- `showNewsPreviewSheet(BuildContext context, {required NewsItemEntry item, required List<String> relatedStocks, required ValueChanged<String> onStockTap})`：原 `_showNewsPreview` 內容；時間改 `formatNewsFullTime(item.publishedAt)`；`ActionChip.onPressed` 改 `Navigator.pop(context); onStockTap(symbol);`；開原文按鈕改 `Navigator.pop(context); openNewsUrl(context, item.url);`（`context` 用呼叫端傳入的外層 context，不是 sheet builder 的）。
- `openNewsUrl(BuildContext context, String url)`：原 `_openUrl`＋`_showOpenLinkError`，每個 `await` 之後用 `if (!context.mounted) return;` 取代 `mounted`。
- 抓取回饋：

```dart
/// 抓新聞後的提示：全部失敗（錯誤樣式）、部分失敗（一般樣式）；全部成功不提示
void showNewsFetchFeedback(BuildContext context, NewsFetchOutcome outcome) {
  final String message;
  final bool isError;
  if (outcome.allFailed) {
    message = S.newsFetchAllFailed;
    isError = true;
  } else if (outcome.partiallyFailed) {
    message = S.newsFetchPartialFailed(outcome.failedSources);
    isError = false;
  } else {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
```

`S.newsFetchAllFailed`／`S.newsFetchPartialFailed` 在本 step 一併加（Task 7 的字串表先加這兩條）：

`lib/core/l10n/app_strings.dart` 的 news 區塊：
```dart
  static String get newsFetchAllFailed => 'news.fetchAllFailed'.tr();
  static String newsFetchPartialFailed(int count) =>
      'news.fetchPartialFailed'.tr(namedArgs: {'count': count.toString()});
```
`zh-TW.json` 的 `news`：`"fetchAllFailed": "新聞來源都抓取失敗，顯示的是先前的新聞"`、`"fetchPartialFailed": "有 {count} 個新聞來源抓取失敗"`
`en.json` 的 `news`：`"fetchAllFailed": "Couldn't reach any news source; showing earlier news"`、`"fetchPartialFailed": "{count} news sources couldn't be reached"`

- [ ] **Step 5: `news_screen.dart` 改用共用元件**

- 刪除 `_AllNewsTabState._openUrl`、`_showOpenLinkError`、`_showNewsPreview`、`_formatFullTime`，以及 `_GroupedNewsList`、`_SectionHeader`、`_NewsListItem`、`_StockChip` 類別。
- `_AllNewsTabState` 加：
  ```dart
  Future<void> _openStock(String symbol) async {
    await context.push(AppRoutes.stockDetail(symbol));
  }

  void _showPreview(NewsItemEntry item, List<String> related) =>
      showNewsPreviewSheet(
        context,
        item: item,
        relatedStocks: related,
        onStockTap: _openStock,
      );
  ```
- 清單分支 `: _GroupedNewsList(...)` 改為：
  ```dart
  : CustomScrollView(
      slivers: newsSectionSlivers(
        sections: groupNewsTodayYesterdayEarlier(
          state.filteredNews,
          ref.read(appClockProvider).now(),
        ),
        relatedStocksOf: state.relatedStocksOf,
        onTap: _showPreview,
        onStockTap: _openStock,
      ),
    ),
  ```
- 移除不再使用的 imports（`url_launcher`、`date_context`、`drag_handle`、`app_bottom_sheet` 等，以 analyze 為準）；加 `news_widgets.dart`、`news_grouping.dart`、`providers.dart`（`appClockProvider`）。

- [ ] **Step 6: 跑測試確認通過**

Run: `flutter test test/presentation/widgets/news/ test/presentation/screens/news/ test/presentation/screens/empty_state_layout_test.dart`
Expected: PASS（`news_screen_test` 既有 17 條不改照樣過）。

- [ ] **Step 7: analyze 並記錄進度**

Run: `flutter analyze` → No issues found。記錄進度。

---

### Task 7: 新聞頁「自選」篩選、抓取回饋、版本監聽、返回重讀

**Files:**
- Modify: `lib/presentation/screens/news/news_screen.dart`、`lib/presentation/screens/news/heat_analysis_tab.dart:409-412`、`lib/core/l10n/app_strings.dart`、`assets/translations/zh-TW.json`、`assets/translations/en.json`
- Test: `test/presentation/screens/news/news_screen_test.dart`（追加）

**Interfaces:**
- Consumes: `NewsFilter`、`NewsState.mineCount`、`relatedStocksOf`、`NewsNotifier.setFilter／reloadMySymbols／onNewsDataChanged／refresh`（Task 5）、`newsDataVersionProvider`（Task 4）、共用元件（Task 6）
- Produces: `S.newsFilterMine`、`S.newsMineEmptyNoStocks`、`S.newsMineEmptyNoNews`

- [ ] **Step 1: 加字串**

`app_strings.dart`（news 區塊）：
```dart
  static String get newsFilterMine => 'news.filterMine'.tr();
  static String get newsMineEmptyNoStocks => 'news.mineEmptyNoStocks'.tr();
  static String get newsMineEmptyNoNews => 'news.mineEmptyNoNews'.tr();
```
`zh-TW.json` 的 `news`：`"filterMine": "自選"`、`"mineEmptyNoStocks": "還沒有自選股或持股"`、`"mineEmptyNoNews": "近 7 天沒有自選股或持股的相關新聞"`
`en.json` 的 `news`：`"filterMine": "My stocks"`、`"mineEmptyNoStocks": "No watchlist stocks or holdings yet"`、`"mineEmptyNoNews": "No news about your watchlist or holdings in the last 7 days"`

- [ ] **Step 2: 寫失敗的畫面測試**

`news_screen_test.dart` 的 `FakeNewsNotifier` 改成可記錄呼叫並可改狀態：

```dart
class FakeNewsNotifier extends NewsNotifier {
  NewsState initialState = NewsState();
  final calls = <String>[];
  NewsFetchOutcome? outcome;
  Set<String>? mySymbolsAfterReload;

  @override
  NewsState build() => initialState;

  @override
  Future<void> loadData({int days = 7}) async => calls.add('load');

  @override
  void setFilter(NewsFilter filter) {
    calls.add('filter');
    state = state.copyWith(filter: filter);
  }

  @override
  Future<NewsFetchOutcome?> refresh({int days = 7}) async {
    calls.add('refresh');
    return outcome;
  }

  @override
  void onNewsDataChanged() => calls.add('changed');

  @override
  Future<void> reloadMySymbols() async {
    calls.add('reloadMine');
    if (mySymbolsAfterReload case final s?) {
      state = state.copyWith(mySymbols: s);
    }
  }
}
```

`buildTestWidget` 改成接收並回傳 notifier 讓測試可檢查（新增參數 `FakeNewsNotifier? notifier`，未給時新建）。新增測試：

```dart
    testWidgets('篩選列有「自選」與則數，排在全部之後', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        relatedStocksByNewsId: const {
          'a': ['9901'],
        },
        mySymbols: const {'9901'},
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      final labels = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .map((c) => ((c.label as Text).data ?? ''))
          .toList();
      expect(labels[0], startsWith('empty.sourceAll'));
      expect(labels[1], 'news.filterMine (1)');
    });

    testWidgets('自選 0 則也顯示「自選」', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('news.filterMine (0)'), findsOneWidget);
    });

    testWidgets('點「自選」只列自選相關新聞', (tester) async {
      widenViewport(tester);
      final now = DateTime.now();
      final state = NewsState(
        allNews: [
          createNewsItem(id: 'a', title: '自選那則', publishedAt: now),
          createNewsItem(id: 'b', title: '別檔那則', publishedAt: now),
        ],
        relatedStocksByNewsId: const {
          'a': ['9901'],
          'b': ['9902'],
        },
        mySymbols: const {'9901'},
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('news.filterMine (1)'));
      await tester.pump();

      expect(find.text('自選那則'), findsOneWidget);
      expect(find.text('別檔那則'), findsNothing);
    });

    testWidgets('自選篩選、沒有自選也沒有持股：顯示還沒有自選股或持股', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        filter: NewsFilter.mine,
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('news.mineEmptyNoStocks'), findsOneWidget);
    });

    testWidgets('自選篩選、有自選但沒新聞：顯示近 7 天沒有相關新聞', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('news.mineEmptyNoNews'), findsOneWidget);
    });

    testWidgets('自選篩選下，自選股的標籤排在 +N 之前看得到', (tester) async {
      widenViewport(tester);
      final state = NewsState(
        allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
        relatedStocksByNewsId: const {
          'a': ['9902', '9903', '9904', '9901'],
        },
        mySymbols: const {'9901'},
        filter: NewsFilter.mine,
      );
      await tester.pumpWidget(buildTestWidget(newsState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('9901'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('從個股頁返回後重讀自選；移除最後一檔後自選篩選顯示空', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier()
        ..initialState = NewsState(
          allNews: [createNewsItem(id: 'a', publishedAt: DateTime.now())],
          relatedStocksByNewsId: const {
            'a': ['9901'],
          },
          mySymbols: const {'9901'},
          filter: NewsFilter.mine,
        )
        ..mySymbolsAfterReload = const {};
      final router = GoRouter(
        initialLocation: '/news',
        routes: [
          GoRoute(path: '/news', builder: (_, _) => const NewsScreen()),
          GoRoute(
            path: '/stock/:symbol',
            builder: (_, _) => const Scaffold(body: Text('detail')),
          ),
        ],
      );
      await tester.pumpWidget(
        buildProviderTestApp(
          const SizedBox(),
          router: router,
          overrides: [newsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('9901'));
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      expect(notifier.calls, contains('reloadMine'));
      expect(find.text('news.mineEmptyNoStocks'), findsOneWidget);
    });

    testWidgets('從熱度分頁點進個股頁、返回後也重讀自選', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier();
      final router = GoRouter(
        initialLocation: '/news',
        routes: [
          GoRoute(path: '/news', builder: (_, _) => const NewsScreen()),
          GoRoute(
            path: '/stock/:symbol',
            builder: (_, _) => const Scaffold(body: Text('detail')),
          ),
        ],
      );
      await tester.pumpWidget(
        buildProviderTestApp(
          const SizedBox(),
          router: router,
          overrides: [
            newsProvider.overrideWith(() => notifier),
            newsHeatProvider.overrideWith(
              (ref) async => const NewsHeatAnalysis(
                themes: [],
                stocks: [
                  StockHeat(
                    symbol: '9901',
                    mentions7d: 5,
                    mentionsPrev21d: 1,
                    isSurging: false,
                    distinctSources7d: 2,
                    hasRiskNews: false,
                    isNewEntrant: false,
                    surgeRatio: 1.0,
                  ),
                ],
                stockNames: {'9901': '甲乙'},
                modeBySymbol: {},
              ),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('news.heatTab'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('甲乙')); // 焦點股列的股名
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      expect(notifier.calls, contains('reloadMine'));
    });

    testWidgets('新聞資料版本遞增時通知 notifier', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier();
      await tester.pumpWidget(
        buildProviderTestApp(
          const NewsScreen(),
          overrides: [newsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      ProviderScope.containerOf(
        tester.element(find.byType(NewsScreen)),
      ).read(newsDataVersionProvider.notifier).bump();
      await tester.pump();

      expect(notifier.calls, contains('changed'));
    });

    testWidgets('重新整理全部來源失敗時跳錯誤提示', (tester) async {
      widenViewport(tester);
      final notifier = FakeNewsNotifier()
        ..outcome = const NewsFetchOutcome(totalSources: 5, failedSources: 5);
      await tester.pumpWidget(
        buildProviderTestApp(
          const NewsScreen(),
          overrides: [newsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(find.text('news.fetchAllFailed'), findsOneWidget);
    });
```

（`AppRoutes.stockDetail(symbol)` 是 `/stock/$symbol`；`buildProviderTestApp` 給了 `router:` 時用 `MaterialApp.router`，`child` 不使用，所以傳 `SizedBox()`。）

imports 加：`package:flutter_riverpod/flutter_riverpod.dart`、`package:go_router/go_router.dart`、`news_fetch_provider.dart`、`package:daredevil/domain/services/news/heat_calculator.dart`（`StockHeat`）。

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/presentation/screens/news/news_screen_test.dart`
Expected: 新測試 FAIL（沒有「自選」標籤、沒有重讀、沒有提示）。例外：「自選篩選下，自選股的標籤排在 +N 之前看得到」在 Task 5 加了 `relatedStocksOf`、Task 6 接上畫面後就會過，這條在這一步 PASS 是正常的。

- [ ] **Step 4: 改 `news_screen.dart`**

`_NewsScreenState.build` 開頭加版本監聽：

```dart
    ref.listen(
      newsDataVersionProvider,
      (_, _) => ref.read(newsProvider.notifier).onNewsDataChanged(),
    );
```

`_refresh()`：

```dart
  Future<void> _refresh() async {
    final outcome = await ref.read(newsProvider.notifier).refresh();
    if (!mounted) return;
    if (outcome != null) showNewsFetchFeedback(context, outcome);
    HapticFeedback.mediumImpact();
  }
```

`_AllNewsTabState._openStock` 改為返回後重讀：

```dart
  Future<void> _openStock(String symbol) async {
    await context.push(AppRoutes.stockDetail(symbol));
    if (!mounted) return;
    await ref.read(newsProvider.notifier).reloadMySymbols();
  }
```

`_SourceFilterChips` 換成 `_NewsFilterChips`：

```dart
class _NewsFilterChips extends StatelessWidget {
  const _NewsFilterChips({
    required this.filter,
    required this.sourceCounts,
    required this.mineCount,
    required this.onSelected,
  });

  final NewsFilter filter;
  final Map<NewsSource, int> sourceCounts;
  final int mineCount;
  final ValueChanged<NewsFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // （保留原 _SourceFilterChips 的選中文字色註解與 selectedLabelColor 計算）
    final selectedLabelColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;

    Widget chip(NewsFilter value, String label) {
      final selected = value == filter;
      return FilterChip(
        selected: selected,
        label: Text(label),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: selected ? selectedLabelColor : theme.colorScheme.onSurface,
        ),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          onSelected(value);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing16,
        vertical: DesignTokens.spacing8,
      ),
      child: Wrap(
        spacing: DesignTokens.spacing8,
        runSpacing: DesignTokens.spacing8,
        children: [
          chip(
            NewsFilter.all,
            '${NewsSource.all.label} (${sourceCounts[NewsSource.all] ?? 0})',
          ),
          chip(NewsFilter.mine, '${S.newsFilterMine} ($mineCount)'),
          for (final source in NewsSource.values)
            if (source != NewsSource.all && (sourceCounts[source] ?? 0) > 0)
              chip(
                SourceNewsFilter(source),
                '${source.label} (${sourceCounts[source] ?? 0})',
              ),
        ],
      ),
    );
  }
}
```

`_AllNewsTabState.build` 的篩選列與空狀態：

```dart
        if (state.allNews.isNotEmpty)
          _NewsFilterChips(
            filter: state.filter,
            sourceCounts: state.sourceCounts,
            mineCount: state.mineCount,
            onSelected: ref.read(newsProvider.notifier).setFilter,
          ),
```

```dart
                : state.filteredNews.isEmpty
                ? FillRemainingScrollable(child: _emptyState(state))
```

```dart
  Widget _emptyState(NewsState state) {
    if (state.filter is MineNewsFilter && state.searchQuery.isEmpty) {
      return state.mySymbols.isEmpty
          ? EmptyState(
              icon: Icons.star_outline,
              title: S.newsMineEmptyNoStocks,
            )
          : EmptyState(
              icon: Icons.article_outlined,
              title: S.newsMineEmptyNoNews,
            );
    }
    return EmptyStates.noNews();
  }
```

imports 加 `news_fetch_provider.dart`、`empty_state.dart`（已有）。

`heat_analysis_tab.dart` 的 `_openStockDetail`（呼叫端是沒有 `ref` 的 StatelessWidget，用 container 取 notifier；在 `await` 前取，避免跨 async 用 context）：

```dart
Future<void> _openStockDetail(BuildContext context, String symbol) async {
  // 照 news_screen.dart 既有慣例（AppRoutes.stockDetail + context.push）。
  // 返回後重讀自選∪持股：個股頁可能加入或移除了自選，新聞頁「自選」篩選要跟上
  final container = ProviderScope.containerOf(context, listen: false);
  await context.push(AppRoutes.stockDetail(symbol));
  await container.read(newsProvider.notifier).reloadMySymbols();
}
```

（import `news_provider.dart`；兩個呼叫端 `onPressed:`／`onTap: () => _openStockDetail(...)` 不用改。）

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/presentation/screens/news/ test/presentation/screens/empty_state_layout_test.dart`
Expected: PASS。

- [ ] **Step 6: analyze 並記錄進度**

Run: `flutter analyze` → No issues found。記錄進度。

---

### Task 8: 個股頁「新聞」分頁

**Files:**
- Create: `lib/presentation/providers/stock_news_provider.dart`、`lib/presentation/screens/stock_detail/tabs/news_tab.dart`
- Modify: `lib/presentation/screens/stock_detail/stock_detail_screen.dart`（:63 `length: 6`、:417-436 加分頁、:481-487 加 Tab）、`lib/presentation/providers/stock_detail_state.dart`（刪 `recentNews`）、`lib/core/l10n/app_strings.dart`、兩個翻譯檔
- Test: `test/presentation/providers/stock_news_provider_test.dart`（新增）、`test/presentation/screens/stock_detail/news_tab_test.dart`（新增）、`test/presentation/screens/stock_detail/stock_detail_screen_test.dart:239-246`（6 個分頁）、`test/presentation/providers/stock_detail_state_test.dart:108`（刪 `recentNews` 斷言）

**Interfaces:**
- Consumes: `newsLinkMatcherProvider`、`newsDataVersionProvider`、`newsFetcherProvider`（Task 4）、`getNewsCandidatesForStock`、`getNewsStockMappingsBatch`（Task 3）、`NewsStockLinks`、`NewsDedup`（Task 2）、`StockNameStatus`（Task 1）、共用元件（Task 6）
- Produces:
  - `class StockNews { List<NewsItemEntry> items; Map<String, List<String>> otherStocksByNewsId; StockNameStatus nameStatus }`
  - `final stockNewsProvider = FutureProvider.autoDispose.family<StockNews, String>`
  - `class StockNewsTab extends ConsumerStatefulWidget { String symbol }`

- [ ] **Step 1: 加字串**

`app_strings.dart`：
```dart
  static String get stockDetailTabNews => 'stockDetail.tabNews'.tr();
  static String get stockNewsNoteMatched => 'stockNews.noteMatched'.tr();
  static String get stockNewsNoteExcluded => 'stockNews.noteExcluded'.tr();
  static String get stockNewsNoteNotListed => 'stockNews.noteNotListed'.tr();
  static String get stockNewsEmpty => 'stockNews.empty'.tr();
  static String get stockNewsRefresh => 'stockNews.refresh'.tr();
```
`zh-TW.json`：`stockDetail.tabNews` = 「新聞」；新增頂層 `"stockNews"`：
```json
"stockNews": {
  "noteMatched": "依標題中的股票代號與公司名稱比對，可能包含同名詞；公告只收上市公司的自選與持股",
  "noteExcluded": "這檔簡稱是常見詞，只依代號比對；公告只收上市公司的自選與持股",
  "noteNotListed": "這檔不在目前的股票清單，只依代號比對；公告只收上市公司的自選與持股",
  "empty": "近 30 天沒有找到這檔的新聞",
  "refresh": "重新整理新聞"
}
```
`en.json`：`stockDetail.tabNews` = "News"；
```json
"stockNews": {
  "noteMatched": "Matched by stock code and company name in headlines; may include other uses of the same name. Announcements cover listed (TWSE) watchlist stocks and holdings only",
  "noteExcluded": "This stock's short name is a common word, so only headlines with its code are matched. Announcements cover listed (TWSE) watchlist stocks and holdings only",
  "noteNotListed": "This stock isn't in the current stock list, so only headlines with its code are matched. Announcements cover listed (TWSE) watchlist stocks and holdings only",
  "empty": "No news about this stock in the last 30 days",
  "refresh": "Refresh news"
}
```

- [ ] **Step 2: 寫失敗的 provider 測試**

`test/presentation/providers/stock_news_provider_test.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class FixedClock implements AppClock {
  const FixedClock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  isActive: true,
  updatedAt: DateTime(2026, 10, 6),
);

NewsItemEntry news(String id, String title, DateTime at) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: title,
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: at,
  fetchedAt: at,
);

void main() {
  late MockAppDatabase db;
  late ProviderContainer container;
  final now = DateTime(2026, 10, 6, 15);

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  setUp(() {
    db = MockAppDatabase();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appClockProvider.overrideWithValue(FixedClock(now)),
        newsLinkMatcherProvider.overrideWith(
          (ref) async => StockNameMatcher.forNewsLinks(
            [
              stock('9901', '甲乙'),
              stock('9902', '常見'),
              stock('9907', '測試電子'),
              stock('9908', '測試'),
            ],
            excludedNames: const {'常見'},
            nonCompanyPhrases: const {},
            extraAliases: const {},
          ),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  void stubCandidates(
    List<NewsItemEntry> items,
    Map<String, List<String>> codeMap,
  ) {
    when(
      () => db.getNewsCandidatesForStock(
        symbol: any(named: 'symbol'),
        names: any(named: 'names'),
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => items);
    when(
      () => db.getNewsStockMappingsBatch(any()),
    ).thenAnswer((_) async => codeMap);
  }

  test('代號對應一律收；名稱候選要比對確認（測試電子不算測試）', () async {
    final t = DateTime(2026, 10, 6, 9);
    stubCandidates(
      [
        news('code', '某公司公告', t),
        news('name', '測試營收', t),
        news('longer', '測試電子營收', t),
      ],
      {
        'code': ['9908'],
      },
    );

    final r = await container.read(stockNewsProvider('9908').future);

    expect(r.items.map((n) => n.id).toSet(), {'code', 'name'});
    expect(r.nameStatus, StockNameStatus.matched);
  });

  test('簡稱被排除的股票仍列出代號對應的新聞', () async {
    final t = DateTime(2026, 10, 6, 9);
    stubCandidates(
      [news('code', '常見(9902)目標價調升', t)],
      {
        'code': ['9902'],
      },
    );

    final r = await container.read(stockNewsProvider('9902').future);

    expect(r.items.map((n) => n.id), ['code']);
    expect(r.nameStatus, StockNameStatus.excluded);
    verify(
      () => db.getNewsCandidatesForStock(
        symbol: '9902',
        names: const [],
        since: any(named: 'since'),
      ),
    ).called(1);
  });

  test('股票標籤只列其他股票；截止點是 30 天前', () async {
    final t = DateTime(2026, 10, 6, 9);
    stubCandidates([news('n', '甲乙與測試電子齊漲', t)], const {});

    final r = await container.read(stockNewsProvider('9901').future);

    expect(r.otherStocksByNewsId['n'], ['9907']);
    verify(
      () => db.getNewsCandidatesForStock(
        symbol: '9901',
        names: ['甲乙'],
        since: now.subtract(const Duration(days: 30)),
      ),
    ).called(1);
  });

  test('不在清單的股票：只靠代號、狀態 notListed', () async {
    stubCandidates(const [], const {});
    final r = await container.read(stockNewsProvider('9999').future);
    expect(r.nameStatus, StockNameStatus.notListed);
  });

  test('同日同標題去重', () async {
    stubCandidates(
      [
        news('a', '甲乙營收', DateTime(2026, 10, 6, 10)),
        news('b', '甲乙營收', DateTime(2026, 10, 6, 9)),
      ],
      const {},
    );
    final r = await container.read(stockNewsProvider('9901').future);
    expect(r.items.map((n) => n.id), ['b']);
  });

  test('新聞資料版本遞增後重讀', () async {
    stubCandidates(const [], const {});
    final sub = container.listen(stockNewsProvider('9901'), (_, _) {});
    addTearDown(sub.close);
    await container.read(stockNewsProvider('9901').future);

    container.read(newsDataVersionProvider.notifier).bump();
    await container.read(stockNewsProvider('9901').future);

    verify(
      () => db.getNewsCandidatesForStock(
        symbol: '9901',
        names: any(named: 'names'),
        since: any(named: 'since'),
      ),
    ).called(2);
  });
}
```

（`AppClock` 的介面與 `appClockProvider` 位置照 `lib/core/utils/clock.dart`、`providers.dart`；若專案已有測試用假時鐘 helper，改用它。）

- [ ] **Step 3: 寫失敗的分頁測試**

`test/presentation/screens/stock_detail/news_tab_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/news_tab.dart';
import 'package:daredevil/presentation/widgets/news/news_widgets.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class MockNewsFetcher extends Mock implements NewsFetcher {}

NewsItemEntry news(String id, {DateTime? at}) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: '標題$id',
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: at ?? DateTime.now(),
  fetchedAt: at ?? DateTime.now(),
);

StockNews data(
  List<NewsItemEntry> items, {
  StockNameStatus status = StockNameStatus.matched,
}) => StockNews(
  items: items,
  otherStocksByNewsId: const {},
  nameStatus: status,
);

void main() {
  setUpAll(() async => setupTestLocalization());

  Widget app(
    String symbol, {
    required StockNews Function(String) load,
    NewsFetcher? fetcher,
  }) => buildProviderTestApp(
    Scaffold(body: StockNewsTab(key: ValueKey('news-$symbol'), symbol: symbol)),
    overrides: [
      stockNewsProvider.overrideWith((ref, s) async => load(s)),
      if (fetcher != null) newsFetcherProvider.overrideWithValue(fetcher),
    ],
  );

  testWidgets('列出新聞與一般說明', (tester) async {
    await tester.pumpWidget(app('9901', load: (_) => data([news('a')])));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('標題a'), findsOneWidget);
    expect(find.text('stockNews.noteMatched'), findsOneWidget);
  });

  testWidgets('簡稱被排除：常見詞版說明', (tester) async {
    await tester.pumpWidget(
      app(
        '9902',
        load: (_) => data([news('a')], status: StockNameStatus.excluded),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('stockNews.noteExcluded'), findsOneWidget);
  });

  testWidgets('不在清單：不在清單版說明', (tester) async {
    await tester.pumpWidget(
      app(
        '9999',
        load: (_) => data(const [], status: StockNameStatus.notListed),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('stockNews.noteNotListed'), findsOneWidget);
  });

  testWidgets('沒有新聞：空畫面，說明照常', (tester) async {
    await tester.pumpWidget(app('9901', load: (_) => data(const [])));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('stockNews.empty'), findsOneWidget);
    expect(find.text('stockNews.noteMatched'), findsOneWidget);
  });

  testWidgets('上百則只建構看得到的列（lazy）', (tester) async {
    final many = [
      for (var i = 0; i < 300; i++)
        news('$i', at: DateTime.now().subtract(Duration(minutes: i))),
    ];
    await tester.pumpWidget(app('9901', load: (_) => data(many)));
    await tester.pump(const Duration(seconds: 1));

    final built = tester.widgetList(find.byType(NewsListItem)).length;
    expect(built, greaterThan(0));
    expect(built, lessThan(100));
  });

  testWidgets('斷網按重新整理：提示全部失敗，重讀期間清單保留、不閃載入中', (tester) async {
    // 走真的 NewsFetcher：抓完遞增版本 → provider 重讀；第二次載入卡住，
    // 驗證 skipLoadingOnReload 讓清單留著
    final repo = MockNewsRepository();
    when(() => repo.syncNews()).thenAnswer(
      (_) async => NewsSyncResult(
        itemsAdded: 0,
        errors: [
          for (final s in NewsFeedSource.defaultSources)
            NewsFeedError(
              sourceName: s.name,
              url: s.url,
              error: 'offline',
              timestamp: DateTime(2026, 10, 6),
            ),
        ],
      ),
    );
    var builds = 0;
    final reload = Completer<StockNews>();
    await tester.pumpWidget(
      buildProviderTestApp(
        const Scaffold(body: StockNewsTab(symbol: '9901')),
        overrides: [
          newsRepositoryProvider.overrideWithValue(repo),
          stockNewsProvider.overrideWith((ref, s) {
            ref.watch(newsDataVersionProvider);
            return builds++ == 0
                ? Future.value(data([news('a')]))
                : reload.future;
          }),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('stockNews.refresh'));
    await tester.pump();
    await tester.pump();

    expect(builds, 2, reason: '前提：抓完遞增版本、清單正在重讀');
    expect(find.text('news.fetchAllFailed'), findsOneWidget);
    expect(find.text('標題a'), findsOneWidget);
    expect(find.byType(NewsListShimmer), findsNothing);

    reload.complete(data([news('a')]));
    await tester.pump();
    expect(find.text('標題a'), findsOneWidget);
  });

  testWidgets('重新整理進行中不重複觸發', (tester) async {
    final fetcher = MockNewsFetcher();
    final gate = Completer<NewsFetchOutcome>();
    when(() => fetcher.fetch()).thenAnswer((_) => gate.future);
    await tester.pumpWidget(
      app('9901', load: (_) => data([news('a')]), fetcher: fetcher),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('stockNews.refresh'));
    await tester.pump();
    await tester.tap(find.byTooltip('stockNews.refresh'), warnIfMissed: false);
    await tester.pump();
    gate.complete(const NewsFetchOutcome(totalSources: 5, failedSources: 0));
    await tester.pump();

    verify(() => fetcher.fetch()).called(1);
  });
}
```

imports 加：`dart:async`、`package:daredevil/data/repositories/news_repository.dart`、`package:daredevil/domain/models/news_feed.dart`、`package:daredevil/domain/repositories/news_repository.dart' show NewsSyncResult`、`package:daredevil/presentation/providers/providers.dart`、`package:daredevil/presentation/widgets/shimmer_loading.dart`；檔頭加 `class MockNewsRepository extends Mock implements NewsRepository {}`。

原地換股的測試放在 `stock_detail_screen_test.dart`（Step 7），要經過個股頁真正的換股路徑。

- [ ] **Step 4: 跑測試確認失敗**

Run: `flutter test test/presentation/providers/stock_news_provider_test.dart test/presentation/screens/stock_detail/news_tab_test.dart`
Expected: 編譯失敗（檔案不存在）。

- [ ] **Step 5: 建立 `lib/presentation/providers/stock_news_provider.dart`**

```dart
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/news_dedup.dart';
import 'package:daredevil/domain/services/news/news_stock_links.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/news_link_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 個股新聞分頁的內容
@immutable
class StockNews {
  const StockNews({
    required this.items,
    required this.otherStocksByNewsId,
    required this.nameStatus,
  });

  /// 這檔近 30 天的新聞（同日同標題去重、新到舊）
  final List<NewsItemEntry> items;

  /// newsId → 同一則新聞提到的其他股票（不含這檔）
  final Map<String, List<String>> otherStocksByNewsId;

  /// 這檔在比對器裡的名稱狀態（決定說明文案）
  final StockNameStatus nameStatus;
}

/// 個股新聞：代號對應到這檔的一律收；標題含這檔名稱的候選要完整比對、
/// 且結果包含這檔才收（「測試電子」不算進「測試」）
final stockNewsProvider = FutureProvider.autoDispose
    .family<StockNews, String>((ref, symbol) async {
      ref.watch(dataUpdateEpochProvider);
      ref.watch(newsDataVersionProvider);
      final matcher = await ref.watch(newsLinkMatcherProvider.future);
      final db = ref.read(databaseProvider);
      final since = ref
          .read(appClockProvider)
          .now()
          .subtract(const Duration(days: DataFreshness.newsRetentionDays));

      final candidates = await db.getNewsCandidatesForStock(
        symbol: symbol,
        names: matcher.namesOf(symbol),
        since: since,
      );
      final codeMap = await db.getNewsStockMappingsBatch([
        for (final n in candidates) n.id,
      ]);
      final related = NewsStockLinks.merge(
        news: candidates,
        codeMap: codeMap,
        matcher: matcher,
      );
      final items = NewsDedup.sameDayTitle([
        for (final n in candidates)
          if (related[n.id]?.contains(symbol) ?? false) n,
      ]);
      return StockNews(
        items: items,
        otherStocksByNewsId: {
          for (final n in items)
            n.id: [
              for (final s in related[n.id]!)
                if (s != symbol) s,
            ],
        },
        nameStatus: matcher.nameStatusOf(symbol),
      );
    });
```

- [ ] **Step 6: 建立 `lib/presentation/screens/stock_detail/tabs/news_tab.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/news/news_grouping.dart';
import 'package:daredevil/presentation/widgets/news/news_widgets.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

/// 個股頁「新聞」分頁：這檔近 30 天的新聞（lazy 清單）
class StockNewsTab extends ConsumerStatefulWidget {
  const StockNewsTab({super.key, required this.symbol});

  final String symbol;

  @override
  ConsumerState<StockNewsTab> createState() => _StockNewsTabState();
}

class _StockNewsTabState extends ConsumerState<StockNewsTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final outcome = await ref.read(newsFetcherProvider).fetch();
    if (!mounted) return;
    setState(() => _refreshing = false);
    showNewsFetchFeedback(context, outcome);
  }

  void _openStock(String symbol) => context.push(AppRoutes.stockDetail(symbol));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(stockNewsProvider(widget.symbol));
    final now = ref.read(appClockProvider).now();

    // primary: false 與其他 5 個分頁一致：捲清單不帶動外層報價區收合
    return CustomScrollView(
      primary: false,
      slivers: [
        SliverToBoxAdapter(
          child: _NoteRow(
            status: async.value?.nameStatus,
            refreshing: _refreshing,
            onRefresh: _refresh,
          ),
        ),
        ...async.when(
          skipLoadingOnReload: true,
          data: (data) => data.items.isEmpty
              ? [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.article_outlined,
                      title: S.stockNewsEmpty,
                    ),
                  ),
                ]
              : newsSectionSlivers(
                  sections: groupNewsByDay(data.items, now),
                  relatedStocksOf: (id) =>
                      data.otherStocksByNewsId[id] ?? const [],
                  onTap: (item, related) => showNewsPreviewSheet(
                    context,
                    item: item,
                    relatedStocks: related,
                    onStockTap: _openStock,
                  ),
                  onStockTap: _openStock,
                ),
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: NewsListShimmer(itemCount: 6),
            ),
          ],
          error: (e, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStates.error(
                message: ErrorDisplay.message(e),
                onRetry: () => ref.invalidate(stockNewsProvider(widget.symbol)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.status,
    required this.refreshing,
    required this.onRefresh,
  });

  final StockNameStatus? status;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = switch (status) {
      StockNameStatus.matched => S.stockNewsNoteMatched,
      StockNameStatus.excluded => S.stockNewsNoteExcluded,
      StockNameStatus.notListed => S.stockNewsNoteNotListed,
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacing16,
        DesignTokens.spacing8,
        DesignTokens.spacing8,
        DesignTokens.spacing8,
      ),
      child: Row(
        children: [
          Expanded(
            child: note == null
                ? const SizedBox.shrink()
                : Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          IconButton(
            tooltip: S.stockNewsRefresh,
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
```

（`async.value` 在 riverpod 3 沒有值時回 null；若編譯不過，改用 `async.hasValue ? async.requireValue.nameStatus : null`。`EmptyStates.error` 的參數名以 `empty_state.dart` 為準。）

- [ ] **Step 7: 接上個股頁、刪死欄位、改既有測試**

`stock_detail_screen.dart`：
- `TabController(length: 5, vsync: this)` → `length: 6`；
- `TabBarView.children` 在 `FundamentalsTab(...)` 與 `AlertsTab(...)` 之間插入 `StockNewsTab(key: ValueKey('news-$_symbol'), symbol: _symbol),`；
- `tabs` 在 `tabFundamentals` 與 `tabAlerts` 之間插入 `Tab(text: 'stockDetail.tabNews'.tr()),`（與鄰近的 inline `.tr()` 一致；`S.stockDetailTabNews` 仍註冊，供 key 檢查與 Task 9 的真實翻譯測試）；
- import `tabs/news_tab.dart`。

`stock_detail_state.dart`：刪除建構子參數 `this.recentNews = const []`、欄位 `final List<NewsItemEntry> recentNews;`、`copyWith` 的 `List<NewsItemEntry>? recentNews` 參數與 `recentNews: recentNews ?? this.recentNews`（`app_database.dart` import 仍被其他型別使用，保留）。

`stock_detail_state_test.dart`：刪 `expect(state.recentNews, isEmpty);`。
`stock_detail_screen_test.dart`：`'shows TabBar with 5 tabs'` 改名 `'shows TabBar with 6 tabs'`，`findsNWidgets(5)` → `findsNWidgets(6)`；並追加：

```dart
    testWidgets('新聞分頁在基本面與提醒之間', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      final labels = tester
          .widgetList<Tab>(find.byType(Tab))
          .map((t) => t.text)
          .toList();
      expect(labels.indexOf('stockDetail.tabNews'), 4);
      expect(labels.last, 'stockDetail.tabAlerts');
    });
```

（`buildTestWidget` 若未 override `stockNewsProvider`，切到其他分頁時不會建構新聞分頁——TabBarView 只建當前頁；預設停在技術分頁，不需 override。）

`buildTestWidget` 加參數 `List<Override> extraOverrides = const []`，接在 `overrides` 清單最後。在 `group('盤中即時報價', ...)`（有 `content` 這個已載入狀態）內、既有 `chevron_right` 換股測試旁追加：

```dart
    testWidgets('新聞分頁載入中原地換股：換股後只顯示新股票的新聞', (tester) async {
      widenViewport(tester);
      final pending2330 = Completer<StockNews>();
      NewsItemEntry n(String id) => NewsItemEntry(
        id: id,
        source: '鉅亨網',
        title: '標題$id',
        url: 'https://example.com/$id',
        category: 'OTHER',
        publishedAt: DateTime.now(),
        fetchedAt: DateTime.now(),
      );
      StockNews news(String id) => StockNews(
        items: [n(id)],
        otherStocksByNewsId: const {},
        nameStatus: StockNameStatus.matched,
      );
      await tester.pumpWidget(
        buildTestWidget(
          stockState: content,
          browsingContext: const ['2330', '2317'],
          extraOverrides: [
            stockNewsProvider.overrideWith(
              (ref, s) =>
                  s == '2330' ? pending2330.future : Future.value(news('2317-only')),
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('stockDetail.tabNews'));
      await tester.pump(const Duration(seconds: 1)); // 2330 仍在載入（shimmer，不可 pumpAndSettle）

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      pending2330.complete(news('2330-only'));
      await tester.pump();

      expect(find.text('標題2317-only'), findsOneWidget);
      expect(find.text('標題2330-only'), findsNothing);
    });
```

（imports 加 `dart:async`、`stock_news_provider.dart`、`stock_name_matcher.dart`、`package:flutter_riverpod/misc.dart`（`Override`，若檔內尚未 import）。若實作誤寫成 `symbol: widget.symbol`，換股後分頁仍是 2330，這條會紅。）

- [ ] **Step 8: 跑測試確認通過**

Run: `flutter test test/presentation/providers/stock_news_provider_test.dart test/presentation/screens/stock_detail/ test/presentation/providers/stock_detail_state_test.dart`
Expected: PASS。

- [ ] **Step 9: 個股頁 golden**

Run: `flutter test --tags golden test/presentation/screens/golden/stock_detail_screen_golden_test.dart`
Expected: FAIL（分頁列多了「新聞」）。用 `--update-goldens` 重產，開兩張圖（light／dark）目視確認：只有分頁列多一個分頁、其餘不變。其他 golden 不得有差異。

- [ ] **Step 10: analyze 並記錄進度**

Run: `flutter analyze` → No issues found。記錄進度。

---

### Task 9: 守門、排除清單定案、文案、全套驗證、mutation、審查、經同意提交

**Files:**
- Create: `test/domain/services/news/news_links_write_guard_test.dart`、`test/presentation/news_links_no_write_test.dart`、`test/presentation/widgets/news/news_copy_zh_test.dart`
- Modify: `lib/core/constants/news_link_params.dart`（定案清單＋審查紀錄）、`CHANGELOG.md`
- Delete: `test/_scratch_news_test.dart`

- [ ] **Step 1: 靜態守門（import 比對器或合併函式的檔案不得寫入 news_stock_map）**

`test/domain/services/news/news_links_write_guard_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 簡稱比對只供顯示，不得寫入 news_stock_map（評分的輸入）。任何 import
/// 比對器、合併函式或其 provider 的 lib 檔案，都不得出現寫入 news_stock_map
/// 的 API。
void main() {
  test('使用簡稱比對的 lib 檔案不寫 news_stock_map', () {
    const importMarkers = [
      'news/stock_name_matcher.dart',
      'news/news_stock_links.dart',
      'providers/news_link_provider.dart',
    ];
    // 使用比對器的檔案沒有理由碰 news_stock_map：連 drift 的 table 識別字
    // （managers／raw 寫入都會用到）一起擋
    const forbidden = [
      'NewsStockMapCompanion',
      'insertNewsWithMappings',
      'newsStockMap',
    ];

    final users = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('.drift.dart')) continue;
      final src = f.readAsStringSync();
      if (!importMarkers.any(src.contains)) continue;
      users.add(f.path);
      for (final word in forbidden) {
        expect(src.contains(word), isFalse, reason: '${f.path} 出現 $word');
      }
    }
    // sanity floor：至少要掃到熱度、快照、新聞頁、個股新聞等使用者，否則是假綠
    expect(users.length, greaterThanOrEqualTo(5), reason: users.join('\n'));
  });
}
```

Run: `flutter test test/domain/services/news/news_links_write_guard_test.dart` → PASS。
**驗守門會紅**：暫時在 `lib/presentation/providers/stock_news_provider.dart` 末尾加一行註解 `// NewsStockMapCompanion`，重跑 → FAIL；移除該行，重跑 → PASS。

- [ ] **Step 2: 行為守門（載入新聞頁與個股新聞後 news_stock_map 不變）**

`test/presentation/news_links_no_write_test.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';

/// 簡稱比對的結果只在記憶體：fixture 含「名稱比得到、代號比不到」的標題，
/// 載入後 news_stock_map 的完整集合必須與載入前相同。
void main() {
  test('載入新聞頁與個股新聞不寫入 news_stock_map', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '9901', name: '甲乙', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9902', name: '丙丁', market: 'TWSE'),
    ]);
    final at = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await db.insertNewsWithMappings(
      [
        NewsItemCompanion.insert(
          id: 'name-only',
          source: '鉅亨網',
          title: '甲乙營收創新高',
          url: 'https://example.com/1',
          category: 'OTHER',
          publishedAt: at,
        ),
        NewsItemCompanion.insert(
          id: 'code',
          source: '鉅亨網',
          title: '某公司(9902)公告',
          url: 'https://example.com/2',
          category: 'OTHER',
          publishedAt: at,
        ),
      ],
      [NewsStockMapCompanion.insert(newsId: 'code', symbol: '9902')],
    );
    Future<Set<(String, String)>> snapshot() async => {
      for (final r in await db.select(db.newsStockMap).get())
        (r.newsId, r.symbol),
    };
    final before = await snapshot();

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await container.read(newsProvider.notifier).loadData();
    final s = container.read(newsProvider);
    expect(s.relatedStocksByNewsId['name-only'], ['9901']); // 確實比對到了
    final sub = container.listen(stockNewsProvider('9901'), (_, _) {});
    addTearDown(sub.close);
    final stockNews = await container.read(stockNewsProvider('9901').future);
    expect(stockNews.items.map((n) => n.id), ['name-only']);

    expect(await snapshot(), before);
  });
}
```

Run → PASS。**驗守門會紅**：暫時在 `NewsNotifier.loadData` 的 `state = state.copyWith(allNews: news, …)` 之前加
`await db.into(db.newsStockMap).insert(NewsStockMapCompanion.insert(newsId: 'name-only', symbol: '9901'));`
（不用 `insertNewsWithMappings`：它在新聞列為空時直接 return，寫不進去），重跑 → FAIL；移除，重跑 → PASS。這行也會讓 Step 1 的靜態守門紅，一併確認。

- [ ] **Step 3: 真實翻譯檢查新文案**

`test/presentation/widgets/news/news_copy_zh_test.dart`（照 `test/presentation/widgets/alert_distance_text_zh_test.dart` 的 `_PreloadedAssetLoader`＋`EasyLocalization` 寫法）：在 `Builder` 內收集全部 11 條新文案

```dart
[
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
]
```

斷言等於

```dart
[
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
]
```

Run: `flutter test test/presentation/widgets/news/news_copy_zh_test.dart test/core/l10n/` → PASS（含 `app_strings_keys_test`、`no_investment_advice_copy_test`）。

- [ ] **Step 4: 排除清單定案（照 `NewsLinkParams` 檔頭程序）**

另建一份最新語料的副本給審查用（`replay.sqlite` 留給 Step 5 的熱度重放，不覆蓋）：
```bash
SP=<執行者的 scratchpad 目錄>/stocknews
DB="$HOME/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite"
rm -f "$SP/audit.sqlite"
sqlite3 "file:$DB?mode=ro&immutable=1" "VACUUM INTO '$SP/audit.sqlite'"
```

在 `test/_scratch_news_test.dart` 追加：

```dart
  test('link audit', () async {
    final db = AppDatabase.forToolFile(_db);
    final stocks = await db.getAllActiveStocks();
    final news = await db.select(db.newsItem).get();
    final m = StockNameMatcher.forNewsLinks(stocks);
    final hits = <String, List<String>>{};
    for (final n in news) {
      for (final s in m.matchInOrder(n.title)) {
        (hits[s] ??= []).add(n.title);
      }
    }
    String line(String s) =>
        '$s ${m.namesOf(s).join('/')} :${hits[s]!.length} | '
        '${hits[s]!.take(6).join(' || ')}';
    final byCount = hits.keys.toList()
      ..sort((a, b) => hits[b]!.length.compareTo(hits[a]!.length));
    final twoChar = [
      for (final s in byCount)
        if (m.namesOf(s).any((n) => n.length == 2) && hits[s]!.length >= 3) s,
    ];
    final longer = [
      for (final s in byCount)
        if (m.namesOf(s).every((n) => n.length >= 3)) s,
    ].take(30);
    // 非公司詞組不得包含 3 字以上有效公司名——用比對器實際用的名稱
    // （去 *、-KY 等後綴的基底名），不是 stock_master 的原字串
    final phraseHits = [
      for (final p in NewsLinkParams.nonCompanyPhrases)
        for (final s in stocks)
          for (final n in m.namesOf(s.symbol))
            if (n.length >= 3 && p.contains(n)) '$p ⊃ $n (${s.symbol})',
    ];
    File(_out).writeAsStringSync(
      [
        'news=${news.length} 2char>=3: ${twoChar.length}',
        '--- 2 字（>=3 次）',
        ...twoChar.map(line),
        '--- 3 字以上前 30',
        ...longer.map(line),
        '--- 詞組含 3 字以上公司名',
        ...phraseHits,
      ].join('\n'),
    );
    await db.close();
  }, timeout: Timeout.none, skip: _db.isEmpty ? '需要 --dart-define=NEWS_DB' : false);
```

（import `news_link_params.dart`）

Run: `flutter test test/_scratch_news_test.dart --plain-name 'link audit' --dart-define=NEWS_DB="$SP/audit.sqlite" --dart-define=NEWS_OUT="$SP/audit.txt"`，用 Read 讀 `$SP/audit.txt`。

逐條判斷（判準照檔頭第 3、4 點）：樣本出現非公司語意 → 誤配來自更長詞彙就加 `nonCompanyPhrases`，名稱本身是常見詞就加 `excludedNames`；「詞組含 3 字以上公司名」那節必須為空或逐條在 doc 註明理由。改完重跑，直到 2 字（≥3 次）與 3 字前 30 的樣本都沒有明顯誤配。最後把 `NewsLinkParams` 檔頭最後一段補上審查紀錄（日期、語料篇數與期間、各清單處理了哪些名稱與理由），例如：

```dart
/// **審查紀錄**：2026-10-0X，語料 N 篇（YYYY-MM-DD～YYYY-MM-DD）；2 字名
/// 30 天 ≥ 3 次共 M 個全審、3 字以上前 30 抽樣。排除：…（常見詞）；
/// 詞組：…（避免 …）。
```

（X、N、M 與清單以實際審查結果填入，不得照抄範例。）

- [ ] **Step 5: 用 App 的算法重算涵蓋率、最後一次熱度重放**

在 `test/_scratch_news_test.dart` 追加：

```dart
  test('coverage', () async {
    final db = AppDatabase.forToolFile(_db);
    final stocks = await db.getAllActiveStocks();
    final watch = {for (final w in await db.getWatchlist()) w.symbol};
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    final news = await (db.select(
      db.newsItem,
    )..where((t) => t.publishedAt.isBiggerOrEqualValue(cutoff))).get();
    final codeMap = await db.getNewsStockMappingsBatch([
      for (final n in news) n.id,
    ]);
    final heat = StockNameMatcher.fromStocks(stocks);
    final display = StockNameMatcher.forNewsLinks(stocks);
    String row(String name, Set<String> Function(NewsItemEntry) symbolsOf) {
      final counts = {for (final s in watch) s: 0};
      for (final n in news) {
        for (final s in symbolsOf(n).intersection(watch)) {
          counts[s] = counts[s]! + 1;
        }
      }
      final v = counts.values.toList()..sort();
      final pct = (int k) =>
          (100 * v.where((x) => x >= k).length / v.length).round();
      final median = v.length.isOdd
          ? v[v.length ~/ 2].toDouble()
          : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
      return '$name >=1:${pct(1)}% >=3:${pct(3)}% median:$median';
    }
    Set<String> codes(NewsItemEntry n) => {...?codeMap[n.id]};
    File(_out).writeAsStringSync(
      [
        row('A', codes),
        row('B', (n) => {...codes(n), ...heat.match(n.title)}),
        row('C', (n) => {...codes(n), ...display.match(n.title)}),
      ].join('\n'),
    );
    await db.close();
  }, timeout: Timeout.none, skip: _db.isEmpty ? '需要 --dart-define=NEWS_DB' : false);
```

Run（輸出只有百分比與中位數，不含股票）：
```bash
SP=<執行者的 scratchpad 目錄>/stocknews
flutter test test/_scratch_news_test.dart --plain-name coverage \
  --dart-define=NEWS_DB="$SP/audit.sqlite" --dart-define=NEWS_OUT="$SP/coverage.txt"
cat "$SP/coverage.txt"
```
Expected: C 的「≥1」明顯高於 B（spec 量測 87% vs 67%）。數字記入進度紀錄與提交訊息草稿；C 不高於 B 就停下來回報。

最後一次熱度重放：用 Task 1 的同一份 `replay.sqlite` 與基線 `heat_before.tsv`。
```bash
SP=<執行者的 scratchpad 目錄>/stocknews
flutter test test/_scratch_news_test.dart --plain-name 'heat replay dump' \
  --dart-define=NEWS_DB="$SP/replay.sqlite" --dart-define=NEWS_OUT="$SP/heat_final.tsv"
cmp "$SP/heat_before.tsv" "$SP/heat_final.tsv" && echo IDENTICAL
```
Expected: `IDENTICAL`。若 scratchpad 已被清空（兩個檔都不在），改用臨時 worktree 重建基線：`git worktree add "$SP/base" HEAD`，把只含 `heat replay dump` 一個測試的暫存檔放進 `$SP/base/test/`，在 `$SP/base` 對新建的 `replay.sqlite` 產生 `heat_before.tsv`，回到主工作目錄產生 `heat_final.tsv` 比對，最後 `git worktree remove --force "$SP/base"`（不可用 `git stash`）。

- [ ] **Step 6: 刪暫存測試、CHANGELOG**

```bash
rm test/_scratch_news_test.dart
git status --short | grep _scratch && echo "還有殘留" || echo "乾淨"
```

`CHANGELOG.md` 的 `## [Unreleased]`：

`### Added` 最上面加：
```markdown
- 自選與個股相關新聞：新聞頁新增「自選」篩選，只看自選與持股相關的新聞；個股頁新增「新聞」分頁，列出這檔近 30 天的新聞
  並可重新整理。新聞與股票的對應除了標題裡的代號，也比對公司簡稱（2 字簡稱排除審過的常見詞），各則新聞的股票標籤
  一併改用這套對應；比對只供顯示，不影響評分與熱度分析。重新整理新聞時，新聞來源全部或部分抓取失敗會提示
```

`### Fixed` 加：
```markdown
- 新聞頁的分組日期與預覽時間改用本地時間：凌晨到早上 8 點的新聞不再被歸到前一天，預覽時間不再差 8 小時
```

- [ ] **Step 7: 全套驗證**

確認沒有其他測試行程後：
```bash
flutter analyze
flutter test > "$SP/full.txt" 2>&1; tail -5 "$SP/full.txt"
flutter test --tags golden > "$SP/golden.txt" 2>&1; tail -5 "$SP/golden.txt"
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
```
Expected: analyze 無問題；全套全綠（記下總數，與開工前基線 +5898 比較）；golden 全綠；kernel 編譯成功（CLI 閉包仍是純 Dart）。

- [ ] **Step 8: mutation**

在 scratchpad 的 repo 副本做（規則見 Global Constraints）。對象與至少要做的突變：
- `stock_name_matcher.dart`：`_compare` 的詞組優先（拿掉／反轉）、`_displayNamesOf`（不去 `*`、不取基底名、`dash > 0` 改 `>= 0`）、`eligible`（`>=` 改 `>`、拿掉排除判斷）、`if (symbol != null)`、`nameStatusOf` 兩個分支、`matchInOrder` 的排序與 `seen`。
- `news_stock_links.dart`：拿掉 `..sort()`、拿掉 `seen.add`、`isNotEmpty` 條件。
- `user_dao.dart`：`isBiggerThanValue(0)` 改 `>=`、拿掉持股那段。
- `news_dao.dart`：`|` 改 `&`、拿掉代號子查詢、`isBiggerOrEqualValue` 改 `isBiggerThanValue`（界線那則要掉）。
- `news_provider.dart`：`_dedupedMine` 條件、`relatedStocksOf` 排序、`onNewsDataChanged` 的 `_isRefreshing` 判斷、兩處 `generation != _loadGeneration`。
- `news_fetch_provider.dart`：`allFailed`／`partiallyFailed` 邊界、`{…}.length` 改 `errors.length`、拿掉 `bump()`。
- `stock_news_provider.dart`：`contains(symbol)` 條件、`s != symbol`。
- `news_grouping.dart`：拿掉兩處 `toLocal()`。

存活者先確認是不是等價突變；不是就補測試（測試先對突變紅、還原後綠），結果寫進「實作後的修正」。

- [ ] **Step 9: 整段審查**

派一個最強模型的審查者（唯讀，不可 `dart run`、背景任務、碰 scratchpad、改檔），帶上：spec、本計畫、`git diff` 範圍（Task 1 起的全部改動）、本計畫的 Review Focus 原文、進度紀錄裡的所有裁定。Critical／Important 照 TDD 修（先寫會紅的測試），Minor 記入「實作後的修正」延後。

- [ ] **Step 10: 實機檢查（交給使用者）**

重編 macOS GUI（Debug），把以下清單交給使用者逐項確認，結果記入「實作後的修正」：
1. 新聞頁：「全部」之後有「自選 (N)」；切過去只剩自選與持股相關的新聞；預覽時間與台灣時間一致。
2. 個股頁各開一檔：3 字名稱的股票、2 字名稱在熱度白名單裡的股票、2 字名稱被排除的股票（說明變「簡稱是常見詞」）、上櫃股，看清單與上方說明。
3. 開台積電的新聞分頁快速捲動，不卡。
4. 盤中在個股新聞分頁按重新整理，確認抓到當天的新聞；關掉網路再按一次，出現「新聞來源都抓取失敗」且清單保留。

- [ ] **Step 11: 經同意提交**

把結果（全套數字、mutation、審查、涵蓋率、熱度重放 IDENTICAL、golden 變動）回報使用者，**等使用者說「提交」**再做；確認不在 09:00–13:30。提交訊息（純文字、不加 Co-Authored-By），內含排除清單審查摘要（語料規模、處理的名稱數）與涵蓋率數字：

```bash
git add -A lib test assets CHANGELOG.md docs/plans/2026-10-06-stock-news-plan.md
git status --short   # 確認沒有 _scratch、沒有 scratchpad 檔
git commit -F - <<'MSG'
feat: 自選與個股相關新聞

（依實際結果撰寫：新聞頁「自選」篩選、個股頁「新聞」分頁、代號＋簡稱對應只供顯示、
抓新聞共用與失敗提示、新聞時間改本地；排除清單審查摘要；涵蓋率 A/B/C；熱度重放一致）
MSG
```

提交後確認 post-commit 重編 CLI 完成（`BUILD_INFO` 為新 SHA）。

## 計畫審查紀錄

2026-10-06 執行前獨立審查（唯讀，對照 pubspec.lock 解析出的套件原始碼）：0 Critical；8 Important 全數納入：
- 兩條 Review Focus 測試改成真的經過風險路徑：斷網重新整理走真的 `NewsFetcher` 並卡住重讀；原地換股移到個股頁、走 `chevron_right`。
- 「依出現位置排序」改用位置與掃描順序不同的標題。
- 刪除錯誤的「本地截止點差 8 小時」宣稱：drift 以 `julianday()` 比較，連帶刪掉延後項、等價突變，並改正 DAO 註解。
- 列表日期轉本地。
- 熱度分頁返回也重讀自選。
- 熱度重放加下限檢查，並寫明 Bash 不保留環境變數。
- 詞組檢查改用比對器實際名稱。

Minor 納入：
- 移除未用的 import。
- 「先紅」預期的例外。
- 既有測試數改為 17。
- 相等性測試改用非 const 實例。
- 補兩條載入世代測試。
- 時區測試依時差挑時刻。
- 靜態守門擋 `newsStockMap`。
- 真實翻譯驗全部 11 條。
- 分頁 `primary: false`。
- 更正版本號。
- dump 檔尾補換行。
- 暫存測試不設逾時。

審查者列為產品取捨的點，裁定如下：
- **抓取全部失敗仍遞增版本**：維持。重讀無害，邏輯單純。
- **資料庫內部錯誤也顯示「新聞來源都抓取失敗」**：維持。罕見，log 有記錄。
- **新聞分頁不帶動外層收合**：採 `primary: false`，與其他分頁一致。

## 實作後的修正

**量測**（資料庫副本，2026-10-06／07）：
- 熱度重放：7,144 則、有比對結果 2,396 則；Task 1 改完與 Task 9 收尾各比一次，`fromStocks(...).match` 逐則相同。
- 新聞頁比對（滾動 7×24 小時 1,924 則，debug JIT 三次）：建比對器 15–17ms、合併 538–571ms，超過 100ms → 照 spec 改背景 isolate。
- 涵蓋率（實際自選清單，滾動 7×24 小時）：A 只用代號 52%／13%／中位 1；B 熱度白名單 65%／37%／1；C 定案清單 85%／52%／3（至少 1 則／至少 3 則／每檔中位數）。

**排除清單定案**：語料 7,144 篇標題（2026-09-06～10-06）；2 字名 30 天 ≥ 3 次共 196 個全審、3 字以上前 30 抽樣。排除名稱 27 個、非公司詞組 26 個、顯示別名 3 個（世界先進、中華車、中華汽車）；詞組含 3 字以上公司名的例外 3 條（台灣大學、台灣大道、信義新天地），理由寫在 `NewsLinkParams`。定案後 2 字 ≥ 3 次剩 170 個。

**裁定**：
- 背景計算放在 domain 的非 async static `NewsStockLinks.mergeInBackground`：`Isolate.run` 的 closure 只捕捉三個純資料參數；寫在 `NewsNotifier` 的 async 方法裡，closure 可能把 db 等不可傳物件帶進 isolate。個股新聞 provider 也用它，因為台積電候選上千則。
- `NewsNotifier.loadData` 的世代檢查放在「讀自選後」與「背景比對後」兩道。
- 刪除草稿詞組「中華信評」：「中華」已整個排除，它不再保護任何名稱。
- 「統一」「三星」「光罩」「國產」「建大」「南港」整個排除、不補別名：語料裡沒有可用的全稱，代號對應仍在。
- 詞組「達明年」「元太高」可能擋到真的公司新聞：目前語料只見非公司用法，接受，日後照定案程序重審。
- 個股頁 golden 不變：golden 有分頁列，但 1080 寬只露約 3.5 個分頁，第 5 個「新聞」在畫面外；分頁順序由 widget 測試釘住。
- 測試寫法：`testWidgets` 的 `skip` 只收 bool；空狀態有循環動畫與 0 秒計時器的測試改用 `pump(1s)`；暫存測試的 drift import 改 `hide isNull, isNotNull`。

**突變測試**：47 個——直接殺 42；補測試後殺 3（別名蓋過同名自然名、讀取失敗分支的世代檢查、部分失敗提示）；等價 2：
- 基底名 `dash > 0` 改 `>= 0`：空字串會被最短長度濾掉。
- 分頁 `_refreshing` 防護：重新整理中按鈕停用，抓取另有去重。

**整段審查**（0 Critical、1 Important、8 Minor）：
- Important 已修：抓取期間分頁被切走或換股拆掉，失敗提示會遺失 → `showNewsFetchFeedback` 改收 `await` 前取好的 `ScaffoldMessengerState` 與錯誤色（新聞頁同改），補測試 RED→GREEN；全套 +5993 ~2。
- 另改正兩句被本次改動弄成不實的註解。

**延後（Minor）**：
- 「今天／昨天」的 `now` 是台北時間、分組用裝置本地時區，裝置不在台北時區時會歸錯段。
- `reloadMySymbols` 可能被進行中的 `loadData` 以舊名單覆蓋（約半秒窗口，下次載入自癒）。
- 基底名與另一檔全名相同（大洋-KY 的「大洋」與 1321 大洋）時歸屬不固定；30 天 0 則命中。
- 原地換股測試沿用該檔既有的 2330／2317 fixture。
- 英文的部分失敗提示在 count＝1 時文法錯。
- 既有的延後項見「與 spec 的差異」與 spec「延後」。
