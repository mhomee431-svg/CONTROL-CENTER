/// CAPABILITY CONTRACT — the Dart mirror must not drift from the backend rule.
///
/// The spec requires capability-driven forms and forbids the frontend inventing
/// category rules the backend does not support. Dart cannot import a Python
/// enum, and regex-parsing a Python SOURCE file is fragile: a formatting change
/// there breaks this check silently instead of failing it.
///
/// So the backend exports its registry to
/// `packages/api_contracts/category_capabilities.json`
/// (`backend/scripts/export_category_capabilities.py`, kept fresh by
/// `test_capability_artifact.py`) and both sides read that file. There is no
/// parsing here, and therefore nothing to parse wrongly.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

String get _artifactPath =>
    '../../packages/api_contracts/category_capabilities.json';

Map<String, dynamic> _contract() =>
    jsonDecode(File(_artifactPath).readAsStringSync()) as Map<String, dynamic>;

/// The contract stores capability lists as JSON arrays of wire strings.
Set<String> _wireList(dynamic node) {
  if (node is! List) return <String>{};
  return {for (final item in node) if (item is String) item};
}

/// Every capability wire value the contract mentions anywhere.
Set<String> _declaredIn(Map<String, dynamic> contract) {
  final found = <String>{};
  void walk(Object? node) {
    if (node is List) {
      node.forEach(walk);
    } else if (node is Map) {
      node.values.forEach(walk);
    } else if (node is String && CategoryCapability.fromWire(node) != null) {
      found.add(node);
    }
  }

  walk(contract['categories']);
  walk(contract['always_present']);
  walk(contract['serving_only_exclusions']);
  return found;
}

void main() {
  setUpAll(() {
    expect(File(_artifactPath).existsSync(), isTrue,
        reason: 'the capability contract is generated; run '
            'python backend/scripts/export_category_capabilities.py');
  });

  test('this build can represent every capability the contract declares', () {
    final declared = _declaredIn(_contract());
    expect(declared, isNotEmpty);
    for (final wire in declared) {
      expect(CategoryCapability.fromWire(wire), isNotNull,
          reason: 'the contract declares $wire but the app cannot represent it');
    }
  });

  test('the app invents no capability the contract does not declare', () {
    final declared = _declaredIn(_contract());
    for (final capability in CategoryCapability.values) {
      expect(declared, contains(capability.wire),
          reason: '${capability.wire} exists only in the app; it would never '
              'be granted, so the screen it gates would never appear');
    }
  });

  test('every offline category table matches the contract', () {
    final categories = _contract()['categories'] as Map<String, dynamic>;
    for (final entry in categories.entries) {
      expect(
        kCategoryCapabilityDefaults[entry.key]!.map((c) => c.wire).toSet(),
        _wireList(entry.value['capabilities']),
        reason: 'offline capability table for ${entry.key} drifted',
      );
    }
  });

  test('the app can render a form for every contract category, offline', () {
    final categories = _contract()['categories'] as Map<String, dynamic>;
    expect(kCategoryCapabilityDefaults.keys.toSet(), categories.keys.toSet(),
        reason: 'a category with no offline table shows an empty form until '
            'the network answers');
  });

  test('business types match the contract', () {
    final contract =
        (List<String>.from(_contract()['business_types'] as List))..sort();
    final app = List<String>.from(kBusinessTypesServerVocabulary)..sort();
    expect(app, contract);
  });

  test('serving-only exclusions match the contract', () {
    expect(
      kServingOnlyExclusions.map((c) => c.wire).toSet(),
      _wireList(_contract()['serving_only_exclusions']),
    );
  });

  test('offline resolution reproduces the contract samples exactly', () {
    // The strongest available check: for every category x {Retail, Service} the
    // Dart resolver must produce precisely what the backend resolved. This
    // catches narrowing drift a table-only comparison would miss.
    final samples = _contract()['resolution_samples'] as Map<String, dynamic>;
    expect(samples, isNotEmpty);

    for (final entry in samples.entries) {
      final parts = entry.key.split('|');
      final code = parts.first;
      final businessType =
          parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
      expect(
        resolveCategoryCapabilities(code, businessType)
            .capabilities
            .map((c) => c.wire)
            .toSet(),
        _wireList(entry.value),
        reason: 'resolution for ${entry.key} drifted from the backend',
      );
    }
  });

  group('safety invariants', () {
    test('CONTACT and LOCATION always survive narrowing', () {
      final codes =
          (_contract()['categories'] as Map<String, dynamic>).keys.toList();
      for (final code in codes) {
        for (final businessType in kBusinessTypesServerVocabulary) {
          final resolved = resolveCategoryCapabilities(code, businessType);
          expect(resolved.has(CategoryCapability.contact), isTrue,
              reason: '$code/$businessType lost CONTACT');
          expect(resolved.has(CategoryCapability.location), isTrue,
              reason: '$code/$businessType lost LOCATION');
        }
      }
    });

    test('no forbidden category appears', () {
      // Word-boundary matching: a check that produces false alarms is a check
      // that eventually gets deleted.
      final banned = RegExp(r'\b(GROCERY|FOOD|DELIVERY|SUPERMARKET)\b');
      for (final code in kCategoryCapabilityDefaults.keys) {
        expect(banned.hasMatch(code), isFalse,
            reason: '$code is not an approved business category');
      }
    });

    test('an unknown business type stays permissive', () {
      expect(
        resolveCategoryCapabilities('HOUSEHOLD_GOODS', 'Nope').capabilities,
        resolveCategoryCapabilities('HOUSEHOLD_GOODS', null).capabilities,
      );
    });

    test('an unknown category resolves to the minimum, not everything', () {
      expect(
        resolveCategoryCapabilities('NOT_A_CATEGORY', null).capabilities,
        {CategoryCapability.contact, CategoryCapability.location},
      );
    });
  });

  group('server response parsing', () {
    test('reads the wire payload', () {
      final parsed = CategoryCapabilitySet.fromJson({
        'category_code': 'RESTAURANTS',
        'business_type': 'Service',
        'capabilities': ['SERVICES', 'BOOKING', 'LOCATION'],
      });
      expect(parsed.categoryCode, 'RESTAURANTS');
      expect(parsed.has(CategoryCapability.services), isTrue);
      expect(parsed.has(CategoryCapability.inventory), isFalse);
    });

    test('an unknown capability is skipped, never guessed', () {
      // A build predating a new capability must not silently treat it as
      // granted — that would render a screen the server never authorised.
      final parsed = CategoryCapabilitySet.fromJson({
        'category_code': 'X',
        'capabilities': ['TELEPORTATION', 'PRICE'],
      });
      expect(parsed.capabilities, {CategoryCapability.price});
    });

    test('malformed payloads degrade to empty, not to a crash', () {
      final parsed = CategoryCapabilitySet.fromJson({
        'category_code': 'X',
        'capabilities': 'not-a-list',
      });
      expect(parsed.isEmpty, isTrue);
    });

    test('every wire value round-trips', () {
      for (final capability in CategoryCapability.values) {
        expect(CategoryCapability.fromWire(capability.wire), capability);
      }
    });
  });
}
