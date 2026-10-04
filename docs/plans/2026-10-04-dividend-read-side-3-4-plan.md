# 股利第 3-4 段：移除舊股利表與舊股利來源 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讀取端已全部改讀 `dividend_distribution`（3-1～3-3），這一段把舊的股利表 `dividend_history`、寫入它的已宣告股利同步、FinMind 股利 API 與相關的死程式碼移除；上市股東會日期照舊從 TWSE 已宣告股利取得。使用者看不到變化。

**Architecture:**
- **同步**：`DividendSyncer.sync()` 改名 `syncShareholderMeetings()`，只剩股東會：上市取自 TWSE 已宣告股利（t187ap45_L，同一個回應內嵌股東會日期），上櫃取自 TPEx 股東會（ap41_O）。上櫃已宣告股利（t187ap39_O）的呼叫連同 client 方法、模型、端點一起拿掉。
- **資料庫**：`DividendHistory` 自 Drift schema 移除；既有 DB 由 `_ensureRetiredSchemaDropped` 在 `beforeOpen` 以 `DROP TABLE IF EXISTS` 清掉，不 bump fingerprint。
- **其餘**：DAO 舊方法、FinMind 股利、`scoring_snapshot` 的 52 週新舊對照回放（它的舊版那半需要舊表）一併移除；過時註解與文件改正。

**Tech Stack:** Flutter／Dart 3、Drift 2.32（build_runner 重產 `*.drift.dart`）、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-01-dividend-read-side-design.md`。本計畫實作 §8「移除」與「驗證」一節的 3-4。3-1（a29602b5）、3-2（66133fc9）、3-3（0684f996＋e7df1168）已提交並 push；GUI 已重編到 e7df1168，使用者已目視確認。

## Global Constraints

- **前提**：GUI 已重編到 3-3 以後（✅ e7df1168，不再讀舊表）。但 3-3 的 GUI 跑更新時仍會呼叫舊的 `DividendSyncer.sync()` 寫舊表，而且不只手動更新會跑（見 Review Focus 1）：提交前先關掉 3-3 的 GUI，提交後到 GUI 重編完成之前完全不要開。
- **不 bump fingerprint**：舊表用 `_ensureRetiredSchemaDropped`（`DROP TABLE IF EXISTS`）清除，沿 2026-08-15 三張殭屍表的先例。
- **回滾不會把表建回來**：revert 3-4 之後，3-3 的程式碼每輪更新都會在股利寫入那一步記錯誤（`no such table`；股東會照寫），CLI 的結果變 PARTIAL、exit 1。要回滾就連同在 live DB 建回空表（DDL 取自 3-3 版的 `market_data_tables.drift.dart`；先備份、經同意才寫）。
- **Drift 改表要重產**：`dart run build_runner build --delete-conflicting-outputs`；`*.drift.dart` 有版控、一起提交。跑之前確認沒有其他 `dart run`／`flutter test`／`flutter run` 行程：`ps -axo pid=,ppid=,etime=,comm= | grep -E '/(dart|flutter)$'`（`comm` 只有執行檔名、不含參數）。IDEA 的 Dart analysis server 是常駐的 dart 行程，從 ppid 與執行時間認出來、不算。
- **update 鏈純 Dart**：`DividendSyncer`、`UpdateService` 在 CLI 閉包內；改完跑 `dart compile kernel tool/daily_update.dart -o build/daily_update.dill`。
- **股東會不得退步**：上市股東會照舊寫入；任一股東會來源失敗時不做全市場刪除；不在主檔的代號不寫事件。基準（2026-10-04 live，唯讀）：SHAREHOLDER_MEETING 上市 525、上櫃 943。
- **live DB 只唯讀查詢**：`file:...?mode=ro`，沒有 -wal 檔時加 `&immutable=1`。刪表的彩排用 `VACUUM INTO` 做出的副本；提交前經同意再做一份備份。
- **提交**：
  - commit／push 只在使用者說「提交」時做。Conventional Commits、中文、純文字、不加 Co-Authored-By。
  - 每個 task 結尾一律「記錄進度」，整段在 Task 6 一次提交。
  - 建議等週一（10/5）15:30 首輪的唯讀檢查做完再提交：首輪只驗 3-1～3-3，出問題時不必分辨是不是 3-4。
- **mutation**：在 scratchpad 的 repo 副本做；還原用備份檔，不用 git checkout；先跑直接測試、存活者再跑全部消費者測試；記錄被哪個斷言殺掉，編譯錯誤或沒 stub 的 mock 殺掉的不算。
- **測試檔批次改寫**：一律用本計畫附的腳本（逐段 `assert` 次數再取代），跑完接 `dart format` 與 `flutter analyze`。
- **不跑 `test/tool/run_*.dart`**：它們不是單元測試（檔名不是 `_test.dart`，`flutter test` 目錄掃描也不會跑），會打網路、FinMind 或跑很久的工具。

## Review Focus

1. **3-3 的 GUI 在表被刪之後跑更新**。
   - 誰先刪表：提交後 post-commit hook 約 9 秒重編兩支 CLI，之後第一個用新版程式碼開 DB 的行程就刪表——交易時段每 5 分鐘的盤中 CLI、15:30／21:30 的每日 CLI，或新版 GUI。
   - 3-3 的 GUI 跑更新的路徑有四條：手動更新、冷啟動自動更新（資料落後交易日時，開 app 就跑）、今日頁下拉重新整理（落後時也會觸發更新）、已開著的 GUI 離開 30 分鐘以上再回到前景（重新載入資料時走冷啟動更新的同一個判斷）。所以「只是開一下」或「一直開著沒關」都會寫舊表。
   - 預期：不會發生——提交前先 Cmd+Q 關掉 3-3 的 GUI，提交後立刻重編 GUI（Task 6），重編完成前不開。萬一發生，舊版 `sync()` 寫舊表那一步被 catch、記成錯誤（`DB 寫入: ... no such table`），股東會照寫，其他步驟照跑；那一輪顯示部分失敗，下次用新版 GUI 就好。
   - 不可以：為此 bump fingerprint。
   - 舊 binary 無法單元測試，靠 Task 6 的提交後步驟。
2. **既有 DB 第一次用新版開啟**。
   - 預期：只刪 `dividend_history`；股利配發五張表、價格、使用者資料一列不少；之後每次開啟冪等。
   - 用新版程式碼開的 DB 都會刪：live DB，以及 `tool/calibration.db`（它的 `dividend_history` 是 0 列，刪了不影響校準）。
   - 測試在 Task 4（退役測試），並在 Task 6 用 live 副本逐表比對列數。
3. **上市股東會**：拿掉上櫃已宣告股利之後，上市的股東會日期仍從 TWSE 已宣告股利寫入；任一股東會來源（TWSE 或 TPEx）失敗時不刪任何既有事件；不在主檔的代號、沒有股東會日期的列不寫。
   - 測試在 Task 1。
4. **股東會來源撞到限流或網路錯誤**：syncer 往上拋、不刪任何股東會事件；限流仍中止本輪（不再打除權除息）；網路錯誤記「股東會同步失敗」後照常跑完；generic 失敗由 syncer 收集、UpdateService 轉發。
   - 測試在 Task 1（syncer 的上市／上櫃 × 限流／網路四條；`update_service_test` 的觸發改成股東會來源）。
5. **新裝機與 fingerprint reset**：Drift 不再建這張表，索引整理不會對不存在的表動作，drop 清單與宣告索引仍零交集。
   - 測試在 Task 4（退役測試、`index_hygiene_test` 不變量）。

## 與 spec 的差異（核可計畫時一併確認）

1. **上櫃已宣告股利整條拿掉**
   - spec：「移除股利寫入與上櫃 t187ap39_O 呼叫」。
   - 本計畫：呼叫拿掉後 `TpexClient.getDeclaredDividends`、`TpexDeclaredDividend`、`ApiEndpoints.tpexDeclaredDividend`、fixture 與它們的測試都成了死程式碼，一併移除。
2. **改名**
   - `DividendSyncer.sync()` → `syncShareholderMeetings()`，`DividendSyncResult` → `ShareholderMeetingSyncResult`（拿掉 `dividendsUpserted`）；UpdateService 的日誌與錯誤字樣改成「股東會同步」。
   - 為什麼：它只剩股東會，舊名會讓人以為還在同步股利。
3. **`scoring_snapshot` 的 52 週新舊對照回放整段移除**
   - spec：「`test/tools/scoring_snapshot.dart` 改讀新事件」。主快照在 3-2 已改讀新事件（`BatchDataBuilder.buildDividendContexts`）。
   - 回放的舊版那半（`_legacyWeek52`）只能讀舊表，它的用途（3-2 提交前的量測）已完成。量測結果沒有寫進 repo；要重跑就從 66133fc9 的 `test/tools/scoring_snapshot.dart` 取回這段（需要一份還有舊表的 DB 副本）。
   - `docs/CALIBRATION.md` 原本指向這個回放當範例，改指向生產的 `BatchDataLoader`／`BatchDataBuilder.buildDividendContexts`（同樣是截 400 日曆天窗＋`priceContext`）。
4. **spec 點名的註解多數在 3-1／3-2 已改**
   - `price_continuity.dart`、`analysis_coordinator_service.dart`、`dividend_coverage.dart`、`tool/backfill.dart`、`tool/replay_calibrator.dart`、`docs/RULE_ENGINE.md`、`.claude/rules/update-pipeline.md`（已是「五張表」）都已是新敘述。
   - spec 點名的殘留 `AnalysisParams.dividendLookbackYears`、`StockData.dividendHistory` 與評分 DTO 的舊欄位（`dividendHistoryMap`）在 3-2／3-3 已移除：2026-10-04 在 lib／tool／test grep `dividendLookbackYears`、`dividendHistoryMap` 為 0，`dividendHistory` 只剩 Drift 產物、DAO 與 i18n 鍵 `stockDetail.dividendHistory`（區段標題，不是這張表）。
   - 3-4 只改仍指向舊表或已刪 API 的地方（Task 5 清單），包括測試檔裡的歷史註解。
5. **資料保留期計畫**：`docs/plans/2026-09-26-data-retention-plan.md`（暫緩實作）的政策表拿掉 `dividend_history` 一行；五張股利表的規則該文件已另有註明。
6. **提交時機**：建議等週一首輪檢查之後（見 Global Constraints）。

## 檔案結構

| 檔案 | 責任 | 動作 |
|:--|:--|:--|
| `lib/domain/services/update/dividend_syncer.dart` | 股東會＋除權除息同步 | `sync` → `syncShareholderMeetings`，拿掉舊股利寫入與上櫃已宣告股利 |
| `lib/domain/services/update_service.dart` | 每日更新 | 呼叫改名、日誌與錯誤字樣 |
| `lib/data/remote/tpex_client.dart`、`lib/data/models/tpex/tpex_declared_dividend.dart`、`lib/data/models/tpex/models.dart`、`lib/core/constants/api_endpoints.dart` | 上櫃已宣告股利 | 移除 |
| `lib/data/remote/finmind_client.dart`、`lib/data/models/finmind/dividend.dart`、`lib/data/models/finmind/models.dart` | FinMind 股利 | 移除 |
| `lib/data/database/tables/market_data_tables.dart`、`lib/data/database/app_database.dart`、`*.drift.dart` | schema | 移除 `DividendHistory`；退役清單；索引清單 |
| `lib/data/database/dao/dividend_dao.dart` | DAO | 移除 `getDividendHistory`／`getDividendHistoryBatch`／`insertDividendData` |
| `test/tools/scoring_snapshot.dart` | 評分快照工具 | 移除 52 週新舊對照回放 |
| 註解與文件（Task 5 清單）、`CHANGELOG.md` | 文件 | 改正 |

---

### Task 1: 股東會同步不再經過舊股利（syncer、UpdateService、上櫃已宣告股利）

**Files:**
- Modify: `lib/domain/services/update/dividend_syncer.dart`
- Modify: `lib/domain/services/update_service.dart`（`_syncAuxiliaryData` 的股利／股東會區塊）
- Modify: `lib/data/remote/tpex_client.dart`（刪 `getDeclaredDividends`）
- Modify: `lib/data/models/tpex/models.dart`（刪 export）
- Modify: `lib/core/constants/api_endpoints.dart`（刪 `tpexDeclaredDividend`）
- Delete: `lib/data/models/tpex/tpex_declared_dividend.dart`、`test/data/models/tpex/tpex_declared_dividend_test.dart`、`test/fixtures/remote/tpex_declared_dividend.json`
- Test: `test/domain/services/update/dividend_syncer_test.dart`、`test/domain/services/update_service_test.dart`、`test/data/remote/api_fixture_parsing_test.dart`

**Interfaces:**
- Produces:
  - `Future<ShareholderMeetingSyncResult> DividendSyncer.syncShareholderMeetings()`
  - `class ShareholderMeetingSyncResult { final int meetingEventsCreated; final List<String> errors; bool get hasErrors; }`
  - UpdateService 錯誤字樣：`股東會同步失敗: <來源錯誤>`、`股東會同步失敗 (rate limit): ...`

- [ ] **Step 1: 改測試（紅燈）**

`<scratchpad>/t34_1_tests.py`（`<repo>`＝repo 根目錄）：

```python
# -*- coding: utf-8 -*-
# 3-4 Task 1：測試改成股東會同步（紅燈）
import os
import re
os.chdir('<repo>')


def read(p):
    return open(p, encoding='utf-8', newline='').read()


def write(p, s):
    open(p, 'w', encoding='utf-8', newline='').write(s)


def edit(p, old, new, count=1):
    s = read(p)
    assert s.count(old) == count, (p, old[:80], s.count(old))
    write(p, s.replace(old, new))


# ── dividend_syncer_test ──
p = 'test/domain/services/update/dividend_syncer_test.dart'
edit(p,
     "import 'package:daredevil/data/database/app_database.dart';\n",
     "import 'package:daredevil/core/exceptions/app_exception.dart';\n"
     "import 'package:daredevil/data/database/app_database.dart';\n")
edit(p, "    registerFallbackValue(<DividendHistoryCompanion>[]);\n", '')
edit(p, "    when(() => db.insertDividendData(any())).thenAnswer((_) async {});\n", '')
edit(p,
     "      // TPEX 股利空、股東會成功回一筆（上櫃 5483）\n",
     "      // TPEX 股東會成功回一筆（上櫃 5483）\n")
edit(p,
     "      when(\n"
     "        () => tpex.getDeclaredDividends(),\n"
     "      ).thenAnswer((_) async => <TpexDeclaredDividend>[]);\n",
     '', count=3)
edit(p, "await syncer.sync();", "await syncer.syncShareholderMeetings();", count=3)
s = read(p)
assert s.endswith('  });\n}\n')
s = s[:-len('  });\n}\n')] + (
    "\n"
    "    // 限流與網路錯誤往上拋（由 UpdateService 決定中止或續跑），而且拋出前\n"
    "    // 不可動既有股東會事件\n"
    "    for (final (kind, error) in const [\n"
    "      ('限流', RateLimitException('429')),\n"
    "      ('網路錯誤', NetworkException('timeout')),\n"
    "    ]) {\n"
    "      test('上市來源$kind：往上拋，不刪不寫股東會事件', () async {\n"
    "        when(() => twse.getDeclaredDividends()).thenThrow(error);\n"
    "        when(() => tpex.getShareholderMeetings()).thenAnswer((_) async => []);\n"
    "\n"
    "        await expectLater(\n"
    "          syncer.syncShareholderMeetings(),\n"
    "          throwsA(same(error)),\n"
    "        );\n"
    "        verifyNever(() => db.deleteAutoGeneratedEventsByTypes(any()));\n"
    "        verifyNever(() => db.insertStockEvents(any()));\n"
    "      });\n"
    "\n"
    "      test('上櫃股東會$kind：往上拋，不刪不寫股東會事件', () async {\n"
    "        when(() => twse.getDeclaredDividends()).thenAnswer(\n"
    "          (_) async => [\n"
    "            TwseDeclaredDividend(\n"
    "              symbol: '2330',\n"
    "              companyName: '台積電',\n"
    "              dividendYear: 2026,\n"
    "              cashDividend: 4.0,\n"
    "              stockDividend: 0.0,\n"
    "              shareholderMeetingDate: DateTime(2026, 8, 15),\n"
    "            ),\n"
    "          ],\n"
    "        );\n"
    "        when(() => tpex.getShareholderMeetings()).thenThrow(error);\n"
    "\n"
    "        await expectLater(\n"
    "          syncer.syncShareholderMeetings(),\n"
    "          throwsA(same(error)),\n"
    "        );\n"
    "        verifyNever(() => db.deleteAutoGeneratedEventsByTypes(any()));\n"
    "        verifyNever(() => db.insertStockEvents(any()));\n"
    "      });\n"
    "    }\n"
    "\n"
    "    test('上市：不在主檔的代號、沒有股東會日期的列都不寫事件', () async {\n"
    "      when(() => twse.getDeclaredDividends()).thenAnswer(\n"
    "        (_) async => [\n"
    "          TwseDeclaredDividend(\n"
    "            symbol: '2330',\n"
    "            companyName: '台積電',\n"
    "            dividendYear: 2026,\n"
    "            cashDividend: 4.0,\n"
    "            stockDividend: 0.0,\n"
    "            shareholderMeetingDate: DateTime(2026, 8, 15),\n"
    "          ),\n"
    "          TwseDeclaredDividend(\n"
    "            symbol: '9999',\n"
    "            companyName: '不在主檔',\n"
    "            dividendYear: 2026,\n"
    "            cashDividend: 1.0,\n"
    "            stockDividend: 0.0,\n"
    "            shareholderMeetingDate: DateTime(2026, 8, 16),\n"
    "          ),\n"
    "          // 在主檔、但這筆沒有股東會日期\n"
    "          TwseDeclaredDividend(\n"
    "            symbol: '5483',\n"
    "            companyName: '中美晶',\n"
    "            dividendYear: 2026,\n"
    "            cashDividend: 1.0,\n"
    "            stockDividend: 0.0,\n"
    "          ),\n"
    "        ],\n"
    "      );\n"
    "      when(() => tpex.getShareholderMeetings()).thenAnswer((_) async => []);\n"
    "\n"
    "      await syncer.syncShareholderMeetings();\n"
    "\n"
    "      final batchArg =\n"
    "          verify(() => db.insertStockEvents(captureAny())).captured.single\n"
    "              as List<StockEventCompanion>;\n"
    "      expect(batchArg.map((e) => e.symbol.value), ['2330']);\n"
    "    });\n"
    "\n"
    "    test('TPEX 股東會失敗、TWSE 成功時不得全市場刪除股東會事件', () async {\n"
    "      when(() => twse.getDeclaredDividends()).thenAnswer(\n"
    "        (_) async => [\n"
    "          TwseDeclaredDividend(\n"
    "            symbol: '2330',\n"
    "            companyName: '台積電',\n"
    "            dividendYear: 2026,\n"
    "            cashDividend: 4.0,\n"
    "            stockDividend: 0.0,\n"
    "            shareholderMeetingDate: DateTime(2026, 8, 15),\n"
    "          ),\n"
    "        ],\n"
    "      );\n"
    "      when(\n"
    "        () => tpex.getShareholderMeetings(),\n"
    "      ).thenThrow(Exception('tpex transient boom'));\n"
    "\n"
    "      final result = await syncer.syncShareholderMeetings();\n"
    "\n"
    "      verifyNever(() => db.deleteAutoGeneratedEventsByTypes(any()));\n"
    "      verifyNever(() => db.insertStockEvents(any()));\n"
    "      expect(result.hasErrors, isTrue);\n"
    "    });\n"
    "  });\n"
    "}\n")
write(p, s)

# ── update_service_test：觸發改成股東會來源 ──
p = 'test/domain/services/update_service_test.dart'
s = read(p)
# 單行 stub 有 6 處（6 格縮排 5 處、8 格 1 處）：整行比對，縮排不同也不會互相吃掉
single = re.compile(
    r"^[ ]*when\(\(\) => (?:mockTpex|tpex)\.getDeclaredDividends\(\)\)"
    r"\.thenAnswer\(\(_\) async => \[\]\);\n",
    re.M)
s, n = single.subn('', s)
assert n == 6, ('單行 stub', n)
write(p, s)
# generic 失敗 → syncer 收集、UpdateService 轉發
edit(p,
     "    test('股利 syncer 內部收集的錯誤應轉發到 result.errors', () async {\n",
     "    test('股東會同步內部收集的錯誤應轉發到 result.errors', () async {\n")
edit(p,
     "      // 股利來源 generic 失敗 → DividendSyncer 收進自身 result.errors（不 throw）\n"
     "      when(\n"
     "        () => mockTpex.getDeclaredDividends(),\n"
     "      ).thenThrow(Exception('payload broken'));\n"
     "      when(() => mockTpex.getShareholderMeetings()).thenAnswer((_) async => []);\n",
     "      // 股東會來源 generic 失敗 → DividendSyncer 收進自身 result.errors（不 throw）\n"
     "      when(\n"
     "        () => mockTpex.getShareholderMeetings(),\n"
     "      ).thenThrow(Exception('payload broken'));\n")
edit(p,
     "      // DividendSyncResult.errors 必須被 caller 讀取並轉發，否則靜默\n"
     "      expect(result.errors, anyElement(contains('股利')));\n",
     "      // ShareholderMeetingSyncResult.errors 必須被 caller 讀取並轉發，否則靜默\n"
     "      expect(result.errors, anyElement(startsWith('股東會同步失敗')));\n")
# 限流 → 中止本輪
edit(p,
     "    test('已宣告股利撞到限流：不再打除權除息', () async {\n",
     "    test('股東會撞到限流：不再打除權除息', () async {\n")
edit(p,
     "      when(\n"
     "        () => mockTpex.getDeclaredDividends(),\n"
     "      ).thenThrow(const RateLimitException('redirect loop'));\n",
     "      when(\n"
     "        () => mockTpex.getShareholderMeetings(),\n"
     "      ).thenThrow(const RateLimitException('redirect loop'));\n")
# 網路錯誤 → 記錯誤後續跑
edit(p,
     "    test('已宣告股利拋網路錯誤：除權除息仍照常同步（兩者分開 try）', () async {\n",
     "    test('股東會拋網路錯誤：除權除息仍照常同步（兩者分開 try）', () async {\n")
edit(p,
     "      // sync() 對 NetworkException rethrow → UpdateService 記錯誤後繼續\n"
     "      when(\n"
     "        () => mockTpex.getDeclaredDividends(),\n"
     "      ).thenThrow(const NetworkException('t187ap45 timeout'));\n",
     "      // syncShareholderMeetings() 對 NetworkException rethrow → UpdateService\n"
     "      // 記錯誤後繼續\n"
     "      when(\n"
     "        () => mockTpex.getShareholderMeetings(),\n"
     "      ).thenThrow(const NetworkException('ap41 timeout'));\n")
edit(p,
     "      expect(result.errors, anyElement(contains('股利/股東會')));\n",
     "      expect(result.errors, anyElement(startsWith('股東會同步失敗')));\n")
assert 'getDeclaredDividends' not in read(p), '還有沒處理到的上櫃已宣告股利 stub'

# ── api_fixture_parsing_test：拿掉上櫃已宣告股利解析 ──
p = 'test/data/remote/api_fixture_parsing_test.dart'
s = read(p)
start = s.index("    test('TPEx 已宣告股利 OpenAPI 解析', () async {\n")
end = s.index("    test('TPEx 內部人轉讓解析', () async {\n")
write(p, s[:start] + s[end:])

for f in ['test/data/models/tpex/tpex_declared_dividend_test.dart',
          'test/fixtures/remote/tpex_declared_dividend.json']:
    os.remove(f)
print('ok')
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/domain/services/update/dividend_syncer_test.dart test/domain/services/update_service_test.dart`
Expected: FAIL——`dividend_syncer_test` 編譯錯誤 `The method 'syncShareholderMeetings' isn't defined`；`update_service_test` 的 generic 與網路兩條紅（舊程式碼的字樣是「股利/股東會同步失敗」，不以「股東會同步失敗」開頭）。限流那條只改觸發來源、行為不變，新舊都綠

- [ ] **Step 3: 實作**

1. `lib/domain/services/update/dividend_syncer.dart`：
   - 類別註解第一段換成：

```dart
/// 股東會 + 除權除息同步器
///
/// 從 TWSE/TPEX 取得：
/// 1. 股東會日程寫入 StockEvent（eventType = SHAREHOLDER_MEETING，
///    [syncShareholderMeetings]）：上市的日期內嵌在 TWSE 已宣告股利回應，
///    上櫃取自 TPEx 股東會資料
/// 2. 除權除息計算結果寫入 DividendDistribution（[syncDistributions]）
///
/// 2 只管本月；歷史月份由 `DividendBackfiller` 回補（同一步驟、本月同步之後）。
///
/// 1 在 UpdateService._syncAuxiliaryData()（並行階段）呼叫，與
/// MarketIndexSyncer、TdccHoldingSyncer 同級；2 在更新步驟 6.6（上櫃候選補充
/// 之後、評分之前）依序執行。
```

   - 整個 `sync()`（含文件註解）換成：

```dart
  /// 同步股東會日程
  ///
  /// 各來源獨立 try/catch，單一來源失敗不影響其他；股東會事件的全市場重建
  /// 只在所有已嘗試來源皆成功時執行（見 Phase 3），避免部分失敗誤刪既有資料。
  /// [RateLimitException]／[NetworkException] 往上拋，由 UpdateService 處理。
  Future<ShareholderMeetingSyncResult> syncShareholderMeetings() async {
    var meetingEventsCreated = 0;
    final errors = <String>[];

    // 追蹤各股東會來源本輪是否失敗。Phase 3 的全市場刪除只有在「所有已嘗試的
    // 股東會來源皆成功」時才安全——否則 meetingCompanions 只含部分市場，
    // delete-then-rewrite 會清掉失敗來源上一輪正確寫入的事件且無法補回。
    var twseMeetingsFailed = false;
    var tpexMeetingsFailed = false;

    // 取得 DB 中所有已知股票（FK constraint — 過濾 1101B 等特別股）
    final knownStocks = await _db.getAllActiveStocks();
    final knownSymbols = knownStocks.map((s) => s.symbol).toSet();
    final meetingCompanions = <StockEventCompanion>[];

    // ==================================================
    // Phase 1: 上市股東會（TWSE 已宣告股利回應內嵌股東會日期）
    // ==================================================
    if (_twse != null) {
      try {
        final twseData = await _twse.getDeclaredDividends();
        for (final item in twseData) {
          if (!knownSymbols.contains(item.symbol)) continue;
          if (item.shareholderMeetingDate == null) continue;
          meetingCompanions.add(
            StockEventCompanion.insert(
              symbol: Value(item.symbol),
              eventType: 'SHAREHOLDER_MEETING',
              eventDate: item.shareholderMeetingDate!,
              title: '${item.symbol} ${item.companyName} 股東會',
              description: const Value(null),
              isAutoGenerated: const Value(true),
            ),
          );
        }
        AppLogger.info('DividendSyncer', 'TWSE 已宣告股利（取股東會）: ${twseData.length} 筆');
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        twseMeetingsFailed = true;
        AppLogger.warning('DividendSyncer', 'TWSE 已宣告股利（股東會）同步失敗', e);
        errors.add('TWSE 已宣告股利: $e');
      }
    }

    // ==================================================
    // Phase 2: 上櫃股東會（TPEX ap41_O）
    // ==================================================
    if (_tpex != null) {
      try {
        final meetings = await _tpex.getShareholderMeetings();
        for (final meeting in meetings) {
          if (!knownSymbols.contains(meeting.symbol)) continue;

          meetingCompanions.add(
            StockEventCompanion.insert(
              symbol: Value(meeting.symbol),
              eventType: 'SHAREHOLDER_MEETING',
              eventDate: meeting.meetingDate,
              title:
                  '${meeting.symbol} ${meeting.companyName} ${meeting.meetingType}',
              description: Value(_buildMeetingDescription(meeting)),
              isAutoGenerated: const Value(true),
            ),
          );
        }
        AppLogger.info('DividendSyncer', 'TPEX 股東會: ${meetings.length} 筆');
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        tpexMeetingsFailed = true;
        AppLogger.warning('DividendSyncer', 'TPEX 股東會同步失敗', e);
        errors.add('TPEX 股東會: $e');
      }
    }

    // ==================================================
    // Phase 3: 寫入股東會 StockEvent（去重後）
    // ==================================================
    // deleteAutoGeneratedEventsByTypes 是全市場（不分 symbol/來源）刪除，故
    // 只有在所有已嘗試的股東會來源本輪皆成功時才可 delete-then-rewrite。若任一
    // 來源失敗，meetingCompanions 僅含成功來源的部分市場，此時重建會連同失敗
    // 來源上一輪正確寫入的事件一併清空且無法補回——改為略過本輪重建、保留既有
    // 事件，待下輪所有來源皆成功再重建。
    final meetingSourceFailed = twseMeetingsFailed || tpexMeetingsFailed;
    if (meetingCompanions.isNotEmpty && meetingSourceFailed) {
      AppLogger.warning('DividendSyncer', '部分股東會來源失敗，略過重建以保留既有事件');
      errors.add('股東會事件: 部分來源失敗，略過重建以保留既有資料');
    } else if (meetingCompanions.isNotEmpty) {
      try {
        // 去重：同一 symbol + 同一日期只保留一筆（TWSE 和 TPEX 可能重複）
        final uniqueMeetings = _deduplicateEvents(meetingCompanions);

        await _db.transaction(() async {
          // 只刪除 SHAREHOLDER_MEETING 類型的自動事件，不影響其他
          await _db.deleteAutoGeneratedEventsByTypes(const [
            'SHAREHOLDER_MEETING',
          ]);
          await _db.insertStockEvents(uniqueMeetings);
        });
        meetingEventsCreated = uniqueMeetings.length;
        AppLogger.info('DividendSyncer', '股東會事件寫入: $meetingEventsCreated 筆');
      } catch (e) {
        AppLogger.warning('DividendSyncer', '股東會事件寫入失敗', e);
        errors.add('股東會事件: $e');
      }
    }

    return ShareholderMeetingSyncResult(
      meetingEventsCreated: meetingEventsCreated,
      errors: errors,
    );
  }
```

   - 刪掉 `_toDividendCompanion`（整個方法含文件註解）。
   - `DividendSyncResult` 整個類別換成：

```dart
/// 股東會同步結果
class ShareholderMeetingSyncResult {
  const ShareholderMeetingSyncResult({
    this.meetingEventsCreated = 0,
    this.errors = const [],
  });

  final int meetingEventsCreated;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}
```

2. `lib/domain/services/update_service.dart` 的股利／股東會區塊（`final divResult = await _dividendSyncer.sync();` 那段 try/catch）換成：

```dart
      try {
        final meetingResult = await _dividendSyncer.syncShareholderMeetings();
        if (meetingResult.meetingEventsCreated > 0) {
          AppLogger.info(
            'UpdateService',
            '股東會同步: ${meetingResult.meetingEventsCreated} 筆',
          );
        }
        // DividendSyncer 內部以 per-source catch 收集 generic 失敗，
        // 不 throw — 必須讀取 errors 轉發，否則對使用者靜默
        for (final err in meetingResult.errors) {
          ctx.result.errors.add('股東會同步失敗: $err');
        }
      } on RateLimitException catch (e) {
        ctx.rateLimitedAbort = true;
        AppLogger.warning('UpdateService', '股東會同步失敗 (rate limit)', e);
        ctx.result.recordError('股東會同步失敗 (rate limit): $e', e);
      } catch (e) {
        AppLogger.warning('UpdateService', '股東會同步失敗', e);
        ctx.result.recordError('股東會同步失敗: $e', e);
      }
```

3. `lib/data/remote/tpex_client.dart`：刪掉 `/// 取得上櫃已宣告股利` 起到 `getDeclaredDividends()` 方法結束（下一個是 `/// 取得上櫃內部人股權轉讓申報資料`）。
4. `lib/data/models/tpex/models.dart`：刪 `export 'tpex_declared_dividend.dart';`；刪除 `lib/data/models/tpex/tpex_declared_dividend.dart`。
5. `lib/core/constants/api_endpoints.dart`：刪 `/// 上櫃已宣告股利 - OpenAPI（免費、無限制）` 起的兩行文件、`tpexDeclaredDividend` 常數（兩行），以及它前面的空行。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/update/ test/domain/services/update_service_test.dart test/data/remote/ test/data/models/tpex/`
Expected: 全部 PASS

Run: `grep -rnE "TpexDeclaredDividend|(mockTpex|_tpex|tpex)\.getDeclaredDividends|tpexDeclaredDividend" lib test --include='*.dart'`
Expected: 沒有輸出（`getDeclaredDividends` 只剩 TWSE 的：`twse_client.dart`、syncer 的 `_twse.`、syncer 測試的 `twse.`、`api_fixture_parsing_test` 的 TWSE 解析）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 2: 移除 FinMind 股利

**Files:**
- Modify: `lib/data/remote/finmind_client.dart`（刪 `getDividends`）
- Modify: `lib/data/models/finmind/models.dart`（刪 `export 'dividend.dart';`）
- Delete: `lib/data/models/finmind/dividend.dart`
- Test: `test/data/loaders/stock_fundamentals_loader_dividend_test.dart`

- [ ] **Step 1: 先改測試**

`test/data/loaders/stock_fundamentals_loader_dividend_test.dart`：
- 檔頭兩行換成：

```dart
// 個股頁股利摘要的載入：只讀 DB（配發表、完整度事實、股票名稱）；資料
// 不完整是摘要裡的建置中，只有讀取失敗回 null
```

- 測試名稱 `'配發表＋完整度事實 → 摘要；不打 FinMind 股利 API'` 改成 `'配發表＋完整度事實 → 摘要'`。
- 刪掉 `// 兩種呼叫形狀都驗：mocktail 依具名參數的組合比對` 與其後兩個 `verifyNever(() => finMind.getDividends(...))`（FinMind 股利 API 整個不存在了，「不打它」由結構保證）。

- [ ] **Step 2: 刪除**

1. `lib/data/remote/finmind_client.dart`：刪掉 `/// 取得股利資料` 起到 `getDividends` 結束（下一個是 `/// 取得本益比/股價淨值比資料`）。
2. `lib/data/models/finmind/models.dart`：刪 `export 'dividend.dart';`。
3. 刪除 `lib/data/models/finmind/dividend.dart`。

- [ ] **Step 3: 確認通過**

Run: `flutter test test/data/`
Expected: 全部 PASS

Run: `grep -rn "FinMindDividend\|getDividends(\|TaiwanStockDividend" lib test tool --include='*.dart'`
Expected: 沒有輸出

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 記錄進度**（不 commit）

---

### Task 3: 移除 `scoring_snapshot` 的 52 週新舊對照回放

**Files:**
- Modify: `test/tools/scoring_snapshot.dart`
- Modify: `docs/CALIBRATION.md`

- [ ] **Step 1: 刪除**

1. `test/tools/scoring_snapshot.dart`：
   - 刪掉從 `  // ── 52 週新舊對照回放（3-2 提交前的量測，spec「驗證」3-2）` 到這個 `test(...)` 結束（`timeout: const Timeout(Duration(minutes: 30)),\n  );`）。
   - 刪掉檔尾的 `_legacyWeek52`（含文件註解）。
   - 跑 `flutter analyze`，依它報的 `unused_import` 一併移除不再用到的 import。
2. `docs/CALIBRATION.md`，把

```markdown
> 再以 `DividendCompleteness.priceContext` 建股利情境（`test/tools/scoring_snapshot.dart` 的 52 週回放
> 兩件都有做）。回補只到今年往前 5 年的 1 月，最早約一年的回放日仍會是 incomplete。
```

   換成

```markdown
> 再以 `DividendCompleteness.priceContext` 建股利情境（生產的評分批次就是這樣做：`BatchDataLoader` 讀
> 400 日曆天的價格窗，`BatchDataBuilder.buildDividendContexts` 以窗首日到評分日建情境）。回補只到今年往前
> 5 年的 1 月，最早約一年的回放日仍會是 incomplete。
```

- [ ] **Step 2: 確認**

Run: `grep -n "52 週新舊對照\|_legacyWeek52\|getDividendHistoryBatch\|WEEK52_" test/tools/scoring_snapshot.dart docs/CALIBRATION.md`
Expected: 沒有輸出

Run: `flutter analyze`
Expected: `No issues found!`（這個檔不在全套測試內，但 analyze 會分析它）

- [ ] **Step 3: 記錄進度**（不 commit）

---

### Task 4: 退役 `dividend_history`（schema、DAO、索引清單、Drift 重產）

**Files:**
- Modify: `lib/data/database/app_database.dart`（`_ensureRetiredSchemaDropped`、`legacyRedundantIndexes`、`@DriftDatabase` 表清單）
- Modify: `lib/data/database/tables/market_data_tables.dart`（刪 `DividendHistory`；`DividendDistribution` 文件）
- Modify: `lib/data/database/dao/dividend_dao.dart`（刪三個方法；mixin 文件）
- Regenerate: `lib/data/database/app_database.drift.dart`、`lib/data/database/tables/market_data_tables.drift.dart`
- Modify: `test/helpers/portfolio_data_builders.dart`（刪 `createTestDividendHistory`）
- Modify: `tool/check_db_range.dart`（表清單刪 `dividend_history`）
- Test: `test/data/database/retired_schema_cleanup_test.dart`、`test/data/database/index_hygiene_test.dart`

- [ ] **Step 1: 寫失敗測試**

1. `test/data/database/retired_schema_cleanup_test.dart`：
   - 檔頭註解最後加一段：

```dart
//
// 2026-10：舊股利表 dividend_history 加入退役清單——讀取端已全部改讀
// dividend_distribution，同步也不再寫它。
```

   - `buildLegacyDb()` 在 `insiderHolding` 那筆寫入之後、`await db.close();` 之前加下面這段。順序有關係：
     - 舊表的 `symbol` 參照 `stock_master`（Drift 的 DDL 是 `REFERENCES stock_master (symbol) ON DELETE CASCADE`，`beforeOpen` 之後外鍵檢查是開的），2330 寫進主檔之後才能寫舊表與配發表。
     - 紅燈階段 Drift 自己已經建了這張表，`CREATE TABLE IF NOT EXISTS` 不動作、`INSERT` 寫進 Drift 的表；綠燈階段才由這段 DDL 建出來，所以 DDL 照抄 Drift 的欄位與外鍵。
     - 第一段 SQL 不含單引號，用單引號字串（`prefer_single_quotes`）。

```dart
    // 退役前的舊股利表一列 + 五張股利表之一的一列,驗證刪舊表不波及新表
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS dividend_history ('
      'symbol TEXT NOT NULL REFERENCES stock_master (symbol) '
      'ON DELETE CASCADE, year INTEGER NOT NULL, '
      'cash_dividend REAL NOT NULL DEFAULT 0, '
      'stock_dividend REAL NOT NULL DEFAULT 0, '
      'ex_dividend_date TEXT, ex_rights_date TEXT, '
      'PRIMARY KEY (symbol, year))',
    );
    await db.customStatement(
      'INSERT INTO dividend_history (symbol, year, cash_dividend) '
      "VALUES ('2330', 2025, 18.0)",
    );
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 7,
        stockSharesPerThousand: 0,
      ),
    ]);
```

   - 在「三張退役表逐一清除」那條之後加：

```dart
  test('🚨 既有 DB 重開：舊股利表 dividend_history 清除，股利配發表不動', () async {
    await buildLegacyDb();

    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();

    expect(await tableNames(db), isNot(contains('dividend_history')));
    expect(await db.getDividendDistributions('2330'), hasLength(1));
    await db.close();
  });

  test('新裝機：schema 不再建 dividend_history', () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();

    expect(await tableNames(db), isNot(contains('dividend_history')));
    expect(
      db.allTables.map((t) => t.actualTableName),
      isNot(contains('dividend_history')),
    );
    await db.close();
  });
```

   - 「冪等：連開三次不炸」迴圈內加 `expect(await tableNames(db), isNot(contains('dividend_history')));`。
2. `test/data/database/index_hygiene_test.dart`：`legacyDdl` 刪 `'idx_dividend_history_symbol': 'dividend_history (symbol)',`，並在原本 daily_recommendation 那段註解後補一行：

```dart
    // (idx_dividend_history_symbol 2026-10 隨 dividend_history 退役刪除,
    // 理由同上)
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/data/database/retired_schema_cleanup_test.dart test/data/database/index_hygiene_test.dart`
Expected: FAIL——退役測試的 `dividend_history` 還在；`index_hygiene_test` 的不變量（DDL 表與 drop 清單不同步）

- [ ] **Step 3: 實作**

1. `lib/data/database/app_database.dart`：
   - `_ensureRetiredSchemaDropped` 的表清單加 `'dividend_history',`；文件註解第一段之後加：

```dart
  ///
  /// 2026-10 加入 `dividend_history`：跟上面三張不同，它有資料（2026-10-04
  /// live 3,557 列），但讀取端已全部改讀 `dividend_distribution`、同步也不再
  /// 寫它，沒有人讀。更早編出的 GUI／CLI 在更新時仍會寫它，表刪掉後那一步
  /// 記錯誤（`no such table`）；revert 這次移除也不會把表建回來。
```

   - 「何時 bump fingerprint」一節（`/// **任何 schema 改動都要 bump ...**` 底下）只列了「純新增的表」一個例外，刪表卻要 bump，跟 2026-08-15 起的退役清理先例矛盾。在既有那條例外之後加：

```dart
  ///
  /// 例外：退役的表或欄位加進 [_ensureRetiredSchemaDropped] 就地 DROP 而不
  /// bump（2026-08-15 起的先例）——bump 會 wipe 價格等全部非白名單表。
```

   - `legacyRedundantIndexes` 刪 `'idx_dividend_history_symbol',`，在 daily_recommendation 那段註解後補：

```dart
    // idx_dividend_history_symbol 2026-10 隨 dividend_history 退役(整張表
    // DROP,索引隨表消失)
```

   - `@DriftDatabase` 的表清單刪 `DividendHistory,`，上面的 `// 股利歷史` 改成 `// 股利（除權除息配發與完整度事實）`。
2. `lib/data/database/tables/market_data_tables.dart`：
   - 刪掉 `/// 股利歷史 Table` 起到 `class DividendHistory` 結束。
   - `DividendDistribution` 文件裡的 `（[DividendHistory] 以 (symbol, year) 為 PK，同年多次配息會互相覆蓋）` 刪掉（句子改成 `季配、半年配、月配各期分列。`）。
3. `lib/data/database/dao/dividend_dao.dart`：刪 `getDividendHistory`、`insertDividendData`、`getDividendHistoryBatch`；mixin 文件 `/// 股利歷史操作` 改成 `/// 股利操作：除權除息配發、逐月完成／失敗紀錄、完整度事實`。
4. 重產 Drift：

```bash
ps -axo pid=,ppid=,etime=,comm= | grep -E '/(dart|flutter)$'
dart run build_runner build --delete-conflicting-outputs
git diff --stat -- '*.drift.dart'
grep -c "DividendHistory\|dividend_history" lib/data/database/app_database.drift.dart lib/data/database/tables/market_data_tables.drift.dart
```

Expected:
- `ps` 只看到 IDEA 的 analysis server（見 Global Constraints），沒有別的 `dart run`／`flutter test`
- 只有 `app_database.drift.dart`、`market_data_tables.drift.dart` 變動，內容是 `DividendHistory` 相關的刪除
- 兩個檔的 `DividendHistory`／`dividend_history` 都是 0（`app_database.drift.dart` 原本有一條 `TableUpdate('dividend_history', ...)` 的串聯刪除規則，也要跟著消失）

5. `test/helpers/portfolio_data_builders.dart`：刪 `// DividendHistoryEntry` 分隔註解區塊與 `createTestDividendHistory`。
6. `tool/check_db_range.dart`：表清單刪 `'dividend_history',`。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/data/database/`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 5: 註解、文件、CHANGELOG

**Files:**
- Modify: `lib/data/database/tables/event_tables.dart`、`lib/data/repositories/event_repository.dart`、`lib/data/models/twse/exright_preannouncement.dart`、`lib/data/database/dao/event_dao.dart`、`lib/domain/services/update/fundamental_syncer.dart`、`lib/data/loaders/stock_fundamentals_loader.dart`
- Modify: `test/data/database/dao/dividend_distribution_dao_test.dart`、`test/data/repositories/event_repository_exright_test.dart`、`test/data/repositories/event_repository_test.dart`、`test/data/loaders/stock_fundamentals_loader_test.dart`
- Modify: `docs/plans/2026-09-26-data-retention-plan.md`、`CHANGELOG.md`

- [ ] **Step 1: 改寫**

原文欄照檔案內容逐字比對；多行的各行前面都有原本的縮排（例如 `event_repository_test.dart` 那三行前面各有兩格空白），表格裡省略。

| 檔案 | 原文 | 改成 |
|:--|:--|:--|
| `fundamental_syncer.dart` | `/// （與 DividendSyncResult.errors 同 pattern）。` | `/// （與 ShareholderMeetingSyncResult.errors 同 pattern）。` |
| `stock_fundamentals_loader.dart` | `// 限流是全域狀態:後續股利/估值的 API call 也會限流,fallback 只是` | `// 限流是全域狀態:後續估值的 API call 也會限流,fallback 只是` |
| `stock_fundamentals_loader_test.dart` | `// 了,後面股利/估值的 API call 也會限流,繼續 fallback 只是燒重試;吞掉` | `// 了,後面估值的 API call 也會限流,繼續 fallback 只是燒重試;吞掉` |
| `event_tables.dart` | `/// - EX_DIVIDEND: 除息日（自動從 DividendHistory 匯入）`<br>`/// - EX_RIGHTS: 除權日（自動從 DividendHistory 匯入）` | `/// - EX_DIVIDEND: 除息日（自動從除權除息預告表匯入，見`<br>`///   EventRepository.syncDividendEvents）`<br>`/// - EX_RIGHTS: 除權日（同上）` |
| `event_repository.dart` | `/// 原實作讀 dividend_history 的日期欄——但大宗「已宣告股利」同步只帶` | `/// 原實作讀舊股利表（2026-10 已移除）的日期欄——但大宗「已宣告股利」同步只帶` |
| `exright_preannouncement.dart` | `/// 日期，dividend_history 的 (symbol, year) 主鍵也裝不下季配息一年多個`<br>`/// 除息日（見 EventRepository.syncDividendEvents）。` | `/// 日期；除權除息配發表（dividend_distribution）只有已發生的除權息，`<br>`/// 沒有預告（見 EventRepository.syncDividendEvents）。` |
| `event_dao.dart` | `/// 百餘筆,逐筆 await 是 N+1;比照 [DividendDaoMixin.insertDividendData]` | `/// 百餘筆,逐筆 await 是 N+1;比照 [DividendDaoMixin.upsertDividendDistributions]` |
| `dividend_distribution_dao_test.dart` | `// 舊表 dividend_history 以 (symbol, year) 為 PK、insertOrReplace 寫入，` | `// 舊的股利表（2026-10 已移除）以 (symbol, year) 為 PK、insertOrReplace 寫入，` |
| `event_repository_exright_test.dart` | `/// 8/7-8/12 因果成對;原功能因 dividend_history 無日期而自上線空轉)。` | `/// 8/7-8/12 因果成對;原功能因舊股利表無日期而自上線空轉)。` |
| `event_repository_test.dart` | `// event_repository_exright_test.dart(資料源由 dividend_history 改為`<br>`// TWSE/TPEx 除權息預告表,舊測試斷言的是已移除的 watchlist-scoped`<br>`// dividend_history 讀取行為)。` | `// event_repository_exright_test.dart(資料源由舊股利表改為`<br>`// TWSE/TPEx 除權息預告表,舊測試斷言的是已移除的 watchlist-scoped`<br>`// 舊股利表讀取行為)。` |
| `docs/plans/2026-09-26-data-retention-plan.md` | `    'dividend_history': _keepAll,` | （整行刪除） |

`CHANGELOG.md`：`[Unreleased]` 的 `### Changed` 段落之後（下一個 `## [` 之前）加：

```markdown
### Removed

- 舊的股利表（每檔每年一列、多數沒有除息日）、寫入它的已宣告股利同步與 FinMind 股利 API：股利表、ETF 殖利率、
  投資組合與 52 週規則都已改讀除權除息配發表。既有資料庫在新版第一次開啟時刪除這張表；上市股東會日期照舊取自
  TWSE 已宣告股利，每輪更新少打一次上櫃已宣告股利 API
```

- [ ] **Step 2: 先找讀這些文件的測試**（`CHANGELOG.md`、data-retention 計畫，以及 Task 3 改的 `docs/CALIBRATION.md`）

Run: `grep -rnE "CHANGELOG|data-retention-plan|CALIBRATION" test --include='*_test.dart'`
Expected: 只有兩處、都不讀這些檔：`test/docs/rule_engine_doc_test.dart`（字串裡提到 `docs/CALIBRATION.md`，它讀的是 `RULE_ENGINE.md`）、`test/domain/domain_layer_purity_test.dart`（註解）。不加 `--include` 會多列出 `test/tool/run_*.dart`；它們不是測試，不跑（見 Global Constraints）。

Run: `grep -rnE "File\(['\"][^'\"]*\.md" test --include='*_test.dart'`
Expected: 只有 `test/docs/scripts_documented_test.dart` 的 `CLAUDE.md`、`README.md`（3-4 不改這兩份）。`rule_engine_doc_test` 以常數 `docPath` 讀 `RULE_ENGINE.md`，這個 grep 抓不到；3-4 也不改它。

- [ ] **Step 3: 驗證**

Run: `flutter test test/data/ test/docs/ test/domain/domain_layer_purity_test.dart`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 記錄進度**（不 commit）

---

### Task 6: 全套驗證、副本彩排、mutation、審查、經同意提交、重編

- [ ] **Step 1: 靜態檢查與全套測試**（log 寫到 scratchpad）

```bash
dart format lib test tool
flutter analyze
flutter test > <scratchpad>/full_3_4.log 2>&1; tail -c 300 <scratchpad>/full_3_4.log
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
dart compile kernel tool/backfill_dividend_distributions.dart -o build/backfill_dividend_distributions.dill
```

Expected: analyze 無 issue；全套通過；兩個 kernel 編譯成功

- [ ] **Step 2: 殘留引用**

```bash
grep -rnE "dividend_history|DividendHistory|getDividendHistory|insertDividendData|FinMindDividend|getDividends\(|TaiwanStockDividend|TpexDeclaredDividend|tpexDeclaredDividend|t187ap39|dividendsUpserted|DividendSyncResult|createTestDividendHistory|_legacyWeek52" \
  lib bin tool test .claude docs CLAUDE.md README.md \
  | grep -v "^docs/plans/2026-10-0" | grep -v "\.drift\.dart:"
```

Expected: 只剩
- `lib/data/database/app_database.dart`：`_ensureRetiredSchemaDropped` 的 `'dividend_history'` 與它的文件註解、`legacyRedundantIndexes` 旁的退役註解
- `test/data/database/retired_schema_cleanup_test.dart`：建舊表與斷言
- `test/data/database/index_hygiene_test.dart`：退役註解
- `docs/plans/2026-07-26-pipeline-review-findings.md` 第 47 行（`DividendSyncResult`）：歷史審查紀錄，照原樣保留

另跑 `grep -c "DividendHistory\|dividend_history" lib/data/database/*.drift.dart lib/data/database/tables/*.drift.dart`，Expected：全部 0。

- [ ] **Step 3: 副本彩排（既有 DB 開啟後只少一張表）**

1. 在 scratchpad 建 repo 副本（`rsync -rl`，不保留 mtime；含 `.dart_tool`〔`package_config.json` 在裡面，沒有它要重跑 pub get〕，但排除 `.dart_tool/flutter_build`、`build/`、`.git/`；Step 4 的 mutation 也用它）。
2. 唯讀做 live DB 副本：有 -wal 檔時 `sqlite3 "file:<live>?mode=ro" "VACUUM INTO '<scratchpad>/r34.sqlite'"`；沒有 -wal 時 URI 加 `&immutable=1`。
3. 開啟前記下各表列數：

```bash
for t in $(sqlite3 <scratchpad>/r34.sqlite "select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name"); do
  printf '%s %s\n' "$t" "$(sqlite3 <scratchpad>/r34.sqlite "select count(*) from \"$t\"")"
done > <scratchpad>/r34_before.txt
```

4. 在 repo 副本放 `test/_r34_open_test.dart`，用新版程式碼開一次（跑 `beforeOpen`）：

```dart
// 3-4 副本彩排：用新版程式碼開一次 DB 副本，只在 scratchpad 的 repo 副本跑
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  final dbPath = Platform.environment['R34_DB'];
  test('3-4 副本彩排', skip: dbPath == null, () async {
    final db = AppDatabase.forToolFile(dbPath!);
    await db.customSelect('SELECT 1').get();
    final integrity = await db
        .customSelect('PRAGMA integrity_check')
        .getSingle();
    expect(integrity.data.values.first, 'ok');
    await db.close();
  });
}
```

   Run（在 repo 副本）：`R34_DB=<scratchpad>/r34.sqlite flutter test test/_r34_open_test.dart`
5. 同第 3 步產生 `r34_after.txt`，`diff r34_before.txt r34_after.txt`。

Expected: 唯一差異是 `dividend_history 3557` 那行消失（列數以副本當下為準）；其他每張表列數相同；integrity ok。

- [ ] **Step 4: mutation**

做法同 3-3：直接測試先跑；存活者再跑全部消費者測試：`test/domain/services test/data test/app test/integration/recommendation_flow_test.dart test/presentation/providers/today_provider_test.dart test/tool/backfill_dividend_distributions_test.dart`（`DividendSyncer`／`UpdateService` 在 `test/` 的消費者，加上用檔案 DB 開 `AppDatabase` 的 backfill 工具測試，2026-10-04 grep；`test/tool` 只跑點名的那個檔）。至少涵蓋：

| 檔案 | mutant | 直接測試 |
|:--|:--|:--|
| app_database | 退役清單拿掉 `'dividend_history'` | `test/data/database/retired_schema_cleanup_test.dart` |
| app_database | `@DriftDatabase` 表清單放回 `DividendHistory`（副本裡要跑 build_runner 重產；兩個 `.drift.dart` 一起備份、一起還原）：退役清單還在，既有 DB 照刪，只有「新裝機」那條的 `db.allTables` 斷言會紅 | `test/data/database/retired_schema_cleanup_test.dart` |
| dividend_syncer | `twseMeetingsFailed = true` 拿掉；TWSE 迴圈的 `knownSymbols` 過濾拿掉；`shareholderMeetingDate == null` 的略過拿掉（讓 `!` 對 null 拋錯）；`tpexMeetingsFailed = true` 拿掉 | `test/domain/services/update/dividend_syncer_test.dart` |
| dividend_syncer | 四個 `rethrow` 各自拿掉（上市／上櫃 × `on RateLimitException`／`on NetworkException`；拿掉後落進 generic catch，不再往上拋） | `test/domain/services/update/dividend_syncer_test.dart` |
| update_service | errors 轉發的迴圈拿掉；`ctx.rateLimitedAbort = true` 拿掉 | `test/domain/services/update_service_test.dart` |

- [ ] **Step 5: 審查**

送 opus 審查（`pr-review-toolkit:code-reviewer`）：範圍＝`git diff` 加未追蹤新檔；附本計畫與 spec 路徑、Review Focus 五條、「與 spec 的差異」六條、Step 2 與 Step 3 的輸出。限制：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。修正後以 SendMessage 請同一位審查者複審，直到 Ready。

- [ ] **Step 6: 報告並等「提交」**

報告：全套測試數、殘留引用結果、副本彩排的逐表比對、mutation、審查輪數與修正；建議提交時機（週一首輪檢查之後）；提交前請使用者同意做 live 備份。

Commit message 草稿：

```
refactor: 移除舊股利表與舊股利來源

- 舊股利表 dividend_history 自 schema 移除，既有 DB 由退役清理在開啟時
  DROP（不 bump fingerprint）；DAO 舊方法與索引清單一併拿掉
- 股東會同步不再經過已宣告股利寫入：上市日期照舊取自 TWSE 已宣告股利，
  上櫃已宣告股利（t187ap39_O）的呼叫、client、模型與端點移除；
  DividendSyncer.sync() 改名 syncShareholderMeetings()
- 移除 FinMind 股利 API 與 scoring_snapshot 的 52 週新舊對照回放（舊版那半
  需要舊表，3-2 的量測已完成）
```

- [ ] **Step 7: 經同意後備份與提交**（使用者說「提交」才做）

1. 唯讀做 live 備份：`VACUUM INTO` 到 `<備份目錄>/afterclose-<日期>-pre-3-4.sqlite`（備份目錄當下跟使用者確認），`sqlite3` 開備份查 `dividend_history` 列數與 live 相同。
2. 請使用者先 Cmd+Q 關掉正在跑的 3-3 GUI（`pgrep -x Daredevil` 只印 PID，確認沒有輸出）。已開著的 GUI 回到前景時也會跑更新（Review Focus 1）。
3. 提交。

- [ ] **Step 8: 提交後**

1. 確認 post-commit hook 已把兩支 CLI 重編到新 commit（`~/Library/Logs/daredevil-cli-rebuild.log` 最後一行、兩支 `BUILD_INFO`）。
2. **立刻**重編 GUI（macOS Debug）。重編完成前不開 3-3 的 GUI——冷啟動自動更新與下拉重新整理也會跑舊的 `sync()`（Review Focus 1）。
3. 下一輪 launchd 跑完後唯讀查：
   - `dividend_history` 不在 `sqlite_master`。
   - SHAREHOLDER_MEETING 上市、上櫃筆數不少於基準（2026-10-04：525／943；股東會季節外自然變動時，逐筆看消失的是不是已過期的會議）。
   - 日誌有「股東會同步: N 筆」**而且**沒有「股東會同步失敗」；沒有 `no such table`。「股東會同步: N 筆」只在寫入筆數大於 0 時才印，沒有這行就去查 SHAREHOLDER_MEETING 的筆數有沒有變。
