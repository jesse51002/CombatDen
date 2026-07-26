import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';

/// The big-logo topbar variant's brand block: the gym's logo over its name.
/// Brand only — the member's identity control lives in the topbar's trailing
/// flank, not inside the title.
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
        Image(
          image: ThemeImage.image(
            CombatDenSlots.logoPrimary,
            fallback: ApiImage.asset(logoAsset),
          ),
          width: 100,
          height: 100,
          fit: BoxFit.contain,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                gymName,
                style: DesignConstants.h1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
