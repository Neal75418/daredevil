import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/stock_detail_state.dart';

void main() {
  final defaultDate = DateTime(2026, 2, 13);

  // ==========================================
  // StockPriceState
  // ==========================================

  group('StockPriceState', () {
    test('default values', () {
      const state = StockPriceState();
      expect(state.stock, isNull);
      expect(state.latestPrice, isNull);
      expect(state.priceHistory, isEmpty);
      expect(state.analysis, isNull);
    });

    test('priceChange returns null when latestPrice is null', () {
      const state = StockPriceState();
      expect(state.priceChange, isNull);
    });

    test('priceChange delegates to PriceCalculator', () {
      final yesterday = DailyPriceEntry(
        symbol: '2330',
        date: defaultDate.subtract(const Duration(days: 1)),
        close: 500.0,
        volume: 10000,
      );
      final today = DailyPriceEntry(
        symbol: '2330',
        date: defaultDate,
        close: 550.0,
        volume: 20000,
      );
      final state = StockPriceState(
        latestPrice: today,
        priceHistory: [yesterday, today],
      );
      // (550-500)/500 * 100 = 10.0
      expect(state.priceChange, closeTo(10.0, 0.01));
    });
  });

  // ==========================================
  // FundamentalsState
  // ==========================================

  group('FundamentalsState', () {
    test('default values', () {
      const state = FundamentalsState();
      expect(state.revenueHistory, isEmpty);
      expect(state.dividendSummary, isNull);
      expect(state.latestPER, isNull);
      expect(state.latestQuarterMetrics, isEmpty);
      expect(state.epsHistory, isEmpty);
    });
  });

  // ==========================================
  // ChipAnalysisState
  // ==========================================

  group('ChipAnalysisState', () {
    test('default values', () {
      const state = ChipAnalysisState();
      expect(state.institutionalHistory, isEmpty);
      expect(state.marginTradingHistory, isEmpty);
      expect(state.dayTradingHistory, isEmpty);
      expect(state.shareholdingHistory, isEmpty);
      expect(state.holdingDistribution, isEmpty);
      expect(state.insiderHistory, isEmpty);
      expect(state.chipStrength, isNull);
    });
  });

  // ==========================================
  // LoadingState
  // ==========================================

  group('LoadingState', () {
    test('default values — all false', () {
      const state = LoadingState();
      expect(state.isLoading, isFalse);
      expect(state.isLoadingFundamentals, isFalse);
      expect(state.isLoadingInsider, isFalse);
      expect(state.isLoadingChip, isFalse);
    });
  });

  // ==========================================
  // StockDetailState
  // ==========================================

  group('StockDetailState', () {
    test('default values', () {
      const state = StockDetailState();
      expect(state.isInWatchlist, isFalse);
      expect(state.error, isNull);
      expect(state.dataDate, isNull);
      expect(state.hasDataMismatch, isFalse);
      expect(state.reasons, isEmpty);
      expect(state.aiSummary, isNull);
    });

    // Convenience getters
    test('priceChange delegates to price sub-state', () {
      const state = StockDetailState();
      expect(state.priceChange, isNull);
    });

    test('stockName returns stock name', () {
      final stock = StockMasterEntry(
        symbol: '2330',
        name: '台積電',
        market: 'TWSE',
        isActive: true,
        updatedAt: defaultDate,
      );
      final state = const StockDetailState().copyWith(stock: stock);
      expect(state.stockName, '台積電');
    });

    test('stockName returns null when stock is null', () {
      const state = StockDetailState();
      expect(state.stockName, isNull);
    });

    test('stockMarket returns market', () {
      final stock = StockMasterEntry(
        symbol: '2330',
        name: '台積電',
        market: 'TWSE',
        isActive: true,
        updatedAt: defaultDate,
      );
      final state = const StockDetailState().copyWith(stock: stock);
      expect(state.stockMarket, 'TWSE');
    });

    test('stockIndustry returns industry', () {
      final stock = StockMasterEntry(
        symbol: '2330',
        name: '台積電',
        market: 'TWSE',
        isActive: true,
        updatedAt: defaultDate,
        industry: '半導體業',
      );
      final state = const StockDetailState().copyWith(stock: stock);
      expect(state.stockIndustry, '半導體業');
    });

    test('latestClose returns close price', () {
      final price = DailyPriceEntry(
        symbol: '2330',
        date: defaultDate,
        close: 600.0,
        volume: 50000,
      );
      final state = const StockDetailState().copyWith(latestPrice: price);
      expect(state.latestClose, 600.0);
    });

    test('latestClose returns null when no latestPrice', () {
      const state = StockDetailState();
      expect(state.latestClose, isNull);
    });

    // sentinel pattern
    test('copyWith clears error with null', () {
      final state = const StockDetailState().copyWith(error: 'Some error');
      final cleared = state.copyWith(error: null);
      expect(cleared.error, isNull);
    });

    test('copyWith preserves error when not passed (sentinel)', () {
      final state = const StockDetailState().copyWith(error: 'Existing error');
      final updated = state.copyWith(isInWatchlist: true);
      expect(updated.error, 'Existing error');
    });

    // copyWith — sub-state skipping optimization
    test('copyWith skips price rebuild when no price fields changed', () {
      final stock = StockMasterEntry(
        symbol: '2330',
        name: '台積電',
        market: 'TWSE',
        isActive: true,
        updatedAt: defaultDate,
      );
      final state = const StockDetailState().copyWith(stock: stock);
      // Update only a direct field — price sub-state should be same reference
      final updated = state.copyWith(isInWatchlist: true);
      expect(identical(state.price, updated.price), isTrue);
    });

    test(
      'copyWith skips fundamentals rebuild when no fundamentals fields changed',
      () {
        final state = const StockDetailState().copyWith(
          latestQuarterMetrics: {'ROE': 25.0},
        );
        final updated = state.copyWith(isInWatchlist: true);
        expect(identical(state.fundamentals, updated.fundamentals), isTrue);
      },
    );

    test('copyWith skips chip rebuild when no chip fields changed', () {
      final state = const StockDetailState().copyWith(institutionalHistory: []);
      final updated = state.copyWith(isInWatchlist: true);
      expect(identical(state.chip, updated.chip), isTrue);
    });

    test('copyWith skips loading rebuild when no loading fields changed', () {
      final state = const StockDetailState().copyWith(isLoading: true);
      final updated = state.copyWith(isInWatchlist: true);
      expect(identical(state.loading, updated.loading), isTrue);
    });

    // Combined update across multiple sub-states
    test('copyWith updates multiple sub-states at once', () {
      final stock = StockMasterEntry(
        symbol: '2330',
        name: '台積電',
        market: 'TWSE',
        isActive: true,
        updatedAt: defaultDate,
      );
      final state = const StockDetailState().copyWith(
        stock: stock,
        latestQuarterMetrics: {'ROE': 25.0},
        institutionalHistory: [],
        isLoading: true,
        isInWatchlist: true,
        error: 'test',
      );
      expect(state.price.stock?.symbol, '2330');
      expect(state.fundamentals.latestQuarterMetrics['ROE'], 25.0);
      expect(state.chip.institutionalHistory, isEmpty);
      expect(state.loading.isLoading, isTrue);
      expect(state.isInWatchlist, isTrue);
      expect(state.error, 'test');
    });
  });
}
