# 測試慣例（test/）

## Widget 測試慣例

```dart
import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization(); // 使用 .tr() 的 widget 必須呼叫
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  testWidgets('example', (tester) async {
    widenViewport(tester); // 避免 RenderFlex overflow
    await tester.pumpWidget(buildTestApp(MyWidget(), brightness: Brightness.light));
  });
}
```

**注意事項**：
- `SectionHeader` 使用 `flutter_animate`，需 `await tester.pump(const Duration(seconds: 1))` 推進動畫
- `buildTestApp` 預設語系 en_US：依語系分級的數字（`Localizations.localeOf(context)` → `LocalizedNumberFormat`／各畫面格式函式）在 widget 測試走英文路徑（K/M/B）。要驗中文輸出或中文長字串版面（溢位）時傳 `locale: const Locale('zh', 'TW')`
- `buildProviderTestApp` 的 `zhTranslations`／`enTranslations`（互斥）載入真實翻譯：驗中文或英文字串的版面（溢位、截斷）用它；key 字串比實際文字長，會造成假溢位
- 測試預設字型 FlutterTest 每個字（含數字、「…」）都是字級見方的方塊，量不出真實文字寬度；沒指定 `fontFamily` 的文字一律用它，`FontLoader` 載同名字型也換不掉。要量真實寬度時，用 `FontLoader` 把系統字型載成 `'Roboto'`（測試主題的字族），並讓被測文字從 `Theme` 取字族（熱力圖 painter 即如此）
- go_router：`context.push` 之後 `router.routerDelegate.currentConfiguration.uri` 仍是底層位置；驗 push 後的位置用 `router.state.matchedLocation`
- `TechnicalIndicatorService` 為 plain class，直接 `new` 使用，不需 mock
- `FinMindRevenue.date` 型別為 `String`（非 `DateTime`）
- `PortfolioPositionData.quantity` 型別為 `double`（非 `int`）
- 每個測試檔案自行宣告 mock classes，不使用共享 mock 檔案

## mocktail 與 DB mock

- **具名參數沒寫＝期望預設值（通常 null）**：`when`／`verify` 裡沒列的具名參數會拿來比對。生產碼開始傳新的具名參數（例如 `ledger:`、`date:`）時，既有 stub／verify 要同一次補上 `any(named: '...')`，否則 stub 對不上、回 null 拋 `TypeError`。nullable 參數的 `any` 不需要 `registerFallbackValue`。
- **`MockAppDatabase` 的 transaction**：要在 mock 上 stub 的 transaction 呼叫，生產碼必須寫明型別參數（例如 `transaction<void>(...)`）——mocktail 用 `==` 比對 type arguments，沒寫時推論出的型別對不上 `<void>` stub。stub 寫 `when(() => mockDb.transaction<void>(any())).thenAnswer((inv) async { await (inv.positionalArguments[0] as Future<void> Function())(); });`。有回傳值的照型別 stub，例如 `transaction<int>`（見 `warning_repository_test.dart`）。
- **`thenThrow` 是同步拋出**：被測程式先啟動多個 Future 再一起等（`awaitPairSettled` 等）時，同步拋出會在掛上 handler 之前就被外層 catch 接走，測不到配對邏輯、還可能剛好綠。模擬 client 失敗用 `thenAnswer((_) async => throw e)`（真的 client 是 async，錯誤走 Future）。
- **Drift 日期欄**存成 ISO 文字（`build.yaml` 的 `store_date_time_values_as_text`）：本地 DateTime 附裝置 offset（台北機器上是 `+08:00`，CI runner 上是 `+00:00`），讀回是本地時間；`DateTime.utc` 存成 `Z`，讀回仍是 UTC。`DateContext.normalize` 是**裝置本地午夜**，不是 UTC。用真 in-memory DB 比對日期時兩邊都先 normalize，不要寫死 offset 字串。
