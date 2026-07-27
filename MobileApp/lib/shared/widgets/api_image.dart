import 'package:flutter/widgets.dart';

/// Resolves a bundled feature image to an [ImageProvider].
///
/// For **real, live feature content** (logos passed from data,
/// reward art, rank belts, class imagery, …) — intentionally NOT
/// part of the tenant-customization system and never touches it.
///
/// Returns a provider rather than a widget so the same asset works
/// in `Image(image: …)`, `DecorationImage`, `CircleAvatar`, and
/// canvas/`paintImage` without re-wrapping. Render with
/// `Image(image: ApiImage.asset('foo.png'), …)`.
///
/// `.asset` → `assets/images`, `.rewardAsset` → `assets/rewards`,
/// `.rankAsset` → `assets/ranks`.
class ApiImage {
  // Private constructor to prevent instantiation.
  ApiImage._();

  static ImageProvider asset(String fileName) =>
      AssetImage('assets/images/$fileName');

  static ImageProvider rewardAsset(String fileName) =>
      AssetImage('assets/rewards/$fileName');

  static ImageProvider rankAsset(String fileName) =>
      AssetImage('assets/ranks/$fileName');
}
