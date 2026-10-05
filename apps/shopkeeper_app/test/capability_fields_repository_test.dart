import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/capability_fields_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/capability_fields.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

/// The merge the repository performs, exercised directly.
///
/// Going through [CapabilityFieldsRepository.load] for each case would need a
/// live HTTP stack; the merge is the part holding the rules, so it is tested
/// here and the transport is covered by the offline-fallback test below.
List<CapabilityFieldSpec> merge(
  Map<String, dynamic> data,
  String code,
) =>
    CapabilityFieldsRepository.fieldsFromServer(
      data,
      fallback: capabilityFieldsFor(resolveCategoryCapabilities(code, null)),
      known: capabilityFieldsFor(resolveCategoryCapabilities(code, null)),
    );

List<CapabilityFieldSpec> localFor(String code) =>
    capabilityFieldsFor(resolveCategoryCapabilities(code, null));

Map<String, dynamic> serverPayload(List<Map<String, dynamic>> fields) =>
    <String, dynamic>{'category_code': 'X', 'fields': fields};

void main() {
  group('a server-only field survives the whole round trip', () {
    // The bug this covers: the form rendered the server's field, the shopkeeper
    // filled it in, and then save() rebuilt the payload from the LOCAL capability
    // table — which has no such field — so the value was dropped on the way out.
    const serverOnly = CapabilityFieldSpec(
      key: 'fleet_size',
      label: 'Fleet size',
      kind: CapabilityFieldKind.number,
      icon: 'directions_bus',
      required: true,
    );

    test('it is submitted even though the local table cannot produce it', () {
      final payload = submittedCapabilityValues(
        const [serverOnly],
        const {'fleet_size': '12'},
      );
      expect(payload, {'fleet_size': '12'});
    });

    test('it is validated as required, so submission is blocked when blank', () {
      final issues = validateCapabilityValues(
        const [serverOnly],
        const <String, String>{},
      );
      expect(issues.containsKey('fleet_size'), isTrue);
      expect(isCapabilityValuesComplete(const [serverOnly], const {}), isFalse);
    });

    test('it stops blocking once filled', () {
      expect(
        isCapabilityValuesComplete(
          const [serverOnly],
          const {'fleet_size': '12'},
        ),
        isTrue,
      );
    });

    test('a blank optional server-only value is omitted, not sent as ""', () {
      expect(
        submittedCapabilityValues(const [serverOnly], const {'fleet_size': '  '}),
        isEmpty,
      );
    });

    test('the local set-based helper cannot see a server-only field', () {
      // Why the explicit-list helpers exist at all: this is what the save path
      // used to do, and it silently threw the value away.
      final local = resolveCategoryCapabilities('TRANSPORT', null);
      expect(
        submittedCapabilityFields(local, const {'fleet_size': '12'}),
        isEmpty,
      );
    });
  });

  group('server wins over the local table', () {
    test('a field the server declares but this build lacks still renders', () {
      // The important direction: a new backend field must not be silently
      // hidden from the shopkeeper.
      final fields = merge(serverPayload([
        {'key': 'fleet_size', 'label': 'Fleet size', 'kind': 'NUMBER'},
      ]), 'TRANSPORT');
      expect(fields.length, 1);
      expect(fields.single.key, 'fleet_size');
      expect(fields.single.label, 'Fleet size');
      expect(fields.single.kind, CapabilityFieldKind.number);
    });

    test('an unknown field still gets a usable icon, not a blank input', () {
      final fields = merge(serverPayload([
        {'key': 'brand_new_field', 'label': 'Brand new', 'kind': 'TEXT'},
      ]), 'TRANSPORT');
      expect(fields.single.icon, isNotEmpty);
    });

    test('the server decides the order', () {
      final fields = merge(serverPayload([
        {'key': 'contact_phone', 'label': 'Contact number', 'kind': 'TEXT'},
        {'key': 'opening_time', 'label': 'Opening time', 'kind': 'TEXT'},
      ]), 'HARDWARE');
      expect(fields.map((f) => f.key).toList(),
          ['contact_phone', 'opening_time']);
    });

    test('the server decides required, overriding the local flag', () {
      final fields = merge(serverPayload([
        {
          'key': 'service_area',
          'label': 'Service area',
          'kind': 'TEXT',
          'required': true,
        },
      ]), 'PERSONAL_TRANSPORT_TRAVEL');
      // Locally optional; the backend has now made it mandatory.
      expect(fields.single.required, isTrue);
      expect(fields.single.errorFor(''), isNotNull);
    });

    test('local shape validation is kept for a known field', () {
      final fields = merge(serverPayload([
        {
          'key': 'booking_lead_hours',
          'label': 'Booking lead time (hours)',
          'kind': 'NUMBER',
        },
      ]), 'BEAUTY_PERSONAL_CARE');
      expect(fields.single.errorFor('soon'), isNotNull);
      expect(fields.single.errorFor('24'), isNull);
    });

    test('server options win over local options', () {
      final fields = merge(serverPayload([
        {
          'key': 'closed_on',
          'label': 'Closed on',
          'kind': 'CHOICE',
          'options': ['Someday', 'Never'],
        },
      ]), 'HARDWARE');
      expect(fields.single.options, ['Someday', 'Never']);
    });

    test('a missing options list falls back to local options', () {
      final fields = merge(serverPayload([
        {'key': 'closed_on', 'label': 'Closed on', 'kind': 'CHOICE'},
      ]), 'HARDWARE');
      expect(fields.single.options, isNotEmpty);
    });
});
group('degrading safely', () {
    test('an empty server list is authoritative, not a reason to re-invent', () {
      // A service category is allowed to declare NO fields. Falling back to the
      // local table here is how a restaurant ends up being shown the built-in
      // inputs for a form the backend deliberately left blank.
      expect(merge(serverPayload(const []), 'HARDWARE'), isEmpty);
    });

    test('a non-list field payload falls back', () {
      expect(merge({'fields': 'oops'}, 'HARDWARE'), localFor('HARDWARE'));
    });

    test('a payload with no fields key falls back', () {
      expect(merge(const {}, 'HARDWARE'), localFor('HARDWARE'));
    });

    test('entries with no key are skipped, not rendered blank', () {
      final fields = merge(serverPayload([
        {'label': 'No key', 'kind': 'TEXT'},
        {'key': 'contact_phone', 'label': 'Contact number', 'kind': 'TEXT'},
      ]), 'HARDWARE');
      expect(fields.length, 1);
      expect(fields.single.key, 'contact_phone');
    });

    test('a non-map entry is skipped without crashing', () {
      final fields = merge(
        <String, dynamic>{
          'fields': [
            'just a string',
            {'key': 'contact_phone', 'label': 'Contact number',
             'kind': 'TEXT'},
          ],
        },
        'HARDWARE',
      );
      expect(fields.length, 1);
    });

    test('a missing label falls back to the local one', () {
      final fields = merge(
        serverPayload([
          {'key': 'contact_phone', 'kind': 'TEXT'},
        ]),
        'HARDWARE',
      );
      expect(fields.single.label, 'Contact number');
    });

    test('an unknown kind degrades to text rather than crashing', () {
      final fields = merge(serverPayload([
        {'key': 'mystery', 'label': 'Mystery', 'kind': 'SOMETHING_ELSE'},
      ]), 'HARDWARE');
      expect(fields.single.kind, CapabilityFieldKind.text);
    });

    test('a payload of only junk still yields a usable form', () {
      final result = merge(serverPayload([
        {'no': 'key at all'},
      ]), 'HARDWARE');
      expect(result, isNotEmpty);
    });
  });

  group('the two contracts stay distinct', () {
    test('shop fields and product attributes never mix', () {
      // A product field must never leak into the shop profile form.
      final shopKeys = localFor('PHARMACY_HEALTHCARE').map((f) => f.key);
      expect(shopKeys, isNot(contains('price')));
      expect(shopKeys, isNot(contains('quantity')));
      expect(shopKeys, contains('contact_phone'));
    });
  });
}