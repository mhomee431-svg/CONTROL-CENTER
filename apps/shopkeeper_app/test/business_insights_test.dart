import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/domain/insights_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/presentation/screens/insights_screen.dart';

import 'fakes.dart';

/// Business insights contract — REAL DATA ONLY.
///
/// Pure-model pins (no widgets, no network) for the six live insight cards the
/// backend computes for a shop: top products, low stock, stale inventory,
/// product search visibility, offers performance and profile completeness.
///
/// Rule (same as the analytics contract): an absent / unknown payload parses to
/// an empty model, and the UI renders only the cards that actually carry
/// something — never an invented number and never a wall of zeroes.
void main() {
  Map<String, dynamic> card({
    required String id,
    String status = 'info',
    Map<String, dynamic> metrics = const <String, dynamic>{},
    List<Map<String, dynamic>> items = const <Map<String, dynamic>>[],
    String? suggestion,
  }) => <String, dynamic>{
    'id': id,
    'title': id,
    'description': 'description',
    'status': status,
    'metrics': metrics,
    'items': items,
    'suggestion': suggestion,
  };

  group('BusinessInsightsBundle real-data rules', () {
    test('an empty payload parses to no cards and no shop', () {
      final bundle = BusinessInsightsBundle.fromJson(const <String, dynamic>{});

      expect(bundle.insights, isEmpty);
      expect(bundle.isEmpty, isTrue);
      expect(bundle.actionable, isEmpty);
      expect(bundle.shopName, '');
      expect(bundle.generatedAt, isNull);
      expect(bundle.byId('low_stock'), isNull);
    });

    test('an unknown status degrades to info instead of throwing', () {
      final bundle = BusinessInsightsBundle.fromJson(<String, dynamic>{
        'shop': <String, dynamic>{'id': 10, 'name': 'Kirana Corner'},
        'generated_at': '2026-01-01T00:00:00+00:00',
        'insights': <Map<String, dynamic>>[
          card(id: 'low_stock', status: 'who_knows'),
        ],
      });

      expect(bundle.byId('low_stock')!.status, BusinessInsightStatus.info);
      expect(BusinessInsightStatus.fromName(null), BusinessInsightStatus.info);
      expect(bundle.shopName, 'Kirana Corner');
      expect(bundle.generatedAt, isNotNull);
    });

    test('cards with nothing to report are skipped, flagged ones are kept', () {
      final bundle = BusinessInsightsBundle.fromJson(<String, dynamic>{
        'insights': <Map<String, dynamic>>[
          card(
            id: 'low_stock',
            status: 'healthy',
            metrics: <String, dynamic>{'count': 0, 'total_products': 4},
          ),
          card(
            id: 'stale_inventory',
            status: 'warning',
            metrics: <String, dynamic>{'count': 2, 'oldest_stale_days': 51},
            items: <Map<String, dynamic>>[
              <String, dynamic>{
                'shop_product_id': 7,
                'name': 'Old Atta',
                'days_since_update': 51,
              },
            ],
            suggestion: 'Update stock counts.',
          ),
          card(
            id: 'profile_completeness',
            status: 'critical',
            metrics: <String, dynamic>{
              'completeness_percentage': 16.7,
              'completed_fields': 2,
              'total_fields': 12,
            },
          ),
        ],
      });

      expect(bundle.insights.length, 3);
      expect(bundle.byId('low_stock')!.hasData, isFalse);
      expect(bundle.actionable.map((c) => c.id), <String>[
        'stale_inventory',
        'profile_completeness',
      ]);
    });
  });

  group('BusinessInsightCard fields', () {
    test('reads the backend metrics verbatim (no client-side invention)', () {
      final card = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'search_visibility',
        'title': 'Product Search Visibility',
        'status': 'healthy',
        'metrics': <String, dynamic>{
          'total_products': 5,
          'visible_products': 4,
          'visibility_percentage': 80.0,
          'products_without_images': 1,
        },
      });

      expect(card.metricInt('total_products'), 5);
      expect(card.metricDouble('visibility_percentage'), 80.0);
      expect(card.headline, '80% of listings visible in search');
      expect(card.summaryLines.single, '4 of 5 visible · 1 without an image');
    });

    test('numeric strings are tolerated; missing metrics read as zero', () {
      final card = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'low_stock',
        'title': 'Low Stock Alert',
        'metrics': <String, dynamic>{'count': '3'},
      });

      expect(card.metricInt('count'), 3);
      expect(card.metricInt('missing_key'), 0);
      expect(card.metricDouble('missing_key'), 0);
      expect(card.headline, '3 at or below threshold');
    });

    test('an empty catalog never renders a percentage headline', () {
      final card = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'search_visibility',
        'title': 'Product Search Visibility',
        'metrics': <String, dynamic>{'total_products': 0},
      });

      expect(card.headline, isNull);
      expect(card.summaryLines, isNotEmpty);
      expect(card.itemLines, isEmpty);
    });

    test('flagged rows are summarised with their card-specific detail', () {
      final stale = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'stale_inventory',
        'title': 'Stale Inventory',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Rice 1kg', 'days_since_update': 45},
        ],
      });
      final offers = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'offers_performance',
        'title': 'Offers Performance',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'title': 'Diwali Sale', 'product_count': 4},
        ],
      });
      final profile = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'profile_completeness',
        'title': 'Profile Completeness',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'field': 'phone', 'label': 'Phone number'},
        ],
      });
      final top = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'top_products',
        'title': 'Top Products',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Rice 1kg', 'quantity': 50},
        ],
      });

      expect(stale.itemLines.single, 'Rice 1kg · 45 days untouched');
      expect(offers.itemLines.single, 'Diwali Sale · 4 products');
      expect(profile.itemLines.single, 'Phone number');
      expect(top.itemLines.single, 'Rice 1kg · 50 units in stock');
    });

    test('item lines are capped at five and skip blank rows', () {
      final card = BusinessInsightCard.fromJson(<String, dynamic>{
        'id': 'low_stock',
        'title': 'Low Stock Alert',
        'items': <Map<String, dynamic>>[
          for (var i = 0; i < 9; i++)
            <String, dynamic>{'name': 'Item $i', 'quantity': i, 'gap': 10 - i},
          <String, dynamic>{},
        ],
      });

      expect(card.itemLines.length, 5);
      expect(card.itemLines.first, 'Item 0 · 0 left, restock 10');
    });

    test('a healthy card without items or suggestion is not actionable', () {
      final healthy = BusinessInsightCard.fromJson(
        card(id: 'top_products', status: 'healthy'),
      );
      final withSuggestion = BusinessInsightCard.fromJson(
        card(
          id: 'offers_performance',
          status: 'info',
          suggestion: 'You have no active offers.',
        ),
      );

      expect(healthy.hasData, isFalse);
      expect(withSuggestion.hasData, isTrue);
    });
  });

  group('InsightsScreen — business-insights section (widget)', () {
    Widget wrap(FakeInsightsRepo repo) => ProviderScope(
      overrides: [
        insightsRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        selectedShopProvider.overrideWith(
          () => SelectedShopOverride(ownerShop(id: 10)),
        ),
      ],
      child: const MaterialApp(home: InsightsScreen()),
    );

    /// Brings a section into view — the report is taller than the viewport and
    /// the insight cards sit at the end of it (`ListView` builds lazily).
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }

    BusinessInsightsBundle bundleWith(List<Map<String, dynamic>> cards) =>
        BusinessInsightsBundle.fromJson(<String, dynamic>{
          'shop': <String, dynamic>{'id': 10, 'name': 'Kirana Corner'},
          'insights': cards,
        });

    testWidgets('renders only the cards that carry something', (tester) async {
      final repo = FakeInsightsRepo(
        businessInsights: bundleWith(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'low_stock',
            'title': 'Low Stock Alert',
            'description': 'Products at or below their low-stock threshold.',
            'status': 'warning',
            'metrics': <String, dynamic>{
              'count': 2,
              'percentage': 40.0,
              'total_gap_units': 11,
            },
            'items': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'Sugar 1kg', 'quantity': 3, 'gap': 7},
            ],
            'suggestion': 'Restock the items above.',
          },
          <String, dynamic>{
            // Healthy with nothing flagged: must NOT be rendered.
            'id': 'top_products',
            'title': 'Top Products',
            'status': 'healthy',
            'metrics': <String, dynamic>{'total_products': 5},
          },
          <String, dynamic>{
            'id': 'profile_completeness',
            'title': 'Profile Completeness',
            'status': 'critical',
            'metrics': <String, dynamic>{
              'completeness_percentage': 16.7,
              'completed_fields': 2,
              'total_fields': 12,
            },
          },
        ]),
      );

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Sugar 1kg · 3 left, restock 7'));

      expect(find.text('Business insights'), findsOneWidget);
      expect(find.text('Low Stock Alert'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('2 at or below threshold'), findsOneWidget);
      expect(find.text('Sugar 1kg · 3 left, restock 7'), findsOneWidget);
      expect(find.text('Restock the items above.'), findsOneWidget);
      // The quiet card is skipped, not rendered as a row of zeroes.
      expect(find.text('Top Products'), findsNothing);
      expect(repo.businessInsightsCalls, 1);

      await scrollTo(tester, find.text('Profile Completeness'));
      expect(find.text('Profile Completeness'), findsOneWidget);
      expect(find.text('16.7% complete (2/12 fields)'), findsOneWidget);
    });

    testWidgets('hides the section when the backend sends no insight cards', (
      tester,
    ) async {
      final repo = FakeInsightsRepo(); // empty bundle by default

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      // The analytics report itself is untouched…
      expect(find.textContaining('Customer activity'), findsOneWidget);

      // …and scrolling to the end of the report proves the section is absent
      // (not merely off-screen).
      await scrollTo(tester, find.textContaining('All metrics are computed'));
      expect(find.text('Business insights'), findsNothing);
      expect(find.text('All clear'), findsNothing);
    });

    testWidgets('a failed sub-call reports the failure, never an empty shop', (
      tester,
    ) async {
      final repo = FakeInsightsRepo()
        ..businessInsightsError = Exception('insights boom');

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      // The analytics report still renders…
      expect(find.textContaining('Customer activity'), findsOneWidget);

      // …and the section says why the cards are missing.
      await scrollTo(tester, find.text('Insights unavailable'));
      expect(find.text('Insights unavailable'), findsOneWidget);
      expect(find.text('Refresh to try again.'), findsOneWidget);
    });
  });
}