import 'package:flutter/material.dart';
import 'package:mobile_app/core/branding/brand.dart';

/// Drop-in replacement for `Image.asset` that resolves the asset folder from
/// the active [Brand] in [BrandScope]. Pass the bare filename (no folder
/// prefix), e.g. `BrandImage.asset('gym_logo_global_mma.png')`.
class BrandImage extends StatelessWidget {
  const BrandImage.asset(
    this.fileName, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
  });

  final String fileName;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final folder = BrandScope.of(context).assetFolder;
    return Image.asset(
      '$folder/$fileName',
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}
