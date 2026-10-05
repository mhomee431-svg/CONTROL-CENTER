import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/data/capability_fields_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/shops/domain/capability_fields.dart';

/// The loaded field set plus where it came from.
class CapabilityFieldsState {
  const CapabilityFieldsState({required this.fields, required this.source});

  /// The closed form: nothing asked for, nothing shown.
  static const empty = CapabilityFieldsState(
    fields: <CapabilityFieldSpec>[],
    source: CapabilityFieldsSource.server,
  );

  final List<CapabilityFieldSpec> fields;
  final CapabilityFieldsSource source;

  /// True when the backend could not be reached and the built-in table was used.
  ///
  /// The screen shows a notice for this, because "saved" must never be implied
  /// for data the server never sent — a shopkeeper who filled in a service area
  /// and saw no warning would reasonably believe it was stored.
  bool get isOffline => source == CapabilityFieldsSource.offlineFallback;

  bool get isEmpty => fields.isEmpty;
}

final capabilityFieldsRepositoryProvider =
    Provider<CapabilityFieldsRepository>(
  (ref) => CapabilityFieldsRepository(client: ref.watch(apiClientProvider)),
);

/// The capability fields for one category/business-type pair.
///
/// Keyed by BOTH axes, because both change the answer: a tour operator and the
/// same shop typed as "Service" get different fields. A plain
/// [FutureProvider.family] rather than a notifier — this is read-only, and the
/// save path lives on the repository where it belongs.
final capabilityFieldsProvider =
    FutureProvider.family<CapabilityFieldsState,
        ({String category, String? businessType})>((ref, arg) async {
  // No category chosen yet: return empty rather than asking for nothing. Without
  // this the form would flash the previous category's fields on first build.
  if (arg.category.isEmpty) return CapabilityFieldsState.empty;

  final result = await ref.watch(capabilityFieldsRepositoryProvider).load(
        arg.category,
        businessType: arg.businessType,
      );
  return CapabilityFieldsState(
    fields: result.fields,
    source: result.source,
  );
});