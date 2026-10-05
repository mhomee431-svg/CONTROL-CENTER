import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/product_attributes.dart';

CategoryProductAttributes attrsFrom(
  List<Map<String, dynamic>> list, {
  String code = 'PHARMACY_HEALTHCARE',
}) =>
    CategoryProductAttributes.fromJson({
      'category_code': code,
      'attributes': list,
    });

void main() {
  group('backend payload parsing', () {
    test('parses every declared property', () {
      final set = attrsFrom([
        {
          'key': 'price',
          'label': 'Price',
          'kind': 'NUMBER',
          'required': true,
          'hint': 'Where applicable',
          'choices': <String>[],
        },
      ]);
      final spec = set.attributes.single;
      expect(spec.key, 'price');
      expect(spec.kind, ProductAttributeKind.number);
      expect(spec.required, isTrue);
      expect(spec.hint, 'Where applicable');
      expect(spec.icon, isNotNull);
    });

    test('empty attribute list means no product form, not a crash', () {
      final set = attrsFrom(const [], code: 'RESTAURANTS');
      expect(set.hasNoProductForm, isTrue);
      expect(set.categoryCode, 'RESTAURANTS');
      expect(set.isComplete(const {}), isTrue);
    });

    test('survives a malformed payload from the network', () {
      expect(
        CategoryProductAttributes.fromJson(const {}).attributes,
        isEmpty,
      );
      expect(CategoryProductAttributes.fromJson(null).attributes, isEmpty);
    });

    test('drops entries with no key rather than rendering a blank input', () {
      final set = attrsFrom([
        {'label': 'No key here', 'kind': 'TEXT'},
        {'key': 'name', 'label': 'Name', 'kind': 'TEXT'},
      ]);
      expect(set.attributes.length, 1);
      expect(set.attributes.single.key, 'name');
    });

    test('an unknown future key still renders as text', () {
      final set = attrsFrom([
        {
          'key': 'warranty_months',
          'label': 'Warranty (months)',
          'kind': 'NUMBER',
        },
      ]);
      final spec = set.attributes.single;
      expect(spec.isKnownKey, isFalse);
      expect(spec.kind, ProductAttributeKind.number);
      expect(spec.errorFor('12'), isNull);
      expect(spec.errorFor('abc'), isNotNull);
    });

    test('an unknown kind falls back to text instead of crashing', () {
      expect(
        ProductAttributeKind.parse('SOMETHING_NEW'),
        ProductAttributeKind.text,
      );
      expect(ProductAttributeKind.parse(null), ProductAttributeKind.text);
    });
  });

  group('catalog-backed attributes', () {
    test('a catalog key is marked even when the flag is absent', () {
      // An older backend omits `catalog_backed`. The client must still offer a
      // picker, because `category_id` is a foreign key — a typed value there is
      // silently discarded on save.
      final spec = ProductAttributeSpec.fromJson({
        'key': 'category',
        'label': 'Category',
        'kind': 'TEXT',
      });
      expect(spec.catalogBacked, isTrue);
    });

    test('product type is catalog-backed, not free text', () {
      // "Hair Care, Skin Care…" are examples only; the real list comes from the
      // catalog, so the field must be a picker fed by it.
      final spec = ProductAttributeSpec.fromJson({
        'key': 'product_type',
        'label': 'Product type',
        'kind': 'TEXT',
        'hint': 'Hair Care, Skin Care… (examples only)',
      });
      expect(spec.catalogBacked, isTrue);
      expect(spec.options, isEmpty);
    });

    test('a genuinely free-text field is not marked', () {
      // Applying the flag everywhere would be as wrong as omitting it: a brand
      // really is free text.
      for (final key in ['name', 'brand', 'variant', 'description']) {
        final spec = ProductAttributeSpec.fromJson({
          'key': key,
          'label': key,
          'kind': 'TEXT',
        });
        expect(spec.catalogBacked, isFalse, reason: key);
      }
    });

    test('an explicit false from the backend is honoured', () {
      final spec = ProductAttributeSpec.fromJson({
        'key': 'category',
        'label': 'Category',
        'kind': 'TEXT',
        'catalog_backed': false,
      });
      expect(spec.catalogBacked, isFalse);
    });
  });

  group('category differences', () {
    test('pharmacy does not expose regulatory fields', () {
      // The spec's IMPORTANT rule: licence, regulatory and medical-attribute
      // fields are future work, to be implemented only once the backend defines
      // the requirements. They must not be rendered, not even as free text.
      final set = attrsFrom([
        {'key': 'name', 'label': 'Product name', 'kind': 'TEXT'},
        {'key': 'price', 'label': 'Price', 'kind': 'NUMBER'},
      ], code: 'PHARMACY_HEALTHCARE');
      for (final spec in set.attributes) {
        expect(spec.key, isNot(contains('regulat')));
        expect(spec.key, isNot(contains('licen')));
        expect(spec.key, isNot(contains('prescription')));
      }
    });

    test('the enum has no regulatory keys to reference', () {
      // A declared-but-unused key invites wiring a regulatory field up later
      // without re-reading the spec, so the keys must not exist at all.
      for (final key in ProductAttributeKey.values) {
        expect(key.wireName, isNot(contains('regulat')));
        expect(key.wireName, isNot(contains('licen')));
        expect(key.wireName, isNot(contains('prescription')));
      }
    });

    test('an unrecognised regulatory key from the server still renders', () {
      // Fail-safe direction: if a future backend DOES define these, the form
      // must show what the server asked for rather than silently hiding it. The
      // gate here is that the backend has not defined them, not that this build
      // is incapable of showing them.
      final set = attrsFrom([
        {'key': 'regulatory_class', 'label': 'Regulatory class', 'kind': 'TEXT'},
      ]);
      final spec = set.attributes.single;
      expect(spec.isKnownKey, isFalse);
      expect(spec.label, 'Regulatory class');
    });

    test('automotive never invents vehicle compatibility', () {
      // The backend does not send a compatibility field, so there is nothing
      // for the app to assume.
      final set = attrsFrom([
        {'key': 'name', 'label': 'Product name', 'kind': 'TEXT'},
      ], code: 'AUTOMOTIVE_PARTS_TOOLS');
      expect(set.attributes.any((s) => s.key.contains('compat')), isFalse);
      expect(set.attributes.any((s) => s.key.contains('vehicle')), isFalse);
    });

    test('books never make ISBN mandatory for every item', () {
      final set = attrsFrom([
        {
          'key': 'barcode',
          'label': 'ISBN / barcode',
          'kind': 'TEXT',
          'required': false,
        },
      ], code: 'BOOKS_MEDIA_STATIONERY');
      expect(set.isComplete(const {}), isTrue);
    });
  });

  group('validation', () {
    test('required attributes must be filled', () {
      final set = attrsFrom([
        {
          'key': 'name',
          'label': 'Product name',
          'kind': 'TEXT',
          'required': true,
        },
      ]);
      expect(set.validate(const {}).containsKey('name'), isTrue);
      expect(set.isComplete(const {'name': 'Brake Pad'}), isTrue);
    });

    test('blank optional attributes are valid', () {
      final set = attrsFrom([
        {'key': 'mrp', 'label': 'MRP', 'kind': 'NUMBER'},
      ]);
      expect(set.validate(const {'mrp': ''}), isEmpty);
    });

    test('non-numeric text is rejected for a number attribute', () {
      final set = attrsFrom([
        {'key': 'quantity', 'label': 'Quantity', 'kind': 'NUMBER'},
      ]);
      expect(set.validate(const {'quantity': 'many'})['quantity'], isNotNull);
      expect(set.validate(const {'quantity': '12'}), isEmpty);
    });

    test('negative numbers are rejected', () {
      final set = attrsFrom([
        {'key': 'quantity', 'label': 'Quantity', 'kind': 'NUMBER'},
      ]);
      expect(
        set.validate(const {'quantity': '-5'}).containsKey('quantity'),
        isTrue,
      );
    });

    test('zero price is rejected', () {
      final set = attrsFrom([
        {
          'key': 'price',
          'label': 'Price',
          'kind': 'NUMBER',
          'required': true,
        },
      ]);
      expect(set.validate(const {'price': '0'}).containsKey('price'), isTrue);
      expect(set.validate(const {'price': '499'}), isEmpty);
    });

    test('a choice must be one of the options the backend sent', () {
      final set = attrsFrom([
        {
          'key': 'availability',
          'label': 'Available',
          'kind': 'CHOICE',
          'choices': ['Yes', 'No'],
        },
      ]);
      expect(set.validate(const {'availability': 'Yes'}), isEmpty);
      expect(
        set.validate(const {'availability': 'Maybe'}).containsKey('availability'),
        isTrue,
      );
    });
  });

  group('submission', () {
    test('numbers are sent as JSON numbers, not strings', () {
      final set = attrsFrom([
        {'key': 'price', 'label': 'Price', 'kind': 'NUMBER'},
      ]);
      final body = set.toSubmissionJson(const {'price': '499'});
      final attr = (body['attributes'] as List).single as Map;
      expect(attr['value'], 499);
      expect(attr['value'], isA<int>());
    });

    test('decimals survive as doubles', () {
      final set = attrsFrom([
        {'key': 'price', 'label': 'Price', 'kind': 'NUMBER'},
      ]);
      final attr =
          (set.toSubmissionJson(const {'price': '49.50'})['attributes'] as List)
              .single as Map;
      expect(attr['value'], 49.5);
    });

    test('blank attributes are omitted, not sent as empty strings', () {
      final set = attrsFrom([
        {'key': 'name', 'label': 'Name', 'kind': 'TEXT'},
        {'key': 'brand', 'label': 'Brand', 'kind': 'TEXT'},
      ]);
      final body =
          set.toSubmissionJson(const {'name': 'Spark Plug', 'brand': ''});
      final attrs = body['attributes'] as List;
      expect(attrs.length, 1);
      expect((attrs.single as Map)['key'], 'name');
    });

    test('the category code travels with the values', () {
      final set = attrsFrom([
        {'key': 'name', 'label': 'Name', 'kind': 'TEXT'},
      ], code: 'HARDWARE');
      expect(
        set.toSubmissionJson(const {'name': 'Nut'})['category_code'],
        'HARDWARE',
      );
    });
  });

  group('the attributes map the create endpoint accepts', () {
    // The server refuses a column-routed key and a catalog-backed name, so the
    // client must not build them into the map: a form that fills itself in and
    // is then rejected reads as a bug, not as a policy.
    test('a plain category field is included', () {
      final set = attrsFrom([
        {'key': 'material', 'label': 'Material', 'kind': 'TEXT'},
      ]);
      expect(
        set.toAttributeMap(const {'material': 'Brass'}),
        {'material': 'Brass'},
      );
    });

    test('a key that owns a column is left out', () {
      final set = attrsFrom([
        {'key': 'name', 'label': 'Name', 'kind': 'TEXT'},
        {'key': 'price', 'label': 'Price', 'kind': 'NUMBER'},
        {'key': 'barcode', 'label': 'Barcode', 'kind': 'TEXT'},
        {'key': 'material', 'label': 'Material', 'kind': 'TEXT'},
      ]);
      final map = set.toAttributeMap(const {
        'name': 'M8 Bolt',
        'price': '12',
        'barcode': '12345678',
        'material': 'Brass',
      });
      expect(map, {'material': 'Brass'});
    });

    test('a catalog-backed key is left out, because ids travel separately', () {
      final set = attrsFrom([
        {'key': 'category', 'label': 'Category', 'kind': 'TEXT',
         'catalog_backed': true},
        {'key': 'subcategory', 'label': 'Subcategory', 'kind': 'TEXT',
         'catalog_backed': true},
      ]);
      expect(
        set.toAttributeMap(const {'category': 'Tools', 'subcategory': 'Bolts'}),
        isEmpty,
      );
    });

    test('a blank value is omitted rather than sent as empty', () {
      final set = attrsFrom([
        {'key': 'material', 'label': 'Material', 'kind': 'TEXT'},
      ]);
      expect(set.toAttributeMap(const {'material': '   '}), isEmpty);
    });

    test('a service category produces an empty map', () {
      final set = attrsFrom([], code: 'RESTAURANTS');
      expect(set.hasNoProductForm, isTrue);
      expect(set.toAttributeMap(const {'anything': 'x'}), isEmpty);
    });

    test('a typed identifier travels in the map for the server to route', () {
      // The backend writes it to product_identifiers with its type, so the
      // client sends the plain value and lets the server place it.
      final set = attrsFrom([
        {'key': 'oem_reference_number', 'label': 'OEM',
         'kind': 'TEXT', 'identifier_type': 'MPN'},
      ]);
      expect(
        set.toAttributeMap(const {'oem_reference_number': 'ABC-1'}),
        {'oem_reference_number': 'ABC-1'},
      );
    });
  });
}