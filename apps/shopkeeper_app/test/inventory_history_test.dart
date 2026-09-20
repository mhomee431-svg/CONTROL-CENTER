import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/widgets/inventory_shared.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';

/// Inventory History & Audit Trail.
///
/// The backend owns every fact in the trail: WHO acted (`actor`, resolved from
/// `movement.created_by` / `adjustment.approved_by` /
/// `price_history.changed_by`), WHAT changed (delta + before → after), WHY
/// (type + source), WHEN (`occurred_at`), and the net stock behind the summary
/// tile (`current_quantity` + `stock_status`).
///
/// These tests pin the client contract:
///   - an automated change is never attributed to a person, and
///   - the summary tile never invents a stock number the server did not send.
void main() {
  ProductHistoryResult result(Map<String, dynamic> json) =>
      ProductHistoryResult.fromJson(json);

  group('ProductHistoryEntry — who acted', () {
    test('resolves the actor name the server reported', () {
      final entry = ProductHistoryEntry.fromJson({
        'type': 'movement',
        'actor': 'Akash',
        'actor_id': 42,
      });
      expect(entry.actor, 'Akash');
      expect(entry.actorId, 42);
      expect(entry.actorLabel, 'By Akash');
    });

    test('a null actor is automated — never a guessed name', () {
      final entry = ProductHistoryEntry.fromJson({
        'type': 'movement',
        'actor': null,
        'actor_id': null,
      });
      expect(entry.actor, isNull);
      expect(entry.actorLabel, 'Automated');
    });

    test('a blank actor name is treated as automated', () {
      final entry =
          ProductHistoryEntry.fromJson({'type': 'movement', 'actor': '   '});
      expect(entry.actorLabel, 'Automated');
    });

    test('keeps the delta and before to after transition', () {
      final entry = ProductHistoryEntry.fromJson({
        'type': 'movement',
        'quantity_change': -10,
        'quantity_before': 60,
        'quantity_after': 50,
        'source': 'MANUAL',
        'actor': 'Akash',
      });
      expect(entry.stockDelta, -10);
      expect(entry.quantityBefore, 60);
      expect(entry.quantityAfter, 50);
      expect(entry.source, 'MANUAL');
    });
  });

  group('ProductHistoryResult — pagination', () {
    test('reads total / offset / limit / has_more from the server', () {
      final r = result({
        'shop_product_id': 7,
        'count': 2,
        'total': 5,
        'offset': 0,
        'limit': 2,
        'has_more': true,
        'entries': [
          {'type': 'movement'},
          {'type': 'adjustment'},
        ],
      });
      expect(r.total, 5);
      expect(r.offset, 0);
      expect(r.limit, 2);
      expect(r.hasMore, isTrue);
      expect(r.count, 2);
    });

    test('derives has_more for an older payload without the flag', () {
      final r = result({
        'shop_product_id': 7,
        'total': 5,
        'offset': 4,
        'entries': [
          {'type': 'movement'},
        ],
      });
      expect(r.hasMore, isFalse);
    });

    test('defaults offset to 0 and limit to the page size', () {
      final r = result({
        'shop_product_id': 7,
        'entries': [
          {'type': 'movement'},
        ],
      });
      expect(r.offset, 0);
      expect(r.limit, 1);
      expect(r.hasMore, isFalse);
    });
  });

  group('ProductHistoryResult — summary tile data', () {
    test('reads the current stock and server stock state', () {
      final r = result({
        'shop_product_id': 7,
        'current_quantity': 25,
        'stock_status': 'IN_STOCK',
        'entries': const [],
      });
      expect(r.currentQuantity, 25);
      expect(r.stockStatus, 'IN_STOCK');
    });

    test('currentQuantity is null when the server did not send it', () {
      final r = result({'shop_product_id': 7, 'entries': const []});
      expect(r.currentQuantity, isNull);
      expect(r.stockStatus, isNull);
    });
  });

  group('StockHistorySummary tile', () {
    testWidgets('shows the server stock, state and trail size',
        (tester) async {
      final r = result({
        'shop_product_id': 7,
        'current_quantity': 25,
        'stock_status': 'IN_STOCK',
        'total': 3,
        'entries': const [],
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StockHistorySummary(history: r)),
      ));
      expect(find.text('Current stock'), findsOneWidget);
      expect(find.text('25 units · In stock'), findsOneWidget);
      expect(find.text('3 entries'), findsOneWidget);
    });

    testWidgets('renders nothing when current_quantity is missing',
        (tester) async {
      final r = result({'shop_product_id': 7, 'entries': const []});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StockHistorySummary(history: r)),
      ));
      expect(find.text('Current stock'), findsNothing);
    });

    testWidgets('singularises a one-entry trail', (tester) async {
      final r = result({
        'shop_product_id': 7,
        'current_quantity': 0,
        'stock_status': 'OUT_OF_STOCK',
        'total': 1,
        'entries': const [],
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StockHistorySummary(history: r)),
      ));
      expect(find.text('0 units · Out of stock'), findsOneWidget);
      expect(find.text('1 entry'), findsOneWidget);
    });

    testWidgets('falls back to the page size when total is absent',
        (tester) async {
      final r = result({
        'shop_product_id': 7,
        'current_quantity': 4,
        'stock_status': 'LOW_STOCK',
        'entries': [
          {'type': 'movement'},
          {'type': 'movement'},
        ],
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StockHistorySummary(history: r)),
      ));
      expect(find.text('4 units · Low stock'), findsOneWidget);
      expect(find.text('2 entries'), findsOneWidget);
    });
  });
}