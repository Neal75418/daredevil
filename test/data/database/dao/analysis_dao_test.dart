import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';

void main() {
  late AppDatabase db;

  final today = DateTime.utc(2025, 6, 15);
  final yesterday = DateTime.utc(2025, 6, 14);

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertTestStocks() async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2454', name: '聯發科', market: 'TWSE'),
    ]);
  }

  group('AnalysisDao', () {
    setUp(() async {
      await insertTestStocks();
    });

    group('getAnalysisForDate', () {
      test('returns analyses sorted by score descending', () async {
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(80.0),
            scoreLong: const Value(80.0),
          ),
        );
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2317',
            date: today,
            trendState: 'DOWN',
            scoreShort: const Value(30.0),
            scoreLong: const Value(30.0),
          ),
        );
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2454',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(50.0),
            scoreLong: const Value(50.0),
          ),
        );

        final analyses = await db.getAnalysisForDate(
          today,
          horizon: Horizon.short,
        );

        expect(analyses.length, 3);
        expect(analyses[0].symbol, '2330');
        expect(analyses[1].symbol, '2454');
        expect(analyses[2].symbol, '2317');
      });

      test('returns empty list for date with no data', () async {
        final analyses = await db.getAnalysisForDate(
          today,
          horizon: Horizon.short,
        );

        expect(analyses, isEmpty);
      });
    });

    group('getAnalysis', () {
      test('returns analysis for specific symbol and date', () async {
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(80.0),
            scoreLong: const Value(80.0),
          ),
        );

        final analysis = await db.getAnalysis('2330', today);

        expect(analysis, isNotNull);
        expect(analysis!.trendState, 'UP');
        expect(analysis.scoreShort, 80.0);
      });

      test('returns null for non-existent entry', () async {
        final analysis = await db.getAnalysis('2330', today);

        expect(analysis, isNull);
      });
    });

    group('insertAnalysis', () {
      test('upserts on conflict', () async {
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(50.0),
            scoreLong: const Value(50.0),
          ),
        );
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'DOWN',
            scoreShort: const Value(30.0),
            scoreLong: const Value(30.0),
          ),
        );

        final analysis = await db.getAnalysis('2330', today);

        expect(analysis!.trendState, 'DOWN');
        expect(analysis.scoreShort, 30.0);
      });
    });

    group('getAnalysesBatch', () {
      test('returns map of symbol to analysis', () async {
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(80.0),
            scoreLong: const Value(80.0),
          ),
        );
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2317',
            date: today,
            trendState: 'DOWN',
            scoreShort: const Value(30.0),
            scoreLong: const Value(30.0),
          ),
        );

        final result = await db.getAnalysesBatch(['2330', '2317'], today);

        expect(result.length, 2);
        expect(result['2330']!.trendState, 'UP');
        expect(result['2317']!.trendState, 'DOWN');
      });

      test('returns empty map for empty symbols', () async {
        final result = await db.getAnalysesBatch([], today);

        expect(result, isEmpty);
      });

      test('ignores symbols without data', () async {
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(80.0),
            scoreLong: const Value(80.0),
          ),
        );

        final result = await db.getAnalysesBatch(['2330', '2317'], today);

        expect(result.length, 1);
        expect(result['2330'], isNotNull);
        expect(result['2317'], isNull);
      });
    });

    group('clearAnalysisForDate', () {
      test('removes all analyses for a date', () async {
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(80.0),
            scoreLong: const Value(80.0),
          ),
        );
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2317',
            date: today,
            trendState: 'DOWN',
            scoreShort: const Value(30.0),
            scoreLong: const Value(30.0),
          ),
        );

        final deleted = await db.clearAnalysisForDate(today);

        expect(deleted, 2);

        final remaining = await db.getAnalysisForDate(
          today,
          horizon: Horizon.short,
        );
        expect(remaining, isEmpty);
      });

      test('does not affect other dates', () async {
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: today,
            trendState: 'UP',
            scoreShort: const Value(80.0),
            scoreLong: const Value(80.0),
          ),
        );
        await db.insertAnalysis(
          DailyAnalysisCompanion.insert(
            symbol: '2330',
            date: yesterday,
            trendState: 'UP',
            scoreShort: const Value(70.0),
            scoreLong: const Value(70.0),
          ),
        );

        await db.clearAnalysisForDate(today);

        final yesterdayData = await db.getAnalysis('2330', yesterday);
        expect(yesterdayData, isNotNull);
      });
    });

    group('getModeStockScores(真 DB;2026-08-29 稽核:三個 mode tab 的分數源零測試)', () {
      // 這條 SQL 是 Today 三 tab(起漲/強勢/回檔)的分數唯一來源;寫入端
      // 8/15 才出過 69/455 檔算錯的事故——讀取端契約在此釘住,寫入端必須
      // 滿足它。
      DailyReasonCompanion row(
        String symbol,
        String type, {
        required double short,
        required double long,
        DateTime? date,
        int rank = 1,
      }) => DailyReasonCompanion.insert(
        symbol: symbol,
        date: date ?? today,
        reasonType: type,
        evidenceJson: '{}',
        ruleScoreShort: Value(short),
        ruleScoreLong: Value(long),
        rank: rank,
      );

      test('🚨 只加總 mode 內的 rule,雙 horizon 各自獨立', () async {
        await db.insertReasons([
          row('2330', 'VOLUME_SPIKE', short: 18, long: 5),
          row('2330', 'PRICE_BREAKOUT', short: 20, long: 7, rank: 2),
          // mode 外的規則:分數再大也不得混入
          row('2330', 'EPS_TURNAROUND', short: 99, long: 99, rank: 3),
          // 只有 mode 外規則的股票:整檔不得出現在結果
          row('2317', 'EPS_TURNAROUND', short: 50, long: 50),
        ]);

        final scores = await db.getModeStockScores(today, [
          'VOLUME_SPIKE',
          'PRICE_BREAKOUT',
        ]);

        expect(scores, hasLength(1));
        expect(scores.single.symbol, '2330');
        expect(scores.single.modeScoreShort, 38, reason: '18+20,不含 mode 外的 99');
        expect(scores.single.modeScoreLong, 12, reason: '5+7——兩 horizon 不得互換');
      });

      test('日期為精確等值:別日與帶時分的同日列都不計入', () async {
        await db.insertReasons([
          row('2330', 'VOLUME_SPIKE', short: 10, long: 10),
          row('2330', 'VOLUME_SPIKE', short: 77, long: 77, date: yesterday),
          // 呼叫端契約:date 必須 midnight 正規化——帶時分的列等值比對
          // 不會命中(這裡釘住語意,讓寫入端若哪天寫進帶時分的日期,
          // 症狀是「分數少了」而不是無聲雙倍)
          row(
            '2330',
            'VOLUME_SPIKE',
            short: 55,
            long: 55,
            date: today.add(const Duration(hours: 13)),
            rank: 2,
          ),
        ]);

        final scores = await db.getModeStockScores(today, ['VOLUME_SPIKE']);
        expect(scores.single.modeScoreShort, 10);
      });

      test('負分照實加總,不得被 clamp(Mode C 回檔負分場景)', () async {
        await db.insertReasons([
          row('2330', 'BREAK_MA20', short: -8, long: -3),
          row('2330', 'VOLUME_SPIKE', short: 20, long: 6, rank: 2),
          row('2454', 'BREAK_MA20', short: -8, long: -12),
        ]);

        final scores = await db.getModeStockScores(today, [
          'BREAK_MA20',
          'VOLUME_SPIKE',
        ]);
        final bySymbol = {for (final s in scores) s.symbol: s};
        expect(bySymbol['2330']!.modeScoreShort, 12);
        expect(bySymbol['2454']!.modeScoreShort, -8, reason: '純負分不得歸零');
        expect(bySymbol['2454']!.modeScoreLong, -12);
      });

      test('空 codes 清單 → 空結果(early return,不產生無效 SQL)', () async {
        await db.insertReasons([
          row('2330', 'VOLUME_SPIKE', short: 18, long: 5),
        ]);
        expect(await db.getModeStockScores(today, []), isEmpty);
      });

      test('同 symbol 同 type 多列(不同 rank)全數計入——記錄現行 SQL 語意', () async {
        // 寫入端理應每 (symbol, date, type) 一列;若哪天寫出重複列,
        // 這條 SQL 的行為是「加總」而非去重——症狀是分數膨脹。此測試
        // 把語意釘成文件,寫入端的唯一性由它自己的約束把關。
        await db.insertReasons([
          row('2330', 'VOLUME_SPIKE', short: 10, long: 1),
          row('2330', 'VOLUME_SPIKE', short: 10, long: 1, rank: 2),
        ]);
        final scores = await db.getModeStockScores(today, ['VOLUME_SPIKE']);
        expect(scores.single.modeScoreShort, 20);
      });
    });

    group('Reason operations', () {
      test('getReasons returns reasons sorted by rank', () async {
        await db.insertReasons([
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'VOLUME_SPIKE',
            evidenceJson: '{}',
            ruleScoreShort: const Value(18.0),
            ruleScoreLong: const Value(18.0),
            rank: 2,
          ),
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'PRICE_BREAKOUT',
            evidenceJson: '{}',
            ruleScoreShort: const Value(20.0),
            ruleScoreLong: const Value(20.0),
            rank: 1,
          ),
        ]);

        final reasons = await db.getReasons('2330', today);

        expect(reasons.length, 2);
        expect(reasons[0].reasonType, 'PRICE_BREAKOUT');
        expect(reasons[1].reasonType, 'VOLUME_SPIKE');
      });

      test('getReasonsBatch groups by symbol', () async {
        await db.insertReasons([
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'VOLUME_SPIKE',
            evidenceJson: '{}',
            ruleScoreShort: const Value(18.0),
            ruleScoreLong: const Value(18.0),
            rank: 1,
          ),
          DailyReasonCompanion.insert(
            symbol: '2317',
            date: today,
            reasonType: 'PRICE_BREAKOUT',
            evidenceJson: '{}',
            ruleScoreShort: const Value(20.0),
            ruleScoreLong: const Value(20.0),
            rank: 1,
          ),
        ]);

        final result = await db.getReasonsBatch(['2330', '2317'], today);

        expect(result['2330']?.length, 1);
        expect(result['2317']?.length, 1);
      });

      test('getReasonsBatch returns empty map for empty input', () async {
        final result = await db.getReasonsBatch([], today);

        expect(result, isEmpty);
      });

      test('replaceReasons atomically replaces', () async {
        await db.insertReasons([
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'OLD_REASON',
            evidenceJson: '{}',
            ruleScoreShort: const Value(10.0),
            ruleScoreLong: const Value(10.0),
            rank: 1,
          ),
        ]);

        await db.replaceReasons('2330', today, [
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'NEW_REASON_A',
            evidenceJson: '{"key": "value"}',
            ruleScoreShort: const Value(25.0),
            ruleScoreLong: const Value(25.0),
            rank: 1,
          ),
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'NEW_REASON_B',
            evidenceJson: '{}',
            ruleScoreShort: const Value(15.0),
            ruleScoreLong: const Value(15.0),
            rank: 2,
          ),
        ]);

        final reasons = await db.getReasons('2330', today);

        expect(reasons.length, 2);
        expect(reasons[0].reasonType, 'NEW_REASON_A');
        expect(reasons[1].reasonType, 'NEW_REASON_B');
      });

      test('replaceReasons with empty list clears reasons', () async {
        await db.insertReasons([
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'SOME_REASON',
            evidenceJson: '{}',
            ruleScoreShort: const Value(10.0),
            ruleScoreLong: const Value(10.0),
            rank: 1,
          ),
        ]);

        await db.replaceReasons('2330', today, []);

        final reasons = await db.getReasons('2330', today);
        expect(reasons, isEmpty);
      });

      test('clearReasonsForDate removes all reasons for a date', () async {
        await db.insertReasons([
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: today,
            reasonType: 'A',
            evidenceJson: '{}',
            ruleScoreShort: const Value(10.0),
            ruleScoreLong: const Value(10.0),
            rank: 1,
          ),
          DailyReasonCompanion.insert(
            symbol: '2317',
            date: today,
            reasonType: 'B',
            evidenceJson: '{}',
            ruleScoreShort: const Value(10.0),
            ruleScoreLong: const Value(10.0),
            rank: 1,
          ),
        ]);

        final deleted = await db.clearReasonsForDate(today);

        expect(deleted, 2);
      });
    });
  });
}
