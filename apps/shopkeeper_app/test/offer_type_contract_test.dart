/// The backend is the vocabulary for offer types: Pydantic rejects anything
/// outside `OfferType`, so an invented client type dies at the edge as a 422.
/// This contract reads `components.schemas.OfferType.enum` straight out of the
/// saved OpenAPI (`packages/api_contracts/openapi.json`) — the same file the
/// backend test suite pins against — and asserts the app's
/// [ShopkeeperOfferType] codes match it exactly. No parsing layer, no second
/// copy: a drift on either side fails here instead of in production.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/domain/offer_models.dart';

String get _openApiPath => '../../packages/api_contracts/openapi.json';

Set<String> _offerTypeEnum() {
  final doc =
      jsonDecode(File(_openApiPath).readAsStringSync()) as Map<String, dynamic>;
  final components = doc['components'] as Map<String, dynamic>?;
  final schemas = components?['schemas'] as Map<String, dynamic>?;
  final offerType = schemas?['OfferType'] as Map<String, dynamic>?;
  final values = offerType?['enum'];
  return {for (final v in (values as List? ?? const [])) if (v is String) v};
}

void main() {
  setUpAll(() {
    expect(File(_openApiPath).existsSync(), isTrue,
        reason: 'the OpenAPI contract is saved; regenerate '
            'packages/api_contracts/openapi.json');
  });

  test('the app offers every type the backend accepts', () {
    final contract = _offerTypeEnum();
    expect(contract, isNotEmpty);
    final app = {
      for (final t in ShopkeeperOfferType.values) t.code,
    };
    expect(app, contract);
  });

  test('the app invents no type the backend would reject', () {
    final contract = _offerTypeEnum();
    for (final t in ShopkeeperOfferType.values) {
      expect(contract, contains(t.code),
          reason: "'${t.code}' is not in the backend's OfferType enum");
    }
  });

  test('the three value-carrying types route to their own field', () {
    expect(ShopkeeperOfferType.percentageDiscount.requiresPercentage, isTrue);
    expect(ShopkeeperOfferType.flatDiscount.requiresFlatValue, isTrue);
    expect(
        ShopkeeperOfferType.promotionalPrice.requiresPromotionalPrice, isTrue);
    for (final t in ShopkeeperOfferType.values) {
      final needs = [
        t.requiresPercentage,
        t.requiresFlatValue,
        t.requiresPromotionalPrice,
      ].where((b) => b);
      // The offer sheet shows exactly one value field per type; two claiming
      // the same type would fork the form and post the wrong field.
      expect(needs.length, lessThanOrEqualTo(1), reason: t.code);
    }
  });
}
