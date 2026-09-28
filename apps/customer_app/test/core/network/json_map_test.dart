import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/enum_codec.dart';
import 'package:hyperlocal_app/core/network/json_map.dart';

/// A status enum for the [EnumCodec] tests.
///
/// Declared at library scope because Dart forbids an `enum` declaration inside a
/// function or closure body — `group(...)` is a closure.
enum _Status { inStock, outOfStock, lowStock, unknown }

/// The typed JSON reader that every API model decodes through.
///
/// The contract under test: **no read ever throws.** A response that is missing
/// a field, has a field of an unexpected type, carries a renamed key, or
/// contains a value this build has never seen must degrade into a partially
/// populated model — never an exception.
///
/// The bug this layer exists to prevent is subtle and specific: `json['id'] as
/// int` throws when the key is absent, so ONE missing optional field took down
/// an entire screen. These tests fail loudly if that behaviour ever returns.
void main() {
  JsonMap map(Map<String, dynamic> raw) => JsonMap.tryParse(raw);

  group('JsonMap construction is total', () {
    test('wraps a real object', () {
      final m = map({'a': 1});
      expect(m.stringOr('a'), '1');
      expect(m.isNotEmpty, isTrue);
    });

    test('a non-object yields an empty map rather than throwing', () {
      // The envelope's `data` can legitimately be a list, a string, or null.
      for (final input in <Object?>[null, 'text', 42, true, [1, 2]]) {
        final m = JsonMap.tryParse(input);
        expect(m.isEmpty, isTrue, reason: 'input: $input');
        // And every accessor on it is still safe.
        expect(m.string('x'), isNull);
        expect(m.integer('x'), isNull);
        expect(m.decimal('x'), isNull);
        expect(m.boolean('x'), isNull);
        expect(m.dateTime('x'), isNull);
        expect(m.list('x'), isEmpty);
        expect(m.objectList('x'), isEmpty);
        expect(m.stringList('x'), isEmpty);
        expect(m.stringMap('x'), isEmpty);
      }
    });

    test('normalises a loosely typed map', () {
      // JSON decoded through a path that loses the key type still works.
      final m = JsonMap.tryParse(<dynamic, dynamic>{1: 'one'});
      expect(m.stringOr('1'), 'one');
    });

    test('re-wrapping a JsonMap preserves it', () {
      // Regression guard. `JsonMap` is not a `Map`, so without the identity
      // branch a nested model handed to `tryParse` again came back EMPTY and
      // silently lost every field — which is how a line item rendered with a
      // blank product name.
      final original = map({'product_name': 'Shampoo'});
      final again = JsonMap.tryParse(original);
      expect(identical(again, original), isTrue);
      expect(again.stringOr('product_name'), 'Shampoo');
    });
  });

  group('missing fields degrade, never throw', () {
    // This is the regression that motivated the whole class: one absent key
    // used to take down the screen that read it.
    test('every accessor tolerates a completely empty object', () {
      const m = JsonMap({});
      expect(m.string('missing'), isNull);
      expect(m.stringOr('missing'), '');
      expect(m.integer('missing'), isNull);
      // The `Or` variants substitute their own default when the field is absent.
      expect(m.integerOr('missing'), 0);
      expect(m.integerOr('missing', 7), 7);
      expect(m.decimal('missing'), isNull);
      expect(m.decimalOr('missing'), 0);
      expect(m.decimalOr('missing', 1.5), 1.5);
      expect(m.boolean('missing'), isNull);
      expect(m.booleanOr('missing', true), isTrue);
      expect(m.dateTime('missing'), isNull);
      expect(m.list('missing'), isEmpty);
      expect(m.object('missing').isEmpty, isTrue);
      expect(m.objectList('missing'), isEmpty);
      expect(m.stringList('missing'), isEmpty);
      expect(m.stringMap('missing'), isEmpty);
      expect(m.nestedJson('missing').isEmpty, isTrue);
    });

    test('a present-but-null field reads the same as an absent one', () {
      final m = map({'a': null});
      expect(m.has('a'), isFalse);
      expect(m.string('a'), isNull);
      expect(m.integer('a'), isNull);
    });
  });

  group('scalar coercion', () {
    test('string reads accept numbers and bools', () {
      final m = map({'id': 42, 'flag': true});
      expect(m.string('id'), '42');
      expect(m.string('flag'), 'true');
    });

    test('string trims and treats blank as absent', () {
      final m = map({'a': '  hi  ', 'b': '   '});
      expect(m.string('a'), 'hi');
      expect(m.string('b'), isNull);
    });

    test('integer accepts number, numeric string and whole double', () {
      final m = map({
        'a': 7,
        'b': '8',
        'c': 9.0,
        'd': 10.7,
        'e': 'not a number',
        'f': {'nope': 1},
      });
      expect(m.integer('a'), 7);
      expect(m.integer('b'), 8);
      expect(m.integer('c'), 9);
      expect(m.integer('d'), 11);
      expect(m.integer('e'), isNull);
      expect(m.integer('f'), isNull);
    });

    test('decimal accepts numbers and formatted currency strings', () {
      final m = map({
        'a': 12.5,
        'b': 13,
        'c': '14.25',
        'd': '1,299.00',
        'e': '₹55.50',
        'f': 'abc',
      });
      expect(m.decimal('a'), 12.5);
      expect(m.decimal('b'), 13.0);
      expect(m.decimal('c'), 14.25);
      // A formatted string is a real possibility for money and must not
      // silently become 0.
      expect(m.decimal('d'), 1299.0);
      expect(m.decimal('e'), 55.5);
      expect(m.decimal('f'), isNull);
    });

    test('boolean distinguishes false from unreadable', () {
      final m = map({
        'a': true,
        'b': false,
        'c': 'true',
        'd': 'NO',
        'e': 1,
        'f': 0,
        'g': 'maybe',
      });
      expect(m.boolean('a'), isTrue);
      expect(m.boolean('b'), isFalse);
      expect(m.boolean('c'), isTrue);
      expect(m.boolean('d'), isFalse);
      expect(m.boolean('e'), isTrue);
      expect(m.boolean('f'), isFalse);
      // The important one: unparseable is NOT false.
      expect(m.boolean('g'), isNull);
    });
  });

  group('dateTime parsing', () {
    test('ISO-8601 is read', () {
      final m = map({'at': '2026-09-27T12:00:00Z'});
      expect(m.dateTime('at')?.year, 2026);
    });

    test('epoch seconds and milliseconds are distinguished', () {
      // Treating seconds as milliseconds silently yields 1970.
      final seconds = map({'at': 1767225600});
      final millis = map({'at': 1767225600000});
      expect(seconds.dateTime('at')?.millisecondsSinceEpoch, 1767225600000);
      expect(millis.dateTime('at')?.millisecondsSinceEpoch, 1767225600000);
    });

    test('a numeric string is treated as an epoch value', () {
      final m = map({'at': '1767225600'});
      expect(m.dateTime('at')?.millisecondsSinceEpoch, 1767225600000);
    });

    test('zero, negative and garbage yield null, not 1970', () {
      final m = map({'a': 0, 'b': -5, 'c': 'soon'});
      expect(m.dateTime('a'), isNull);
      expect(m.dateTime('b'), isNull);
      expect(m.dateTime('c'), isNull);
    });
  });

  group('structure reads', () {
    test('list tolerates a bare object where a list was expected', () {
      // A one-element collection collapsed to a bare object is a real
      // API-version change; it must not crash the decoder.
      final m = map({'items': {'id': 1}});
      expect(m.list('items').length, 1);
    });

    test('objectList drops non-object rows instead of throwing', () {
      // One malformed row should cost that row, not the whole list.
      final m = map({
        'rows': [
          {'id': 1},
          'garbage',
          42,
          null,
          {'id': 2},
        ],
      });
      final rows = m.objectList('rows');
      expect(rows.length, 2);
      expect(rows.first.stringOr('id'), '1');
      expect(rows.last.stringOr('id'), '2');
    });

    test('stringList drops non-scalar entries and blanks', () {
      final m = map({'tags': ['a', '', 'b', 3, {'x': 1}]});
      expect(m.stringList('tags'), ['a', 'b', '3']);
    });

    test('nestedJson decodes a double-encoded object', () {
      final m = map({'attrs': '{"color":"red","size":"M"}'});
      expect(m.nestedJson('attrs').stringOr('color'), 'red');
    });

    test('nestedJson returns empty for malformed content', () {
      // A TEXT column holding invalid JSON must not break its parent row.
      final m = map({'attrs': 'not json at all'});
      expect(m.nestedJson('attrs').isEmpty, isTrue);
    });

    test('nestedJson accepts an already-decoded object', () {
      // A newer API may stop double-encoding it.
      final m = map({'attrs': {'color': 'red'}});
      expect(m.nestedJson('attrs').stringOr('color'), 'red');
    });

    test('stringMap skips nested structures', () {
      final m = map({
        'm': {'a': 'x', 'b': 2, 'c': null, 'd': {'e': 'f'}},
      });
      expect(m.stringMap('m'), {'a': 'x', 'b': '2'});
    });
  });


  group('version tolerance', () {
    test('firstOf prefers the newest key when several are present', () {
      final m = map({'old': 'v1', 'new': 'v2'});
      expect(m.firstOf(['new', 'old']), 'v2');
    });

    test('firstOf falls through to an older key during a rename', () {
      // This is the whole point: a renamed field costs an entry here, not a
      // crash and not a release.
      final m = map({'stock_status': 'IN_STOCK'});
      expect(m.firstOf(['availability', 'stock_status']), 'IN_STOCK');
    });

    test('firstOf skips a key that is present but null', () {
      final m = map({'new': null, 'old': 'value'});
      expect(m.firstOf(['new', 'old']), 'value');
    });

    test('firstOf returns null when no alias carries a value', () {
      expect(map({'other': 'x'}).firstOf(['a', 'b']), isNull);
    });

    test('typed firstOf variants behave the same way', () {
      expect(map({'a': '5'}).firstDecimalOf(['b', 'a']), 5.0);
      expect(map({'a': 'yes'}).firstBooleanOf(['b', 'a']), isTrue);
      expect(map({'a': '2026-01-02'}).firstDateTimeOf(['b', 'a'])?.year, 2026);
      expect(map({'a': {'k': 1}}).firstObjectOf(['b', 'a']).isNotEmpty, isTrue);
    });

    test('firstBooleanOf reports a genuine false rather than skipping it', () {
      // If it skipped `false` it would fall through to a stale alias and report
      // the wrong thing.
      final m = map({'new': false, 'old': true});
      expect(m.firstBooleanOf(['new', 'old']), isFalse);
    });

    test('firstBooleanOf skips an unreadable value and uses the next alias', () {
      final m = map({'new': 'maybe', 'old': true});
      expect(m.firstBooleanOf(['new', 'old']), isTrue);
    });
  });

  group('EnumCodec never throws on an unknown value', () {
    // A real enum rather than a stand-in, so the test exercises the same
    // `values`/`name` contract the app's enums rely on.
    _Status parse(String? raw) =>
        EnumCodec<_Status>(raw, _Status.values, _Status.unknown);

    test('a known value is decoded', () {
      expect(parse('IN_STOCK'), _Status.inStock);
      expect(parse('outOfStock'), _Status.outOfStock);
    });

    test('an unknown value falls back instead of throwing', () {
      // The core guarantee: a new backend status is DATA, not an error.
      // `Enum.values.byName` would throw here and kill the screen.
      expect(() => parse('QUARANTINED'), returnsNormally);
      expect(parse('QUARANTINED'), _Status.unknown);
    });

    test('null and blank fall back', () {
      expect(parse(null), _Status.unknown);
      expect(parse('   '), _Status.unknown);
    });

    test('separator and casing variants are normalised', () {
      expect(parse('in-stock'), _Status.inStock);
      expect(parse('in stock'), _Status.inStock);
      expect(parse('available'), _Status.inStock);
      expect(parse('UNAVAILABLE'), _Status.outOfStock);
      expect(parse('limited'), _Status.lowStock);
    });
  });

  group('unknownKeys surfaces an API change in debug builds', () {
    test('a field this build does not know about is reported', () {
      // This is what turns a silent contract drift into a visible one.
      final m = map({'id': 1, 'brand_new_field': 'x'});
      expect(m.unknownKeys({'id'}), {'brand_new_field'});
    });

    test('a fully known object reports nothing', () {
      final m = map({'id': 1, 'name': 'a'});
      expect(m.unknownKeys({'id', 'name', 'description'}), isEmpty);
    });
  });
}
