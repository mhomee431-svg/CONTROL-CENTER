import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class NetworkImageView extends StatelessWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;

  const NetworkImageView({
    super.key,
    required this.imageUrl,
    this.width = double.infinity,
    this.height = double.infinity,
    this.fit = BoxFit.cover,
    this.borderRadius = 8.0,
  });

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
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => Container(color: Colors.grey.shade200),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }
}
