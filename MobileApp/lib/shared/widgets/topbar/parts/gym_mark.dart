import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

/// Sizes the gym mark can be rendered at across the shell formats.
enum GymMarkSize {
  /// The stacked topbar's hero mark.
  lg(100),

  /// The mark-only topbar.
  md(56),

  /// Inline beside the gym name in a single-row topbar.
  sm(28),

  /// Alongside promoted stats, where identity is secondary.
  xs(20);

  const GymMarkSize(this.extent);

  final double extent;
}

/// The tenant's logo, resolved from the customization with the bundled
/// asset as fallback. One mark, sized by the shell layout that composes
/// it, so every layout draws identity from the same place.
class GymMark extends StatelessWidget {
  const GymMark({
    super.key,
    required this.logoAsset,
    this.size = GymMarkSize.lg,
  });

  final String logoAsset;
  final GymMarkSize size;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: ThemeImage.image(
        CombatDenSlots.logoPrimary,
        fallback: ApiImage.asset(logoAsset),
      ),
      width: size.extent,
      height: size.extent,
      fit: BoxFit.contain,
    );
  }
}
