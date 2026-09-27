import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

/// ARCHITECTURE GUARD — paid-feature logic stays in ONE layer.
///
/// Product rule (spec): *"Subscription/plan features may come later. Do not
/// hardcode paid feature logic everywhere."* This is the Flutter tripwire for
/// that rule. It adds no behaviour; it fails the build the moment a screen
/// starts deciding what a shop may do by asking which PLAN it is on.
///
/// The sanctioned shape, and the only one:
///
///     backend derive_shop_capabilities  ->  `canX` flags on the payload
///       ShopCapabilities (model, parses flags)
///         capabilitiesControllerProvider (the ONE stateful layer)
///           CapabilityGate / feature screens (render)
///
/// A screen that reads `subscription.plan` for *display* is fine. A screen
/// that branches on it to decide what to show is the bug this file exists to
/// stop.
void main() {
  final libDir = Directory('lib');
  // Dart's Directory paths are platform-separated (backslash on Windows), so
  // compare on a normalised form or the "one owner" check silently passes.
  final shopModelPath =
      'features${Platform.pathSeparator}shops${Platform.pathSeparator}domain'
      '${Platform.pathSeparator}shop_models.dart';

  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  group('capability layer boundary', () {
    test('no screen gates on a plan name or the subscription status', () {
      // Matching a PLAN against something is the tell. Reading the plan to
      // print it (`'${data.subscription.plan}'`) is not.
      //
      // Scoped to *subscription* state on purpose: `integration.status` and
      // `shop.status` are unrelated lifecycles and must stay free to compare.
      final gateOnPlan = RegExp(r"""(plan|planName)\s*(==|!=)\s*['"]""");
      final gateOnSubscriptionStatus = RegExp(
        r"""subscription\s*\.\s*status\s*(==|!=)\s*['"]""",
        caseSensitive: false,
      );

      final offenders = <String>[];
      for (final file in dartFilesUnder('lib/features')) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (gateOnPlan.hasMatch(line) ||
              gateOnSubscriptionStatus.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'A feature screen is branching on plan/subscription state.\n'
            'Gate on the backend flag instead: watch '
            'capabilitiesControllerProvider and use CapabilityGate '
            '(core/ui/capability_gate.dart). Displaying the plan name is fine; '
            'deciding behaviour from it is not.\n${offenders.join('\n')}',
      );
    });

    test('no invented isPro/isPremium style helper exists', () {
      // These are the shapes a "just this once" shortcut takes. The rule is
      // not the spelling - it is a boolean that means "this shop is paid".
      final shortcut = RegExp(
        r'bool\s+(is|has)(Pro|Premium|Paid|Basic|Enterprise|Plan)\w*\s*[=(]',
        caseSensitive: false,
      );

      final offenders = <String>[];
      for (final file in dartFilesUnder('lib')) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (shortcut.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Introduced a plan-derived boolean. Add an entitlement on the '
            'backend and let derive_shop_capabilities() expose it as a canX '
            'flag instead.\n${offenders.join('\n')}',
      );
    });

    test('the canX flags are declared in exactly one file', () {
      // A second copy of the model is how the two sides stop agreeing.
      const flagNames = [
        'canUsePos',
        'canUploadExcel',
        'canCreateOffers',
        'canViewReports',
      ];
      final owners = <String>[];
      for (final file in dartFilesUnder('lib')) {
        if (file.path.endsWith(shopModelPath)) continue;
        final source = file.readAsStringSync();
        final declared = flagNames
            .where((n) => RegExp('final\\s+bool\\s+$n\\b').hasMatch(source))
            .toList();
        if (declared.isNotEmpty) owners.add('${file.path} -> $declared');
      }

      expect(
        owners,
        isEmpty,
        reason: 'ShopCapabilities is the single model for these flags. '
            'Consumers read them; only $shopModelPath declares them.\n'
            '${owners.join('\n')}',
      );
    });
  });

  group('the layer is actually wired', () {
    test('the model is the one place the flags live', () {
      // Pairs with the boundary test above: the flags must exist somewhere,
      // and that somewhere is the model - not a per-screen local.
      expect(const ShopCapabilities().canUsePos, isTrue);
      expect(
        ShopCapabilities.fromJson(const {'canUsePos': false}).canUsePos,
        isFalse,
      );
    });

    test('an absent flags block stays permissive (never a lock-out)', () {
      final caps = ShopCapabilities.fromJson(null);
      expect(caps.canUsePos, isTrue);
      expect(caps.canUploadExcel, isTrue);
      expect(caps.canCreateOffers, isTrue);
      expect(caps.canViewReports, isTrue);
    });
  });

  test('the lib directory resolved (guards against a silently empty scan)', () {
    // A boundary test whose file list is empty passes for the wrong reason.
    expect(libDir.existsSync(), isTrue, reason: 'run from apps/shopkeeper_app');
    expect(dartFilesUnder('lib').length, greaterThan(50));
  });
}
