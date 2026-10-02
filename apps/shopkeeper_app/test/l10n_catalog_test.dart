import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/errors/app_message_code.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_form_rules.dart';

/// The code -> catalog link the compiler cannot check.
///
/// Every [AppMessageCode] and [ProductFormFieldError] carries the `app_en.arb`
/// key that holds its wording. The resolvers' `switch` statements prove the
/// generated GETTER exists, but the `l10nKey` string beside each code is plain
/// data: rename the ARB entry without touching it and the metadata quietly
/// points at nothing. These tests read the catalog and hold the two together.
void main() {
  final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map<String, dynamic>;

  String wording(String key) => arb[key] as String;

  /// Placeholders the wording interpolates (`{count}`, `{name}`, ...).
  Set<String> placeholders(String text) =>
      RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

  void expectCatalogued(Iterable<String> keys) {
    for (final key in keys) {
      expect(arb.containsKey(key), isTrue,
          reason: 'no app_en.arb entry named "$key"');
      expect(wording(key).trim(), isNotEmpty, reason: '"$key" is empty');
    }
  }

  test('every AppMessageCode names a real catalog entry', () {
    expectCatalogued(AppMessageCode.values.map((code) => code.l10nKey));
  });

  test('every ProductFormFieldError names a real catalog entry', () {
    expectCatalogued(ProductFormFieldError.values.map((code) => code.l10nKey));
  });

  test('the codes that quote a number keep their placeholder', () {
    // The generated getters take an `int`, so an entry that lost `{count}`
    // would still compile — and then ship the sentence without its number.
    for (final key in [
      ProductFormFieldError.barcodeTooShort.l10nKey,
      ProductFormFieldError.tooManyCharacters.l10nKey,
    ]) {
      expect(placeholders(wording(key)), contains('count'),
          reason: '"$key" dropped its {count} placeholder');
    }
  });

  test('any added locale defines every English key with the same placeholders',
      () {
    // Translations are not required yet, so this passes trivially today. It is
    // the seam that keeps a second locale honest: a missing key or a dropped
    // placeholder falls back silently at runtime and never breaks the build.
    final others = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .where((f) => !f.path.endsWith('app_en.arb'));

    for (final file in others) {
      final other = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in arb.entries) {
        if (entry.key.startsWith('@')) continue; // metadata, not a string
        expect(other.containsKey(entry.key), isTrue,
            reason: '${file.path} is missing "${entry.key}"');
        expect(
          placeholders(other[entry.key] as String),
          placeholders(entry.value as String),
          reason: '${file.path} changed the placeholders of "${entry.key}"',
        );
      }
    }
  });
}
