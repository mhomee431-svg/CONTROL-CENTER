// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_details_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ProductActionController)
final productActionControllerProvider = ProductActionControllerProvider._();

final class ProductActionControllerProvider
    extends $NotifierProvider<ProductActionController, void> {
  ProductActionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'productActionControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$productActionControllerHash();

  @$internal
  @override
  ProductActionController create() => ProductActionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$productActionControllerHash() =>
    r'829274f538e790f67154808dacba235e24996e96';

abstract class _$ProductActionController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
