// Pagination — backend-paged lists deliver one bounded page per request.
//
// Every large list in the app must NOT load everything at once. This suite proves
// that the five SERVER-paged screens — Notifications, Import History, Support
// Tickets and the two audit trails (stock history + price history) — page through
// the backend with `limit` / `offset`, surface a "Load more" footer, and never
// ask for a page they already hold.
//
// The products list is deliberately NOT here: it pages in MEMORY (the whole
// catalog arrives in one `view=list` response and `productsPageSize` reveals a
// render window at a time), which `product_state_test.dart` covers.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/stock_history_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/domain/import_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/presentation/screens/import_history_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/domain/notification_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/screens/price_history_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/data/support_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/domain/support_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/domain/support_ticket.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/presentation/screens/my_tickets_screen.dart';

import 'fakes.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const int kPagedRows = 45;
const int kTrailRows = 55;

/// The failure a paged request reports when the network drops mid-list.
const _offline = ApiException(
  message: 'No internet connection. Check your network and retry.',
);

// ── Fixtures ────────────────────────────────────────────────────────────────

ShopkeeperNotification _mkNotif({
  required int id,
  bool isRead = false,
}) =>
    ShopkeeperNotification(
      id: id,
      title: 'Alert $id',
      body: 'Body $id',
      type: id.isEven ? 'PRICE_UPDATE' : 'INVENTORY_LOW',
      isRead: isRead,
      createdAt: DateTime(2026, 9, 10, 8).add(Duration(hours: id)),
      deepLink: null,
      payload: null,
    );

ImportJob _mkJob({
  required int id,
}) =>
    ImportJob(
      id: id,
      filename: 'batch-$id.xlsx',
      status: ImportJobStatusValue.completed,
      totalRows: 10,
      validRows: 10,
      errorRows: 0,
      createdAt: DateTime(2026, 9, 18, 21, 19).add(Duration(hours: id)),
    );

ProductHistoryEntry _mkTrailEntry({required int seq}) => ProductHistoryEntry(
      type: seq.isEven ? 'price_change' : 'movement',
      occurredAt: DateTime(2026, 9, 10, 8).add(Duration(hours: seq)),
      changeSource:
          seq.isEven ? 'PRICE_LIST' : 'MANUAL_STOCK_ADJUSTMENT',
      quantityChange: seq.isEven ? null : seq,
      quantityBefore: seq.isEven ? null : seq,
      quantityAfter: seq.isEven ? null : seq * 2,
      movementType: seq.isEven ? null : 'MANUAL',
      oldPrice: seq.isEven ? 100.0 + seq : null,
      newPrice: seq.isEven ? 120.0 + seq : null,
      oldMrp: seq.isEven ? 150.0 + seq : null,
      newMrp: seq.isEven ? 160.0 + seq : null,
      actor: 'Admin',
    );

ShopProductItem _mkProduct({required int id}) => ShopProductItem(
      id: id,
      name: 'Product $id',
      status: 'ACTIVE',
      price: 100.0,
      mrp: 120.0,
      isActive: true,
      isAvailable: true,
      quantity: 50,
      stockStatus: 'IN_STOCK',
      freshnessStatus: 'FRESH',
      lastUpdated: DateTime(2026, 9, 10),
      source: 'EXCEL_UPLOAD',
      updatedBy: 'Admin',
      lowStockThreshold: 10,
    );

SupportTicket _mkTicket({
  required int id,
  required String status,
  required String statusLabel,
}) =>
    SupportTicket(
      id: id,
      reference: 'HL-$id',
      subject: 'Issue $id',
      description: 'Description for issue $id',
      category: 'APP_PRODUCTS',
      statusCode: status,
      statusLabel: statusLabel,
      createdAt: DateTime(2026, 9, 10, 8).add(Duration(hours: id)),
      shopName: 'Test Shop',
      resolutionNotes: null,
      priority: 'MEDIUM',
      categoryLabel: 'Products & catalogue',
    );

// ── Fake repos with paging support ──────────────────────────────────────────

class PagedNotificationsRepo implements NotificationsRepository {
  PagedNotificationsRepo(this.allItems);

  final List<ShopkeeperNotification> allItems;
  final List<int> requestedOffsets = [];

  /// When set, every request starting at or beyond this offset fails — the way
  /// a dropped connection behaves mid-list.
  int? failFromOffset;

  @override
  Future<NotificationsPage> fetchNotifications(
    int shopId,
    String token, {
    int limit = notificationsPageSize,
    int offset = 0,
  }) async {
    requestedOffsets.add(offset);
    final failAt = failFromOffset;
    if (failAt != null && offset >= failAt) throw _offline;
    final start = offset.clamp(0, allItems.length);
    final end = (offset + limit).clamp(0, allItems.length);
    return NotificationsPage(
      items: allItems.sublist(start, end),
      unreadCount: allItems.where((n) => n.isUnread).length,
      total: allItems.length,
    );
  }

  @override
  Future<void> markAsRead(int notificationId, String token) async {}

  @override
  Future<void> markAllAsRead(String token) async {}
}

class PagedImportRepo implements InventoryImportRepository {
  PagedImportRepo(this.allJobs);

  final List<ImportJob> allJobs;
  final List<int> requestedOffsets = [];

  /// When set, every request starting at or beyond this offset fails.
  int? failFromOffset;

  @override
  Future<ImportPreview> upload(
    int shopId,
    PickedWorkbook workbook,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<ImportPreview> preview(int shopId, int jobId, String token) =>
      throw UnimplementedError();

  @override
  Future<ImportConfirmResult> confirm(
    int shopId,
    int jobId,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<ImportJobPage> listJobs(
    int shopId,
    String token, {
    int limit = importJobsPageSize,
    int offset = 0,
  }) async {
    requestedOffsets.add(offset);
    final failAt = failFromOffset;
    if (failAt != null && offset >= failAt) throw _offline;
    final start = offset.clamp(0, allJobs.length);
    final end = (offset + limit).clamp(0, allJobs.length);
    return ImportJobPage(
      jobs: allJobs.sublist(start, end),
      total: allJobs.length,
    );
  }

  @override
  Future<Uint8List> downloadSample(int shopId, String token) =>
      throw UnimplementedError();
}

class PagedProductRepo implements ProductRepository, InventoryRepository {
  PagedProductRepo({
    this.products = const [],
    required this.historyFixture,
  });

  final List<ShopProductItem> products;
  final List<ProductHistoryEntry> historyFixture;
  final List<int> requestedHistoryOffsets = [];

  /// When set, every trail request starting at or beyond this offset fails.
  int? failFromOffset;

  @override
  Future<ShopProductItem> createProduct(
    int shopId,
    Map<String, dynamic> payload,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<ShopProductItem> updateProduct(
    int shopId,
    int productId,
    Map<String, dynamic> fields,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<InventoryOverview> fetchInventoryOverview(
    int shopId,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<StockAdjustmentResult> adjustStock(
    int shopId,
    int productId,
    Map<String, dynamic> payload,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<ProductHistoryResult> fetchProductHistory(
    int shopId,
    int productId,
    String token, {
    int limit = productHistoryPageSize,
    int offset = 0,
  }) async {
    requestedHistoryOffsets.add(offset);
    final failAt = failFromOffset;
    if (failAt != null && offset >= failAt) throw _offline;
    final start = offset.clamp(0, historyFixture.length);
    final end = (offset + limit).clamp(0, historyFixture.length);
    return ProductHistoryResult(
      shopProductId: productId,
      entries: historyFixture.sublist(start, end),
      total: historyFixture.length,
      offset: offset,
      limit: limit,
      hasMore: end < historyFixture.length,
    );
  }

  @override
  Future<LowStockThresholdResult> updateLowStockThreshold(
    int shopId,
    int productId,
    int threshold,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<StockAdjustmentHistory> fetchStockAdjustments(
    int shopId,
    int productId,
    String token,
  ) =>
      throw UnimplementedError();

  @override
  Future<void> clearOfflineSnapshot() async {}
}

class PagedSupportRepo implements SupportRepository {
  PagedSupportRepo(this.allTickets);

  final List<SupportTicket> allTickets;
  final List<int> requestedOffsets = [];

  /// When set, every request starting at or beyond this offset fails.
  int? failFromOffset;

  @override
  Future<SupportTicket> createTicket({
    required String token,
    required IssueCategory category,
    required IssueSeverity severity,
    required String description,
    String? steps,
    String? appVersion,
    int? shopId,
    String? attachmentKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> uploadAttachment({
    required String token,
    required String filename,
    required String contentType,
    required Uint8List bytes,
  }) =>
      throw UnimplementedError();

  @override
  Future<SupportTicketsPage> fetchTickets(
    String token, {
    int limit = supportTicketsPageSize,
    int offset = 0,
  }) async {
    requestedOffsets.add(offset);
    final failAt = failFromOffset;
    if (failAt != null && offset >= failAt) throw _offline;
    final start = offset.clamp(0, allTickets.length);
    final end = (offset + limit).clamp(0, allTickets.length);
    return SupportTicketsPage(
      tickets: allTickets.sublist(start, end),
      total: allTickets.length,
    );
  }

  @override
  Future<SupportTicket> fetchTicket(int ticketId, String token) =>
      throw UnimplementedError();
}

// ── Test helpers ─────────────────────────────────────────────────────────────

ProviderContainer makeNotificationsContainer({
  required PagedNotificationsRepo repo,
}) {
  return ProviderContainer(
    overrides: [
      notificationsRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
}

ProviderContainer makeImportContainer({
  required PagedImportRepo repo,
}) {
  return ProviderContainer(
    overrides: [
      inventoryImportRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
}

ProviderContainer makeHistoryContainer({
  required PagedProductRepo repo,
}) {
  return ProviderContainer(
    overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
}

ProviderContainer makeSupportContainer({
  required PagedSupportRepo repo,
}) {
  return ProviderContainer(
    overrides: [
      supportRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
}

Future<void> pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

/// The scrollable the rows live in.
///
/// The LAST one in the tree: some screens put a horizontal filter bar above the
/// list, and that bar is a scrollable too — paging must always drive the list.
Finder rowsScrollable() => find.byType(Scrollable).last;

/// Scrolls the row list until [finder] is mounted AND on screen.
///
/// The rows are built lazily, so a footer (or the last row) only exists in the
/// widget tree once the list has been scrolled to it.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 400, scrollable: rowsScrollable());
  await tester.pumpAndSettle();
}

/// Drags the row list to its very end.
///
/// Used to prove a footer is ABSENT: without scrolling, a lazily-built footer
/// would not be in the tree either way and the assertion would prove nothing.
Future<void> dragToEnd(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.drag(rowsScrollable(), const Offset(0, -800));
    await tester.pumpAndSettle();
  }
}

/// Taps the page footer and lets the follow-up page settle.
Future<void> tapLoadMore(WidgetTester tester, String key) async {
  await reveal(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

// ── Main test groups ─────────────────────────────────────────────────────────

void main() {
  // ── Notifications ──────────────────────────────────────────────────────────
  group('Notifications pagination', () {
    testWidgets('pages through all server rows', (tester) async {
      final repo = PagedNotificationsRepo(
        List.generate(kPagedRows, (i) => _mkNotif(id: i + 1)),
      );
      final container = makeNotificationsContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const NotificationsScreen());

      // First page only — one bounded request.
      expect(find.text('Alert 1'), findsOneWidget);
      expect(repo.requestedOffsets, [0]);

      // The footer reports the rows the server still holds.
      await reveal(tester, find.byKey(const Key('notifications-load-more')));
      expect(
        find.text('Load more (${kPagedRows - notificationsPageSize} remaining)'),
        findsOneWidget,
      );

      // First tap: the SECOND page starts exactly where the first ended.
      await tapLoadMore(tester, 'notifications-load-more');
      expect(repo.requestedOffsets, [0, notificationsPageSize]);
      await reveal(tester, find.byKey(const Key('notifications-load-more')));
      expect(
        find.text(
          'Load more (${kPagedRows - notificationsPageSize * 2} remaining)',
        ),
        findsOneWidget,
      );

      // Second tap: the rest arrives and the footer retires.
      await tapLoadMore(tester, 'notifications-load-more');
      expect(
        repo.requestedOffsets,
        [0, notificationsPageSize, notificationsPageSize * 2],
      );
      expect(
        find.byKey(const Key('notifications-load-more')),
        findsNothing,
      );
      await reveal(tester, find.text('Alert $kPagedRows'));
      expect(find.text('Alert $kPagedRows'), findsOneWidget);
    });

    testWidgets('shows remaining count after first page', (tester) async {
      final repo = PagedNotificationsRepo(
        List.generate(kPagedRows, (i) => _mkNotif(id: i + 1)),
      );
      final container = makeNotificationsContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const NotificationsScreen());
      await reveal(tester, find.byKey(const Key('notifications-load-more')));

      expect(
        find.text('Load more (${kPagedRows - notificationsPageSize} remaining)'),
        findsOneWidget,
      );
    });

    testWidgets('hides footer when all rows are loaded', (tester) async {
      final repo = PagedNotificationsRepo(
        List.generate(notificationsPageSize, (i) => _mkNotif(id: i + 1)),
      );
      final container = makeNotificationsContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const NotificationsScreen());
      await dragToEnd(tester);

      expect(
        find.byKey(const Key('notifications-load-more')),
        findsNothing,
      );
    });

    testWidgets('a failed page keeps the loaded rows and says why', (
      tester,
    ) async {
      final repo = PagedNotificationsRepo(
        List.generate(kPagedRows, (i) => _mkNotif(id: i + 1)),
      )..failFromOffset = notificationsPageSize;
      final container = makeNotificationsContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const NotificationsScreen());
      await tapLoadMore(tester, 'notifications-load-more');

      // The page never arrived — but nothing already fetched was dropped, and
      // the reason is on screen instead of a silently shorter list.
      expect(repo.requestedOffsets, [0, notificationsPageSize]);
      expect(find.text('Alert $notificationsPageSize'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('notifications-page-error')));
      expect(find.text(_offline.message), findsOneWidget);
      // The footer stays: those rows are still behind the server's page break.
      expect(
        find.byKey(const Key('notifications-load-more')),
        findsOneWidget,
      );
    });
  });

  // ── Import History ─────────────────────────────────────────────────────────
  group('Import History pagination', () {
    testWidgets('pages through all server rows', (tester) async {
      final repo = PagedImportRepo(
        List.generate(kPagedRows, (i) => _mkJob(id: i + 1)),
      );
      final container = makeImportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ImportHistoryScreen());

      // First page only — one bounded request.
      expect(find.text('batch-1.xlsx'), findsOneWidget);
      expect(repo.requestedOffsets, [0]);

      await reveal(tester, find.byKey(const Key('import-history-load-more')));
      expect(
        find.text('Load more (${kPagedRows - importJobsPageSize} remaining)'),
        findsOneWidget,
      );

      // First tap, then the remainder — the offset advances by one page each
      // time instead of re-fetching what is already on screen.
      await tapLoadMore(tester, 'import-history-load-more');
      expect(repo.requestedOffsets, [0, importJobsPageSize]);
      await tapLoadMore(tester, 'import-history-load-more');
      expect(
        repo.requestedOffsets,
        [0, importJobsPageSize, importJobsPageSize * 2],
      );
      expect(
        find.byKey(const Key('import-history-load-more')),
        findsNothing,
      );
      await reveal(tester, find.text('batch-$kPagedRows.xlsx'));
      expect(find.text('batch-$kPagedRows.xlsx'), findsOneWidget);
    });

    testWidgets('shows remaining count after first page', (tester) async {
      final repo = PagedImportRepo(
        List.generate(kPagedRows, (i) => _mkJob(id: i + 1)),
      );
      final container = makeImportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ImportHistoryScreen());
      await reveal(tester, find.byKey(const Key('import-history-load-more')));

      expect(
        find.text('Load more (${kPagedRows - importJobsPageSize} remaining)'),
        findsOneWidget,
      );
    });

    testWidgets('hides footer when all rows are loaded', (tester) async {
      final repo = PagedImportRepo(
        List.generate(importJobsPageSize, (i) => _mkJob(id: i + 1)),
      );
      final container = makeImportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ImportHistoryScreen());
      await dragToEnd(tester);

      expect(
        find.byKey(const Key('import-history-load-more')),
        findsNothing,
      );
    });

    testWidgets('a failed page keeps the loaded rows', (tester) async {
      final repo = PagedImportRepo(
        List.generate(kPagedRows, (i) => _mkJob(id: i + 1)),
      )..failFromOffset = importJobsPageSize;
      final container = makeImportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const ImportHistoryScreen());
      await tapLoadMore(tester, 'import-history-load-more');

      // The follow-up failed, so the jobs already fetched stay on screen and
      // the footer stays reachable for a retry.
      expect(repo.requestedOffsets, [0, importJobsPageSize]);
      expect(find.text('batch-$importJobsPageSize.xlsx'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('import-history-load-more')));
      expect(
        find.byKey(const Key('import-history-load-more')),
        findsOneWidget,
      );
    });
  });

  // ── Support Tickets ────────────────────────────────────────────────────────
  group('Support tickets pagination', () {
    testWidgets('pages through all server rows', (tester) async {
      final repo = PagedSupportRepo(
        List.generate(
          kPagedRows,
          (i) => _mkTicket(
            id: i + 1,
            status: TicketStatus.open.code,
            statusLabel: 'Submitted',
          ),
        ),
      );
      final container = makeSupportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const MyTicketsScreen());

      // First page only — one bounded request.
      expect(find.text('HL-1'), findsOneWidget);
      expect(repo.requestedOffsets, [0]);

      await reveal(tester, find.byKey(const Key('tickets-load-more')));
      expect(
        find.text(
          'Load more (${kPagedRows - supportTicketsPageSize} remaining)',
        ),
        findsOneWidget,
      );

      await tapLoadMore(tester, 'tickets-load-more');
      expect(repo.requestedOffsets, [0, supportTicketsPageSize]);
      await tapLoadMore(tester, 'tickets-load-more');
      expect(
        repo.requestedOffsets,
        [0, supportTicketsPageSize, supportTicketsPageSize * 2],
      );
      expect(find.byKey(const Key('tickets-load-more')), findsNothing);
      await reveal(tester, find.text('HL-$kPagedRows'));
      expect(find.text('HL-$kPagedRows'), findsOneWidget);
    });

    testWidgets('shows remaining count after first page', (tester) async {
      final repo = PagedSupportRepo(
        List.generate(
          kPagedRows,
          (i) => _mkTicket(
            id: i + 1,
            status: TicketStatus.open.code,
            statusLabel: 'Submitted',
          ),
        ),
      );
      final container = makeSupportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const MyTicketsScreen());
      await reveal(tester, find.byKey(const Key('tickets-load-more')));

      expect(
        find.text(
          'Load more (${kPagedRows - supportTicketsPageSize} remaining)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hides footer when all rows are loaded', (tester) async {
      final repo = PagedSupportRepo(
        List.generate(
          supportTicketsPageSize,
          (i) => _mkTicket(
            id: i + 1,
            status: TicketStatus.resolved.code,
            statusLabel: 'Resolved',
          ),
        ),
      );
      final container = makeSupportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const MyTicketsScreen());
      await dragToEnd(tester);

      expect(find.byKey(const Key('tickets-load-more')), findsNothing);
    });

    testWidgets('a failed page keeps the loaded rows and says why', (
      tester,
    ) async {
      final repo = PagedSupportRepo(
        List.generate(
          kPagedRows,
          (i) => _mkTicket(
            id: i + 1,
            status: TicketStatus.open.code,
            statusLabel: 'Submitted',
          ),
        ),
      )..failFromOffset = supportTicketsPageSize;
      final container = makeSupportContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(tester, container, const MyTicketsScreen());
      await tapLoadMore(tester, 'tickets-load-more');

      expect(repo.requestedOffsets, [0, supportTicketsPageSize]);
      expect(find.text('HL-$supportTicketsPageSize'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('tickets-page-error')));
      expect(find.text(_offline.message), findsOneWidget);
      expect(find.byKey(const Key('tickets-load-more')), findsOneWidget);
    });
  });

  // ── Product History ────────────────────────────────────────────────────────
  group('Stock history pagination', () {
    testWidgets('pages through the audit trail', (tester) async {
      final repo = PagedProductRepo(
        historyFixture: List.generate(
          kTrailRows,
          (i) => _mkTrailEntry(seq: i + 1),
        ),
      );
      final container = makeHistoryContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        StockHistoryScreen(product: _mkProduct(id: 1)),
      );

      // Only the first page was requested.
      expect(repo.requestedHistoryOffsets, [0]);

      await reveal(tester, find.byKey(const Key('stock-history-load-more')));
      expect(
        find.text('Load more (${kTrailRows - productHistoryPageSize} remaining)'),
        findsOneWidget,
      );

      await tapLoadMore(tester, 'stock-history-load-more');

      // The follow-up started exactly where the first page ended.
      expect(repo.requestedHistoryOffsets, [0, productHistoryPageSize]);
      expect(
        find.byKey(const Key('stock-history-load-more')),
        findsNothing,
      );
    });

    testWidgets('hides footer when the trail fits one page', (tester) async {
      final repo = PagedProductRepo(
        historyFixture: List.generate(
          productHistoryPageSize,
          (i) => _mkTrailEntry(seq: i + 1),
        ),
      );
      final container = makeHistoryContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        StockHistoryScreen(product: _mkProduct(id: 1)),
      );
      await dragToEnd(tester);

      expect(
        find.byKey(const Key('stock-history-load-more')),
        findsNothing,
      );
    });

    testWidgets('a failed page keeps the trail and says why', (tester) async {
      final repo = PagedProductRepo(
        historyFixture: List.generate(
          kTrailRows,
          (i) => _mkTrailEntry(seq: i + 1),
        ),
      )..failFromOffset = productHistoryPageSize;
      final container = makeHistoryContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        StockHistoryScreen(product: _mkProduct(id: 1)),
      );
      await tapLoadMore(tester, 'stock-history-load-more');

      // The follow-up page failed: the entries already fetched stay, and the
      // footer reports why instead of vanishing.
      expect(repo.requestedHistoryOffsets, [0, productHistoryPageSize]);
      await reveal(tester, find.byKey(const Key('stock-history-page-error')));
      expect(find.text(_offline.message), findsOneWidget);
      expect(
        find.byKey(const Key('stock-history-load-more')),
        findsOneWidget,
      );
    });
  });

  group('Price history pagination', () {
    testWidgets('pages through the whole audit trail', (tester) async {
      final repo = PagedProductRepo(
        historyFixture: List.generate(
          kTrailRows,
          (i) => _mkTrailEntry(seq: i + 1),
        ),
      );
      final container = makeHistoryContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        PriceHistoryScreen(product: _mkProduct(id: 1)),
      );

      expect(repo.requestedHistoryOffsets, [0]);

      // The price list is a VIEW over the whole trail, so the footer reports
      // the audit entries behind the page break, not just the price changes.
      await reveal(tester, find.byKey(const Key('price-history-load-more')));
      expect(
        find.text('Load more (${kTrailRows - productHistoryPageSize} remaining)'),
        findsOneWidget,
      );

      await tapLoadMore(tester, 'price-history-load-more');

      expect(repo.requestedHistoryOffsets, [0, productHistoryPageSize]);
      expect(
        find.byKey(const Key('price-history-load-more')),
        findsNothing,
      );
    });

    testWidgets('hides footer when the trail fits one page', (tester) async {
      final repo = PagedProductRepo(
        historyFixture: List.generate(
          productHistoryPageSize,
          (i) => _mkTrailEntry(seq: i + 1),
        ),
      );
      final container = makeHistoryContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        PriceHistoryScreen(product: _mkProduct(id: 1)),
      );
      await dragToEnd(tester);

      expect(
        find.byKey(const Key('price-history-load-more')),
        findsNothing,
      );
    });

    testWidgets('a failed page keeps the prices and says why', (tester) async {
      final repo = PagedProductRepo(
        historyFixture: List.generate(
          kTrailRows,
          (i) => _mkTrailEntry(seq: i + 1),
        ),
      )..failFromOffset = productHistoryPageSize;
      final container = makeHistoryContainer(repo: repo);
      addTearDown(container.dispose);

      await pumpScreen(
        tester,
        container,
        PriceHistoryScreen(product: _mkProduct(id: 1)),
      );
      await tapLoadMore(tester, 'price-history-load-more');

      // The older page failed: the price changes already on screen stay, and
      // the footer reports why instead of pretending the list is complete.
      expect(repo.requestedHistoryOffsets, [0, productHistoryPageSize]);
      await reveal(tester, find.byKey(const Key('price-history-page-error')));
      expect(find.text(_offline.message), findsOneWidget);
      expect(
        find.byKey(const Key('price-history-load-more')),
        findsOneWidget,
      );
    });
  });
}