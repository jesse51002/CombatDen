import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The class image.
///
/// Every [ClassItemLayout] renders exactly one of these — the size and
/// the crop move, the image never leaves. Give it either explicit
/// [width]/[height] or an [aspectRatio] to fill the width it is handed.
class ClassItemThumb extends StatelessWidget {
  const ClassItemThumb({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.aspectRatio,
    this.borderRadius,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final double? aspectRatio;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget image = Image(
      image: CachedNetworkImageProvider(imageUrl),
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => SizedBox(
        width: width,
        height: height,
        child: ColoredBox(color: DesignConstants.card),
      ),
    );
    if (aspectRatio != null) {
      image = AspectRatio(aspectRatio: aspectRatio!, child: image);
    }
    if (borderRadius == null) return image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius!),
      child: image,
    );
  }
}
