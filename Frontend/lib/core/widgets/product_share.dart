import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Lightweight, dependency-free product share helper.
///
/// Composes a rich share text from the search-result data the caller already
/// has (name, price, shop, discount) and opens the native share sheet
/// immediately — sharing is never blocked by a network round-trip.
///
/// ```dart
/// onShare: () => shareProduct(
///   context,
///   productName: result.productName,
///   price: result.price,
///   mrp: result.mrp,
///   discountPercent: result.discountPercent,
///   shopName: result.shopName,
///   distanceInKm: result.distanceInKm,
/// );
/// ```
Future<void> shareProduct(
  BuildContext context, {
  required String productName,
  double? price,
  double? mrp,
  int? discountPercent,
  String? shopName,
  double? distanceInKm,
  String? variant,
  String? brand,
}) async {
  final buffer = StringBuffer('Check out $productName');

  if (variant != null && variant.isNotEmpty) buffer.write(' ($variant)');
  if (price != null) {
    buffer.write(' — available at ₹${price.toStringAsFixed(0)}');
    if (mrp != null && mrp > price) {
      buffer.write(' (MRP ₹${mrp.toStringAsFixed(0)})');
    }
    if (discountPercent != null && discountPercent > 0) {
      buffer.write(' · $discountPercent% OFF');
    }
  }
  if (shopName != null && shopName.isNotEmpty) {
    buffer.write(' at $shopName');
    if (distanceInKm != null) buffer.write(' (${distanceInKm.toStringAsFixed(1)} km)');
  }
  if (brand != null && brand.isNotEmpty) {
    buffer.write(' · $brand');
  }
  buffer.write(' — find it near you on Hyperlocal!');

  await SharePlus.instance.share(
    ShareParams(
      text: buffer.toString(),
      subject: 'Product: $productName',
    ),
  );
}