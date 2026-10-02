import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/router/deep_link.dart';
import 'package:hyperlocal_app/core/router/deep_link_guard.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';

/// A probe whose answer the test dictates, and which counts how often it was
/// asked.
///
/// The call count is the important part: several assertions below are about
/// *not* probing, which is the difference between a crafted link costing one
/// malformed route and costing a network request per tap.
class _FakeProbe implements DeepLinkTargetProbe {
  _FakeProbe(this.state);

  DeepLinkTargetState state;
  int callCount = 0;

  @override
  Future<DeepLinkTargetState> probe(DeepLinkIntent intent) async {
    callCount++;
    return state;
  }
}

final _readyEnv = DeepLinkEnvironment(
  authStatus: AuthStatus.authenticated,
  isAppReady: true,
  now: DateTime(2026, 1, 1),
);

void main() {
  group('evaluateDeepLink: the four checks', () {
    test(
      'entity exists (form) — a malformed id never reaches the probe',
      () async {
        final probe = _FakeProbe(DeepLinkTargetState.available);
        final decision = await evaluateDeepLink(
          intent: const DeepLinkIntent(entity: DeepLinkEntity.product, id: ''),
          environment: _readyEnv,
          probe: probe,
        );

        expect(decision.isAllowed, isFalse);
        expect(decision.reason, DeepLinkBlockReason.malformed);
        expect(
          probe.callCount,
          0,
          reason: 'a malformed link must not cost a network request',
        );
      },
    );

    test(
      'required context — a link before the app is ready is held back',
      () async {
        final probe = _FakeProbe(DeepLinkTargetState.available);
        final decision = await evaluateDeepLink(
          intent: const DeepLinkIntent(
            entity: DeepLinkEntity.product,
            id: 'p1',
          ),
          environment: DeepLinkEnvironment(
            authStatus: AuthStatus.initial,
            isAppReady: false,
            now: DateTime(2026),
          ),
          probe: probe,
        );

        expect(decision.isAllowed, isFalse);
        expect(decision.reason, DeepLinkBlockReason.missingContext);
        expect(probe.callCount, 0);
      },
    );

    test('auth state — a guest cannot open an account-scoped offer', () async {
      final probe = _FakeProbe(DeepLinkTargetState.available);
      final decision = await evaluateDeepLink(
        intent: const DeepLinkIntent(entity: DeepLinkEntity.offer, id: 'o1'),
        environment: DeepLinkEnvironment(
          authStatus: AuthStatus.guest,
          isAppReady: true,
          now: DateTime(2026),
        ),
        probe: probe,
      );

      expect(decision.isAllowed, isFalse);
      expect(decision.reason, DeepLinkBlockReason.unauthenticated);
      expect(
        probe.callCount,
        0,
        reason:
            'refusing before probing stops the probe leaking that a '
            'private entity exists',
      );
    });

    test('auth state — a signed-out customer cannot open the inbox', () async {
      final decision = await evaluateDeepLink(
        intent: const DeepLinkIntent.notifications(),
        environment: DeepLinkEnvironment(
          authStatus: AuthStatus.unauthenticated,
          isAppReady: true,
          now: DateTime(2026),
        ),
        probe: _FakeProbe(DeepLinkTargetState.available),
      );
      expect(decision.reason, DeepLinkBlockReason.unauthenticated);
    });

    test(
      'auth state — a guest CAN open a product (browsing is public)',
      () async {
        final decision = await evaluateDeepLink(
          intent: const DeepLinkIntent(
            entity: DeepLinkEntity.product,
            id: 'p1',
          ),
          environment: DeepLinkEnvironment(
            authStatus: AuthStatus.guest,
            isAppReady: true,
            now: DateTime(2026),
          ),
          probe: _FakeProbe(DeepLinkTargetState.available),
        );
        expect(decision.isAllowed, isTrue);
        expect(decision.path, '/product/p1');
      },
    );

    test('entity gone — a deleted product falls back gracefully', () async {
      final decision = await evaluateDeepLink(
        intent: const DeepLinkIntent(entity: DeepLinkEntity.product, id: 'p1'),
        environment: _readyEnv,
        probe: _FakeProbe(DeepLinkTargetState.gone),
      );

      expect(decision.isAllowed, isFalse);
      expect(decision.reason, DeepLinkBlockReason.notFound);
      expect(decision.path, isNull);
      expect(decision.fallbackPath, kDeepLinkFallbackPath);
      expect(decision.message, isNotNull);
    });

    test('entity unavailable — an expired offer says so, not "gone"', () async {
      final decision = await evaluateDeepLink(
        intent: const DeepLinkIntent(entity: DeepLinkEntity.offer, id: 'o1'),
        environment: _readyEnv,
        probe: _FakeProbe(DeepLinkTargetState.unavailable),
      );

      expect(decision.reason, DeepLinkBlockReason.unavailable);
      expect(
        decision.message,
        isNot(deepLinkMessageFor(DeepLinkBlockReason.notFound)),
      );
    });

    test('a healthy entity is allowed through to its route', () async {
      final decision = await evaluateDeepLink(
        intent: const DeepLinkIntent(entity: DeepLinkEntity.shop, id: 's1'),
        environment: _readyEnv,
        probe: _FakeProbe(DeepLinkTargetState.available),
      );

      expect(decision.isAllowed, isTrue);
      expect(decision.path, '/shop/s1');
      expect(decision.reason, isNull);
      expect(decision.message, isNull);
    });
  });

  group('graceful fallback', () {
    test('every refusal still names a destination', () async {
      for (final state in [
        DeepLinkTargetState.gone,
        DeepLinkTargetState.unavailable,
      ]) {
        final decision = await evaluateDeepLink(
          intent: const DeepLinkIntent(
            entity: DeepLinkEntity.product,
            id: 'p1',
          ),
          environment: _readyEnv,
          probe: _FakeProbe(state),
        );
        expect(
          decision.fallbackPath,
          kDeepLinkFallbackPath,
          reason: 'a refused link must never end on a dead screen',
        );
        expect(decision.message, isNotEmpty);
      }
    });

    test('each reason has distinct customer-facing copy', () {
      final messages = DeepLinkBlockReason.values
          .map(deepLinkMessageFor)
          .toSet();
      expect(
        messages.length,
        DeepLinkBlockReason.values.length,
        reason: 'distinct reasons must not collapse into one dead end',
      );
    });

    test('no refusal copy leaks an internal id or route', () {
      for (final reason in DeepLinkBlockReason.values) {
        final message = deepLinkMessageFor(reason);
        expect(message, isNot(contains('/')));
        expect(message, isNot(matches(RegExp(r'\d{3,}'))));
      }
    });
  });

  group('deepLinkRequiresAuthentication', () {
    test('marks exactly the account-scoped entities', () {
      expect(deepLinkRequiresAuthentication(DeepLinkEntity.offer), isTrue);
      expect(
        deepLinkRequiresAuthentication(DeepLinkEntity.notification),
        isTrue,
      );
      expect(deepLinkRequiresAuthentication(DeepLinkEntity.product), isFalse);
      expect(deepLinkRequiresAuthentication(DeepLinkEntity.shop), isFalse);
      expect(deepLinkRequiresAuthentication(DeepLinkEntity.search), isFalse);
    });
  });
}
