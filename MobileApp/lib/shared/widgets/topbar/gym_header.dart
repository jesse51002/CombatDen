import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/customization/widgets/branded_image.dart';

class GymHeader extends StatelessWidget {
  const GymHeader({
    super.key,
    required this.gymName,
    required this.logoAsset,
  });

  final String gymName;
  final String logoAsset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        BrandedImage(
          slot: CombatDenSlots.logoPrimary,
          fallback: ApiImage.asset(logoAsset),
          width: 100,
          height: 100,
          fit: BoxFit.cover,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(gymName, style: DesignConstants.h1),
            Icon(
              Symbols.expand_more_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text,
              size: DesignConstants.iconSizeSm,
            ),
          ],
        ),
      ],
    );
  }
}
