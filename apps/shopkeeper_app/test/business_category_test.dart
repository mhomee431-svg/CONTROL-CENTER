/// BUSINESS CATEGORY — one source of truth, pinned to the backend registry.
///
/// The spec for this area is explicit: the eleven approved categories "must come
/// from one centralized source", must NOT be re-typed into registration / shop
/// profile / product forms / filters / dashboard / reports / backend models, and
/// Grocery / General Food / Food Delivery must not appear.
///
/// A copied list cannot enforce any of that by itself — it only fails once
/// somebody notices. These tests read the BACKEND REGISTRY from disk and
/// compare, so drift fails the build instead of shipping a dropdown that offers
/// a category the server will reject at registration.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

/// Parses `backend/app/models/merchant_category.py` — the authoritative registry
/// — without importing it (Dart cannot run Python, and shelling out to the
/// interpreter would make a unit test depend on the runtime being present).
class _BackendRegistry {
  _BackendRegistry(String source) {
    final enumBody =
        _between(source, 'class MerchantCategoryCode', 'MERCHANT_CATEGORY_NAMES');
    for (final line in enumBody.split('\n')) {
      final m = RegExp(r'^\s*([A-Z_]+)\s*=\s*"([A-Z_]+)"').firstMatch(line);
      if (m != null) codes.add(m.group(2)!);
    }

    final namesBody =
        _between(source, 'MERCHANT_CATEGORY_NAMES', 'MERCHANT_CATEGORIES');
    final nameRe = RegExp(r'MerchantCategoryCode\.([A-Z_]+)\.value:\s*"([^"]+)"');
    for (final m in nameRe.allMatches(namesBody)) {
      names[m.group(1)!] = m.group(2)!;
    }
  }

  static String _between(String s, String start, String end) {
    final i = s.indexOf(start);
    final j = s.indexOf(end, i + 1);
    if (i < 0 || j < 0) return '';
    return s.substring(i, j);
  }

  final codes = <String>[];
  final names = <String, String>{};
}

void main() {
  final registryFile = File('../../backend/app/models/merchant_category.py');

  late _BackendRegistry backend;

  setUpAll(() {
    expect(
      registryFile.existsSync(),
      isTrue,
      reason: 'the backend category registry is the source of truth; if it '
          'moved, update this path rather than deleting the check',
    );
    backend = _BackendRegistry(registryFile.readAsStringSync());
    expect(backend.codes, isNotEmpty,
        reason: 'sanity: the registry really parsed and has codes');
  });

  test('the app list is exactly the backend registry ? no more, no fewer', () {
    expect(
      kBusinessCategoryFallback.map((c) => c.code).toSet(),
      backend.codes.toSet(),
      reason: 'the app must offer precisely the approved categories. An extra '
          'code lets a shopkeeper pick something the backend rejects; a missing '
          'one blocks a legitimate business.',
    );
    expect(kBusinessCategoryFallback.length, backend.codes.length);
  });

  test('every display name matches the backend registry verbatim', () {
    for (final category in kBusinessCategoryFallback) {
      final expected = backend.names[category.code];
      expect(expected, isNotNull,
          reason: '${category.code} has no display name in the registry');
      expect(category.label, expected,
          reason: 'display name for ${category.code} drifted from the backend');
    }
  });

  test('sort order is a dense 1..N sequence', () {
    // A sparse or duplicated order makes the picker ambiguous and can hide a
    // newly inserted category, so it is checked rather than assumed.
    expect(
      kBusinessCategoryFallback.map((c) => c.sortOrder).toList(),
      List.generate(kBusinessCategoryFallback.length, (i) => i + 1),
    );
  });

  test('no grocery / food / delivery category is offered', () {
    const forbidden = [
      'GROCERY', 'FOOD', 'DELIVERY', 'SUPERMARKET', 'FAST_FOOD'
    ];
    for (final category in kBusinessCategoryFallback) {
      for (final word in forbidden) {
        expect(category.code.contains(word), isFalse,
            reason: '${category.code} is not an approved business category');
      }
    }
  });

  test('a category CODE is submitted, never the display label', () {
    // The value posted to /profile-create is the CODE. A form that submitted
    // "Pharmacy & Healthcare" would fail server-side validation with a message
    // the shopkeeper cannot act on.
    for (final category in kBusinessCategoryFallback) {
      expect(category.code, matches(RegExp(r'^[A-Z_]+$')));
      expect(category.label, isNot(equals(category.code)));
    }
  });

  test('no screen re-types the category list', () {
    // The drift that actually shipped: the create-profile picker and the
    // dashboard label switch each carried a private copy of the eleven names.
    // This scans for a second literal list of category CODES anywhere in lib/.
    final offenders = <String>[];
    final codeLiteral = RegExp(
      "'(PHARMACY_HEALTHCARE|BEAUTY_PERSONAL_CARE|FURNITURE_HOME_CARE|"
      "HOUSEHOLD_GOODS|SPORTS_FITNESS_OUTDOOR|BOOKS_MEDIA_STATIONERY|"
      "AUTOMOTIVE_PARTS_TOOLS|RESTAURANTS|PERSONAL_TRANSPORT_TRAVEL)'",
    );

    for (final entry in Directory('lib').listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      // The one allowed home for the list.
      if (entry.path.endsWith('shop_models.dart')) continue;

      final hits = codeLiteral.allMatches(entry.readAsStringSync()).length;
      if (hits > 0) offenders.add('${entry.path} ($hits code literal(s))');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'category codes must not be re-typed outside shop_models.dart — '
          'that duplication is what silently drifts:\n${offenders.join('\n')}',
    );
  });

  group('businessCategoryLabel', () {
    test('renders the canonical name, not the generic humanised code', () {
      // The point of the helper: `humanizeCode` alone would render
      // "Pharmacy healthcare", losing the ampersand the backend prints.
      expect(businessCategoryLabel('PHARMACY_HEALTHCARE'),
          'Pharmacy & Healthcare');
      expect(businessCategoryLabel('AUTOMOTIVE_PARTS_TOOLS'),
          'Automotive Parts & Tools');
    });

    test('an unknown code still renders legibly instead of shouting', () {
      expect(businessCategoryLabel('SOME_NEW_CATEGORY'), 'Some new category');
    });

    test('null and empty are handled without throwing', () {
      expect(businessCategoryLabel(null), 'Not set');
      expect(businessCategoryLabel(''), 'Not set');
    });

    test('covers every registry code', () {
      for (final code in backend.codes) {
        expect(businessCategoryLabel(code), isNot(equals(code)));
      }
    });
  });

  group('business type is a separate concept from category', () {
    test('the list is populated and has no duplicates', () {
      expect(kBusinessTypes, isNotEmpty);
      expect(kBusinessTypes.toSet().length, kBusinessTypes.length);
    });
  });
}