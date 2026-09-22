// Support tickets — REAL backend intake + tracking.
//
// Pins the app side of `/shopkeeper/support/tickets`: the ticket model renders
// exactly the status the backend sent (never a locally invented progression),
// the list shows server truth, and signing out drops the previous account's
// history. Anything the app cannot parse is an honest empty/error state — no
// fabricated ticket, no invented status.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/auth/firebase_auth_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/permissions/data/permission_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/app_router.dart';
import 'package:hyperlocal_shopkeeper_app/core/router/route_names.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/data/sessions_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/insights/data/insights_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notification_preferences_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/data/support_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/data/support_screenshot_picker.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/domain/support_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/domain/support_ticket.dart';
import 'package:hyperlocal_shopkeeper_app/features/support/presentation/controllers/support_tickets_controller.dart';

import 'fakes.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

Map<String, dynamic> ticketJson({
  int id = 42,
  String reference = 'HL-42',
  String subject = 'Price saved as old value',
  String status = 'OPEN',
  String statusLabel = 'Submitted',
  String category = 'APP_PRODUCTS',
  String? categoryLabel = 'Products & catalogue',
  String? priority = 'MEDIUM',
  String? shopName = 'Kirana Corner',
  String? resolutionNotes,
  String createdAt = '2026-09-21T10:00:00+00:00',
  String? resolvedAt,
}) => <String, dynamic>{
  'id': id,
  'reference': reference,
  'subject': subject,
  'description': 'I changed the price and it saved the old value.',
  'category': category,
  'category_label': categoryLabel,
  'status': status,
  'status_label': statusLabel,
  'priority': priority,
  'shop_name': shopName,
  'resolution_notes': resolutionNotes,
  'created_at': createdAt,
  'resolved_at': resolvedAt,
};

SupportTicket makeTicket(
  String status, {
  String label = 'Submitted',
  int id = 42,
  String? notes,
}) {
  final json = ticketJson(id: id, status: status, statusLabel: label)
    ..['resolution_notes'] = notes;
  return SupportTicket.fromJson(json);
}

/// Scriptable fake for `SupportRepository`; counts calls for the assertions.
class FakeSupportRepo implements SupportRepository {
  FakeSupportRepo({
    this.tickets = const <SupportTicket>[],
    this.created,
    this.error,
    this.createError,
    this.allTickets,
  });

  List<SupportTicket> tickets;
  SupportTicket? created;
  Object? error;
  Object? createError;

  /// Full fixture for PAGED reads.
  ///
  /// When set, the fake slices it by `limit`/`offset` exactly like the tickets
  /// endpoint and reports the server's total, so a "Load more" test pages
  /// through real second-page tickets instead of replaying page one.
  final List<SupportTicket>? allTickets;

  int fetchCalls = 0;
  int createCalls = 0;
  int uploadCalls = 0;
  int fetchOneCalls = 0;
  int? lastCreatedShopId;
  String? lastCreatedCategory;
  String? lastCreatedPriority;
  String? lastCreatedDescription;
  String? lastCreatedAttachmentKey;

  /// The `offset` of every list request, in order.
  final List<int> requestedOffsets = [];

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
  }) async {
    createCalls++;
    lastCreatedShopId = shopId;
    lastCreatedCategory = category.code;
    lastCreatedPriority = severity.code;
    lastCreatedDescription = description;
    lastCreatedAttachmentKey = attachmentKey;
    if (createError != null) throw createError!;
    return created ?? makeTicket('OPEN');
  }

  @override
  Future<String> uploadAttachment({
    required String token,
    required String filename,
    required String contentType,
    required Uint8List bytes,
  }) async {
    uploadCalls++;
    if (createError != null) throw createError!;
    return 'support/fake-attachment-key';
  }

  @override
  Future<SupportTicketsPage> fetchTickets(
    String token, {
    int limit = supportTicketsPageSize,
    int offset = 0,
  }) async {
    fetchCalls++;
    requestedOffsets.add(offset);
    if (error != null) throw error!;
    final full = allTickets;
    if (full != null) {
      final start = offset < full.length ? offset : full.length;
      final end = offset + limit < full.length ? offset + limit : full.length;
      return SupportTicketsPage(
        tickets: full.sublist(start, end),
        total: full.length,
      );
    }
    return SupportTicketsPage(tickets: tickets, total: tickets.length);
  }

  @override
  Future<SupportTicket> fetchTicket(int ticketId, String token) async {
    fetchOneCalls++;
    if (error != null) throw error!;
    return tickets.firstWhere((t) => t.id == ticketId);
  }
}

// ── Harness (mirrors settings_support_test's real-app container) ────────────

ProviderContainer buildContainer({FakeSupportRepo? support}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository()..restoreResult = makeSession(),
      ),
      firebaseAuthServiceProvider.overrideWithValue(FakeFirebaseAuthService()),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      notificationsRepositoryProvider.overrideWithValue(
        FakeNotificationsRepo(),
      ),
      sessionsRepositoryProvider.overrideWithValue(FakeSessionsRepo()),
      notificationPreferencesStoreProvider.overrideWithValue(
        InMemoryNotificationPreferencesStore(),
      ),
      permissionServiceProvider.overrideWithValue(InMemoryPermissionService()),
      insightsRepositoryProvider.overrideWithValue(FakeInsightsRepo()),
      supportRepositoryProvider.overrideWithValue(
        support ?? FakeSupportRepo(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShopkeeperApp(),
    ),
  );
  await tester.pumpAndSettle();
}


void main() {
  group('TicketStatus mapping (backend vocabulary, no invented progression)', () {
    test('maps every backend complaint status', () {
      expect(TicketStatus.fromCode('OPEN'), TicketStatus.open);
      expect(TicketStatus.fromCode('in_progress'), TicketStatus.inProgress);
      expect(TicketStatus.fromCode(' RESOLVED '), TicketStatus.resolved);
      expect(TicketStatus.fromCode('CLOSED'), TicketStatus.closed);
      expect(TicketStatus.fromCode('REJECTED'), TicketStatus.rejected);
    });

    test('an unknown status maps to null instead of guessing', () {
      expect(TicketStatus.fromCode('ESCALATED'), isNull);
      expect(TicketStatus.fromCode(null), isNull);
      expect(TicketStatus.fromCode(''), isNull);
    });

    test('active vs finished split matches the triage lifecycle', () {
      expect(TicketStatus.open.isActive, isTrue);
      expect(TicketStatus.inProgress.isActive, isTrue);
      expect(TicketStatus.resolved.isFinished, isTrue);
      expect(TicketStatus.closed.isFinished, isTrue);
      expect(TicketStatus.rejected.isFinished, isTrue);
    });
  });

  group('SupportTicket model real-data rules', () {
    test('parses the backend payload verbatim', () {
      final t = SupportTicket.fromJson(ticketJson());

      expect(t.id, 42);
      expect(t.reference, 'HL-42');
      expect(t.subject, 'Price saved as old value');
      expect(t.category, 'APP_PRODUCTS');
      expect(t.categoryLabel, 'Products & catalogue');
      expect(t.statusLabel, 'Submitted');
      expect(t.status, TicketStatus.open);
      expect(t.hasResolution, isFalse);
      expect(t.isValid, isTrue);
    });

    test('falls back to the raw status when no label is sent', () {
      final json = ticketJson()..remove('status_label');
      expect(SupportTicket.fromJson(json).statusLabel, 'OPEN');
    });

    test('resolution notes only come from the server', () {
      final t = makeTicket('RESOLVED', label: 'Resolved', notes: 'Fixed in v1.4');
      expect(t.status, TicketStatus.resolved);
      expect(t.hasResolution, isTrue);
    });

    test('listFrom skips rows the app cannot track', () {
      final rows = SupportTicket.listFrom(<String, dynamic>{
        'tickets': <Object?>[
          ticketJson(id: 1),
          <String, dynamic>{'id': 2}, // no status / subject → unusable
          'garbage',
          ticketJson(id: 3, status: 'RESOLVED', statusLabel: 'Resolved'),
        ],
      });

      expect(rows.map((t) => t.id), [1, 3]);
      expect(rows[1].status, TicketStatus.resolved);
    });

    test('an unknown envelope shape yields an empty list', () {
      expect(SupportTicket.listFrom(null), isEmpty);
      expect(SupportTicket.listFrom(<String, dynamic>{}), isEmpty);
    });
  });


  group('SupportTicketsController (real container, fake repo)', () {
    test('load fills the list with what the server returned', () async {
      final repo = FakeSupportRepo(tickets: [
        makeTicket('OPEN', id: 1),
        makeTicket('RESOLVED', label: 'Resolved', id: 2),
      ]);
      final container = buildContainer(support: repo);

      await container.read(supportTicketsProvider.notifier).load();

      final state = container.read(supportTicketsProvider);
      expect(state.status, SupportTicketsStatus.ready);
      expect(state.tickets.map((t) => t.id), [1, 2]);
      expect(state.isEmpty, isFalse);
    });

    test('a failed load reports the failure with a retryable error state',
        () async {
      final repo = FakeSupportRepo(
        error: const ApiException(message: 'backend unreachable'),
      );
      final container = buildContainer(support: repo);

      await container.read(supportTicketsProvider.notifier).load();

      final state = container.read(supportTicketsProvider);
      expect(state.status, SupportTicketsStatus.error);
      expect(state.message, 'backend unreachable');
    });

    test('submit posts the category/severity codes and the selected shop',
        () async {
      final repo = FakeSupportRepo(created: makeTicket('OPEN'));
      final container = buildContainer(support: repo);

      final filed =
          await container.read(supportTicketsProvider.notifier).submit(
                category: IssueCategory.offers,
                severity: IssueSeverity.high,
                description: 'Offers disappear after saving',
              );

      expect(filed, isNotNull);
      expect(repo.createCalls, 1);
      expect(repo.lastCreatedCategory, 'APP_OFFERS');
      expect(repo.lastCreatedPriority, 'HIGH');
      expect(repo.lastCreatedShopId, 10);
      // The server's ticket is prepended to the cached list.
      expect(
        container.read(supportTicketsProvider).tickets.first.reference,
        'HL-42',
      );
    });

    test('a failed submit surfaces the reason and files nothing', () async {
      final repo = FakeSupportRepo(
        createError: const ApiException(message: 'Description too short'),
      );
      final container = buildContainer(support: repo);

      final filed =
          await container.read(supportTicketsProvider.notifier).submit(
                category: IssueCategory.other,
                severity: IssueSeverity.low,
                description: 'Something odd',
              );

      expect(filed, isNull);
      expect(
        container.read(supportTicketsProvider).submitError,
        'Description too short',
      );
    });

    test('submit uploads a screenshot and attaches its key to the ticket',
        () async {
      final repo = FakeSupportRepo(created: makeTicket('OPEN'));
      final container = buildContainer(support: repo);

      final filed =
          await container.read(supportTicketsProvider.notifier).submit(
                category: IssueCategory.products,
                severity: IssueSeverity.medium,
                description: 'Screenshot shows the wrong price',
                screenshot: PickedScreenshot(
                  filename: 'evidence.webp',
                  contentType: 'image/webp',
                  bytes: Uint8List(4),
                ),
              );

      expect(filed, isNotNull);
      // The screenshot is uploaded (grant -> upload -> confirm) BEFORE the
      // ticket is filed...
      expect(repo.uploadCalls, 1);
      // ...and the confirmed media key is attached so support can fetch it.
      expect(repo.lastCreatedAttachmentKey, 'support/fake-attachment-key');
      expect(repo.lastCreatedCategory, 'APP_PRODUCTS');
    });

    test('reset drops every ticket (the logout contract)', () async {
      final repo = FakeSupportRepo(tickets: [makeTicket('OPEN')]);
      final container = buildContainer(support: repo);
      await container.read(supportTicketsProvider.notifier).load();
      expect(container.read(supportTicketsProvider).isEmpty, isFalse);

      container.read(supportTicketsProvider.notifier).reset();

      final state = container.read(supportTicketsProvider);
      expect(state.tickets, isEmpty);
      expect(state.lastFiled, isNull);
    });
  });


  group('support ticket screens (real router)', () {
    testWidgets('my tickets shows the server rows with their real statuses',
        (tester) async {
      final repo = FakeSupportRepo(tickets: [
        makeTicket('OPEN', id: 1, label: 'Submitted'),
        makeTicket('IN_PROGRESS', id: 2, label: 'In progress'),
        makeTicket('RESOLVED', id: 3, label: 'Resolved', notes: 'Fixed in v1.4'),
      ]);
      final container = buildContainer(support: repo);
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.myTickets);
      await tester.pumpAndSettle();

      expect(find.text('My support tickets'), findsOneWidget);
      expect(find.byKey(const Key('ticket_reference_1')), findsOneWidget);
      expect(find.byKey(const Key('ticket_reference_2')), findsOneWidget);
      expect(find.byKey(const Key('ticket_reference_3')), findsOneWidget);
      // Statuses are the BACKEND's labels, rendered verbatim.
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.byKey(const Key('ticket_resolution_3')), findsOneWidget);
      expect(repo.fetchCalls, 1);
    });

    testWidgets('an empty history offers the one action that files a ticket',
        (tester) async {
      final container = buildContainer(support: FakeSupportRepo());
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.myTickets);
      await tester.pumpAndSettle();

      expect(find.text('No tickets yet'), findsOneWidget);
      expect(find.byKey(const Key('tickets_file_one')), findsOneWidget);
    });

    testWidgets('a failed load is retryable', (tester) async {
      final repo = FakeSupportRepo(
        error: const ApiException(message: 'backend unreachable'),
      );
      final container = buildContainer(support: repo);
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.myTickets);
      await tester.pumpAndSettle();

      expect(find.text('backend unreachable'), findsOneWidget);

      repo.error = null;
      repo.tickets = [makeTicket('OPEN')];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ticket_reference_42')), findsOneWidget);
    });

    testWidgets('the detail screen re-reads the ticket from the server',
        (tester) async {
      final repo = FakeSupportRepo(
        tickets: [
          makeTicket('RESOLVED', id: 7, label: 'Resolved',
              notes: 'Fixed in v1.4'),
        ],
      );
      final container = buildContainer(support: repo);
      await pumpApp(tester, container);

      container.read(routerProvider).go(Routes.supportTicketDetail(7));
      await tester.pumpAndSettle();

      expect(repo.fetchOneCalls, 1);
      expect(find.text('Fixed in v1.4'), findsOneWidget);
      expect(find.textContaining('Resolved'), findsWidgets);
    });
  });
}

