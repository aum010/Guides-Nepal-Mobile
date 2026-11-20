import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/config/app_config.dart';

/// Memory-aware cached image with a stable layout while loading and a
/// branded fallback when the URL fails or is empty.
class NetworkImageView extends StatelessWidget {
  const NetworkImageView({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.semanticsLabel,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.shimmerBase,
      alignment: Alignment.center,
      child: const Icon(Icons.landscape_outlined,
          color: AppColors.tertiary, size: 28),
    );

    // Uploaded photos arrive as `/uploads/...`; resolving here keeps every
    // image widget correct without each caller knowing the API origin.
    final resolved = (url == null || url!.isEmpty)
        ? url
        : AppConfig.resolveMedia(url!);

    final child = (resolved == null || resolved.isEmpty)
        ? placeholder
        : CachedNetworkImage(
            imageUrl: resolved,
            width: width,
            height: height,
            fit: fit,
            // Never fetch wildly oversized assets on mobile networks.
            maxWidthDiskCache: 1600,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
            fadeInDuration: const Duration(milliseconds: 220),
          );

    final wrapped = borderRadius != null
        ? ClipRRect(borderRadius: borderRadius!, child: child)
        : child;

    return Semantics(
      image: true,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel == null,
      child: wrapped,
    );
  }
}
