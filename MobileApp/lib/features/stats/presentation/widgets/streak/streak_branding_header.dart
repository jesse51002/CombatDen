import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Streak screen's top branding: gym name + small logo, centered.
/// Mirrors the small `branding` row from the Figma frame.
class StreakBrandingHeader extends StatelessWidget {
  const StreakBrandingHeader({
    super.key,
    required this.gymName,
    required this.logoAsset,
  });

  final String gymName;
  final String logoAsset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          gymName,
          style: DesignConstants.h1.copyWith(color: DesignConstants.text2nd),
        ),
        Image.asset(logoAsset, width: 35, height: 35, fit: BoxFit.contain),
      ],
    );
  }
}
