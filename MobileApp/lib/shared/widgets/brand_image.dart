import 'package:flutter/material.dart';
import 'package:mobile_app/core/branding/brand.dart';

/// Drop-in replacement for `Image.asset` that resolves the asset folder from
/// the active [Brand] in [BrandScope]. Pass the bare filename (no folder
/// prefix), e.g. `BrandImage.asset('gym_logo_global_mma.png')`.
///
/// `BrandImage.classAsset`, `BrandImage.videoAsset`, `BrandImage.rewardAsset`,
/// and `BrandImage.rankAsset` resolve to the global, non-brand-keyed
/// `assets/classes/`, `assets/videos/`, `assets/rewards/`, and `assets/ranks/`
/// folders. Class, video, reward, and rank art is per-deployment (swapped at
/// customer onboarding), not per-brand-flavor, so it does not vary with
/// [BrandScope].
class BrandImage extends StatelessWidget {
  const BrandImage.asset(
    this.fileName, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
  }) : _folder = null;

  const BrandImage.classAsset(
    this.fileName, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
  }) : _folder = 'assets/classes';

  const BrandImage.videoAsset(
    this.fileName, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
  }) : _folder = 'assets/videos';

  const BrandImage.rewardAsset(
    this.fileName, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
  }) : _folder = 'assets/rewards';

  const BrandImage.rankAsset(
    this.fileName, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
  }) : _folder = 'assets/ranks';

  final String fileName;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final String? _folder;

  @override
  Widget build(BuildContext context) {
    final folder = _folder ?? BrandScope.of(context).assetFolder;
    return Image.asset(
      '$folder/$fileName',
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
    );
  }
}
