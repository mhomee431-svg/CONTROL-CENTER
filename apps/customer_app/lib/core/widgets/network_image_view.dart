import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The five states a product/shop image can be in.
///
/// Distinguishing these matters because they mean different things to the
/// customer: a *missing* URL means the shop never uploaded a photo, whereas a
/// *broken* URL means a photo exists but cannot be fetched. Collapsing them
/// into one generic icon hides real data problems.
enum ImageLoadState {
  /// The URL is absent or blank — there is nothing to fetch.
  missing,

  /// A fetch is in flight.
  loading,

  /// The image decoded and is displayed.
  loaded,

  /// The fetch or decode failed (404, network, corrupt bytes).
  broken,
}

/// A resilient, cache-friendly network image.
///
/// Guarantees:
/// * **Never throws or crashes on a missing/blank/malformed URL.** The absent
///   case short-circuits before any network call is attempted, because handing
///   an empty string to an image loader is a common source of runtime errors.
/// * **Never requests a full-resolution decode for a small slot.** The decode
///   is bounded to the widget's layout size at the device pixel ratio, so a
///   4000px photo in a 100px card costs ~100px of RAM instead of ~60MB.
/// * **Caches efficiently.** `cached_network_image` serves repeats from memory
///   then disk, so scrolling a list does not re-download.
/// * **Has a bounded failure state.** A broken image degrades to a placeholder
///   rather than an infinite spinner.
class NetworkImageView extends StatelessWidget {
  /// The remote image location. Null, empty, or whitespace-only is treated as
  /// [ImageLoadState.missing] and rendered without any network request.
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;

  /// Optional widget shown in place of the built-in placeholder for the
  /// `missing`, `loading`, and `broken` states. When supplied it is used for
  /// all three so callers can match a bespoke layout; when omitted the widget
  /// falls back to its own icon-per-state rendering.
  final Widget? placeholder;

  const NetworkImageView({
    super.key,
    required this.imageUrl,
    this.width = double.infinity,
    this.height = double.infinity,
    this.fit = BoxFit.cover,
    this.borderRadius = 8.0,
    this.placeholder,
  });

  /// True when there is no usable URL to load.
  ///
  /// Blank strings are rejected because an empty `imageUrl` is a real value
  /// that reaches this widget from the API, not a programming error.
  bool get _hasNoUrl => (imageUrl ?? '').trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    // Memory hardening: bound the decoded (in-memory) image size to what the
    // slot actually needs at device pixel ratio. Without this, a 4000px hero
    // photo decoded into a 100px card can cost ~60MB of RAM per image and
    // quickly OOMs image-heavy screens.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final int? memCacheWidth = width.isFinite && width > 0
        ? (width * dpr).round()
        : null;
    final int? memCacheHeight = height.isFinite && height > 0
        ? (height * dpr).round()
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        // MISSING — short-circuit before the loader ever sees an empty URL.
        child: _hasNoUrl
            ? (placeholder ??
                  const _ImagePlaceholder(state: ImageLoadState.missing))
            : CachedNetworkImage(
                imageUrl: imageUrl!.trim(),
                width: width,
                height: height,
                fit: fit,
                memCacheWidth: memCacheWidth,
                memCacheHeight: memCacheHeight,
                // The disk cache needs the same bound. `memCacheWidth` only
                // limits what is held decoded in RAM; without these a 4000px
                // photo is still written to disk in full on first view, so
                // scrolling back and forth through 50 rows fills the cache with
                // full-resolution bytes that are never displayed at that size.
                maxWidthDiskCache: memCacheWidth,
                maxHeightDiskCache: memCacheHeight,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (context, url) =>
                    placeholder ??
                    const _ImagePlaceholder(state: ImageLoadState.loading),
                errorWidget: (context, url, error) =>
                    placeholder ??
                    const _ImagePlaceholder(state: ImageLoadState.broken),
              ),
      ),
    );
  }
}

/// The built-in visual for the non-loaded image states.
///
/// Every state renders a *static* icon (never an indeterminate spinner): a
/// spinner would keep scheduling frames for as long as a request is pending,
/// which both violates the "avoid endless spinners" guideline and prevents
/// `pumpAndSettle` from ever settling in widget tests when a network image
/// stays unresolved.
class _ImagePlaceholder extends StatelessWidget {
  final ImageLoadState state;

  const _ImagePlaceholder({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: switch (state) {
        // Request in flight — a static hourglass says "coming" without
        // animating forever.
        ImageLoadState.loading => Icon(
          Icons.hourglass_top_outlined,
          color: Colors.grey.shade500,
        ),
        // No URL was supplied — this is missing data, not a failure.
        ImageLoadState.missing => Icon(
          Icons.image_outlined,
          color: Colors.grey.shade500,
        ),
        // A URL exists but could not be fetched.
        ImageLoadState.broken => Icon(
          Icons.broken_image_outlined,
          color: Colors.grey.shade500,
        ),
        ImageLoadState.loaded => const SizedBox.shrink(),
      },
    );
  }
}
