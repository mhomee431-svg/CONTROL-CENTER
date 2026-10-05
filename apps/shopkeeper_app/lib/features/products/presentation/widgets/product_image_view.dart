import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/theme/app_colors.dart';

/// A resilient, self-contained product image widget supporting:
/// - Placeholder state (when no image is present)
/// - Loading state (during network fetch with smooth indicator)
/// - Loaded state (displaying remote URL or local file preview)
/// - Error fallback state (when URL is invalid, broken, or network fails)
/// - Replace and Remove user actions
class ProductImageView extends StatelessWidget {
  const ProductImageView({
    super.key,
    this.imageUrl,
    this.localPath,
    this.width = 72,
    this.height = 72,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.fit = BoxFit.cover,
    this.semanticLabel = 'Product image',
    this.excludeFromSemantics = false,
    this.isEditable = false,
    this.onReplace,
    this.onRemove,
    this.errorWidget,
    this.placeholderWidget,
    this.cacheWidth,
  });

  final String? imageUrl;
  final String? localPath;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final String semanticLabel;
  final bool isEditable;
  final VoidCallback? onReplace;
  final VoidCallback? onRemove;
  final Widget? errorWidget;
  final Widget? placeholderWidget;
  final int? cacheWidth;

  /// Decorative thumbnails (a list tile already names the product) set this so
  /// screen readers announce only the product name.
  final bool excludeFromSemantics;

  bool get _hasLocalPath => localPath != null && localPath!.trim().isNotEmpty;

  bool get _hasImageUrl => imageUrl != null && imageUrl!.trim().isNotEmpty;

  bool get _hasImage => _hasLocalPath || _hasImageUrl;

  Widget _buildPlaceholder(BuildContext context) {
    if (placeholderWidget != null) return placeholderWidget!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            // "Absent", not "broken" — a load failure gets its own
            // broken-image state, so the two must stay visually distinct.
            Icons.image_not_supported_outlined,
            size: (width * 0.38).clamp(18.0, 36.0),
            color: scheme.outline,
          ),
          if (height >= 70) ...[
            const SizedBox(height: 2),
            Text(
              appText(context).commonNoImage2,
              style: TextStyle(
                fontSize: 10,
                color: scheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    if (errorWidget != null) return errorWidget!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: (width * 0.38).clamp(18.0, 36.0),
            color: scheme.error,
          ),
          if (height >= 70) ...[
            const SizedBox(height: 2),
            Text(
              appText(context).commonFailedToLoad,
              style: TextStyle(
                fontSize: 9,
                color: scheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.outline),
      ),
    );
  }

  /// The decode width a local file should be sampled to: the box width scaled
  /// by the device pixel ratio, so the bitmap matches the pixels the widget
  /// really paints instead of the camera's full resolution.
  ///
  /// Clamped to at least 1px so a zero/infinite box can never produce an
  /// invalid `cacheWidth`, and capped so a very large display box still cannot
  /// ask for a needlessly huge decode.
  int _decodeWidthFor(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final target = (width * dpr).ceil();
    return target.clamp(1, 1024);
  }

  Widget _buildImageContent(BuildContext context) {
    if (_hasLocalPath) {
      // A picked verification / product photo is up to 2000px wide. Decoding it
      // at source resolution costs tens of megabytes of bitmap for a preview
      // box that is never larger than a card thumbnail, and the decoded bitmap
      // then sits in the image cache for as long as the screen lives (§111
      // "unbounded image caching"). Decode at the size this widget actually
      // paints — [cacheWidth] when the caller states it, otherwise the box
      // width at the current device pixel ratio.
      return Image.file(
        File(localPath!),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth ?? _decodeWidthFor(context),
        // Replacing a photo gives a NEW path, which Flutter treats as a
        // different image: without this the preview blanks to the placeholder
        // while the replacement decodes.
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        errorBuilder: (ctx, err, stack) => _buildError(context),
      );
    }

    if (_hasImageUrl) {
      final url = imageUrl!.trim();
      final uri = Uri.tryParse(url);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return _buildError(context);
      }

      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        // Same rule as the local-file branch above: `cacheWidth` when the caller
        // states it, otherwise the size this widget actually paints. A bare
        // `cacheWidth` left the network path (the common case — a catalog photo
        // served by the backend) decoding at FULL source resolution, so the
        // bitmap-cache cost the comment above describes was avoided only for
        // local files.
        cacheWidth: cacheWidth ?? _decodeWidthFor(context),
        // The backend serves presigned URLs, so the URL string rotates on every
        // refresh even though the picture is unchanged. Flutter treats a changed
        // provider as a new image, so without this every pull-to-refresh blanks
        // the decoded thumbnail back to the placeholder — a visible flash across
        // the whole product list. Keeping the last frame makes the swap seamless.
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return _buildLoading(context);
        },
        // `errorBuilder` already renders the fallback, so this must stay a
        // pure render: scheduling a `setState` here would re-run the error
        // path on every rebuild and spin `pumpAndSettle` forever.
        errorBuilder: (ctx, err, stack) => _buildError(context),
      );
    }

    return _buildPlaceholder(context);
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget = ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: _buildImageContent(context),
      ),
    );

    if (excludeFromSemantics) {
      imageWidget = ExcludeSemantics(child: imageWidget);
    }

    if (!isEditable) return imageWidget;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        imageWidget,
        Positioned(
          top: 2,
          right: 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReplace != null)
                Material(
                  color: AppColors.overlayBackdrop.withValues(alpha: 0.54),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onReplace,
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: AppColors.onOverlay,
                      ),
                    ),
                  ),
                ),
              if (_hasImage && onRemove != null) ...[
                const SizedBox(width: 4),
                Material(
                  color: AppColors.overlayBackdrop.withValues(alpha: 0.54),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.delete_outline,
                        size: 14,
                        color: AppColors.onOverlay,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
