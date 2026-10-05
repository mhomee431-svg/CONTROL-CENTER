import 'package:flutter/foundation.dart'
    show debugPrint, visibleForTesting;
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_endpoints.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/capability_fields.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/shop_models.dart';

/// Outcome of a capability-field load: what was used, and why.
///
/// Callers need this to tell the shopkeeper the truth. Showing offline fallback
/// data while the screen claims "saved" is how someone ends up believing a field
/// was stored when the server never saw it.
enum CapabilityFieldsSource {
  /// The backend answered. This is the authoritative source.
  server,

  /// The network failed and the built-in table was used instead.
  offlineFallback,
}

/// The resolved field set for a category, plus its provenance.
class CapabilityFieldsResult {
  const CapabilityFieldsResult({required this.fields, required this.source});

  /// Falls back to the built-in table — used only when [source] is
  /// [CapabilityFieldsSource.offlineFallback].
  factory CapabilityFieldsResult.offline(CategoryCapabilitySet set) =>
      CapabilityFieldsResult(
        fields: capabilityFieldsFor(set),
        source: CapabilityFieldsSource.offlineFallback,
      );

  final List<CapabilityFieldSpec> fields;
  final CapabilityFieldsSource source;

  bool get isOffline => source == CapabilityFieldsSource.offlineFallback;
}

/// Loads the capability field set from the backend, falling back offline.
///
/// The server's answer WINS. The local table exists so an offline or
/// not-yet-configured build still renders a usable form instead of an error —
/// but a field the server declared that this build does not know about is still
/// rendered, from the server's own description, rather than dropped. That
/// direction matters: dropping it would silently hide a field the shopkeeper was
/// supposed to fill in.
class CapabilityFieldsRepository {
  CapabilityFieldsRepository({required this.client});

  final ApiClient client;

  Future<CapabilityFieldsResult> load(
    String categoryCode, {
    String? businessType,
  }) async {
    final set = resolveCategoryCapabilities(categoryCode, businessType);

    try {
      final response = await client.get(
        ApiEndpoints.businessCategoryFields(
          categoryCode,
          businessType: businessType,
        ),
      );
      final data = response.data;
      if (data is! Map) return CapabilityFieldsResult.offline(set);
      return CapabilityFieldsResult(
        fields: fieldsFromServer(
          data,
          fallback: capabilityFieldsFor(set),
          known: capabilityFieldsFor(set),
        ),
        source: CapabilityFieldsSource.server,
      );
    } catch (_) {
      // Any failure — offline, 5xx, malformed body — resolves to the built-in
      // table rather than throwing, because a registration form that refuses to
      // open is worse than one that opens with the previous build's fields.
      return CapabilityFieldsResult.offline(set);
    }
  }

  /// Merge the server's field list with this build's presentation details.
  ///
  /// The backend owns which fields exist, their order, labels, kinds and
  /// required flags. This build owns icons, hints and max-length presentation.
  /// A server field with no local twin is rendered from the server's own data —
  /// inventing nothing, and dropping nothing.
  ///
  /// The one case that is NOT treated as the server's answer is a body with no
  /// usable `fields` list at all: that is a broken response, and quietly showing
  /// nothing would look identical to a category that legitimately has no fields.
  /// Falling back to the built-in table is the recoverable option there.
  @visibleForTesting
  static List<CapabilityFieldSpec> fieldsFromServer(
    Map<dynamic, dynamic> data, {
    required List<CapabilityFieldSpec> fallback,
    required List<CapabilityFieldSpec> known,
  }) {
    final raw = data['fields'];
    // Not a list: the contract was broken, so this is not the server's answer.
    if (raw is! List) return fallback;
    // An explicit empty list IS the server's answer. A service category is
    // allowed to declare no fields, and treating that as malformed re-invented
    // the local table — showing inputs for a category the backend deliberately
    // left blank.
    if (raw.isEmpty) return const <CapabilityFieldSpec>[];

    final byKey = {for (final spec in known) spec.key: spec};
    final merged = <CapabilityFieldSpec>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final key = (entry['key'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      final local = byKey[key];
      merged.add(
        CapabilityFieldSpec(
          key: key,
          label: (entry['label'] ?? local?.label ?? key).toString(),
          kind: _kindFromWire(entry['kind']?.toString(), local?.kind),
          icon: local?.icon ?? _fallbackIcon,
          hint: local?.hint,
          required: entry['required'] == true,
          maxLength: local?.maxLength,
          options: _optionsFrom(entry['options'], local?.options),
          // Local shape rules are kept, but the server's `required` overrides
          // the local one: it is the authority on what must be filled in.
          validate: local?.validate,
        ),
      );
    }
    // The server said "you have fields" and none of them could be read, which
    // is the same broken-contract situation as a missing list.
    return merged.isEmpty ? fallback : List.unmodifiable(merged);
  }

  static CapabilityFieldKind _kindFromWire(
    String? raw,
    CapabilityFieldKind? local,
  ) {
    switch (raw?.trim().toUpperCase()) {
      case 'MULTILINE':
        return CapabilityFieldKind.multiline;
      case 'NUMBER':
        return CapabilityFieldKind.number;
      case 'CHOICE':
        return CapabilityFieldKind.choice;
      case 'TEXT':
        return CapabilityFieldKind.text;
      default:
        // An unknown future kind degrades to the local guess, then to text —
        // never to a crash on a shipping app.
        return local ?? CapabilityFieldKind.text;
    }
  }

  static List<String> _optionsFrom(dynamic raw, List<String>? local) {
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList(growable: false);
    }
    return local ?? const <String>[];
  }

  /// A neutral icon for a field this build has never seen.
  static const IconCodex _fallbackIcon = 'tune';

  /// Persist the values for a shop.
  ///
  /// [fields] is the list the backend actually declared, not one re-derived from
  /// this build's capability table. Re-deriving silently dropped any field the
  /// server asked for that this build has no local twin for — the shopkeeper saw
  /// the input, filled it in, and watched it vanish on save.
  ///
  /// Returns the field keys the backend refused, or `{'__': message}` when the
  /// whole request failed, so the caller can show something honest rather than
  /// a silent no-op.
  Future<Map<String, String>> save({
    required int shopId,
    required String categoryCode,
    required List<CapabilityFieldSpec> fields,
    String? businessType,
    required Map<String, String> values,
  }) async {
    final payload = submittedCapabilityValues(fields, values);
    if (payload.isEmpty) return const {};

    try {
      final response = await client.put(
        ApiEndpoints.shopCapabilityFields(shopId),
        body: {
          'category_code': categoryCode,
          // Null-aware rather than a conditional `if`: an absent business type
          // must not be sent as an empty string, which the backend would treat
          // as a different (unknown) type.
          ?businessType: businessType,
          'fields': payload,
        },
      );
      final data = response.data;
      if (data is Map && data['rejected'] is List) {
        return {
          for (final key in (data['rejected'] as List))
            '$key': 'This field is not part of your category',
        };
      }
      return const {};
    } catch (e) {
      debugPrint('[CAPABILITY_FIELDS] save failed: $e');
      return const {'__': 'Could not save these details. Please retry later.'};
    }
  }
}