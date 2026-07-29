import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';

/// A secondary line naming a gym: its logo tile beside its name.
///
/// When the gym has no `logo_url` (or it fails to load) the tile is omitted
/// entirely rather than replaced by a placeholder — identical placeholders on
/// every row add noise and disambiguate nothing.
///
/// Shared so the profile picker row and the identity sheet's current-member
/// header render the gym identically.
class GymLine extends StatelessWidget {
  const GymLine({super.key, required this.gymName, this.gymLogoUrl});

  final String gymName;
  final String? gymLogoUrl;

  @override
  Widget build(BuildContext context) {
    final logo = gymLogoUrl;
    final name = Flexible(
      child: Text(
        gymName,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (logo == null || logo.isEmpty) {
      return Row(mainAxisSize: MainAxisSize.min, children: [name]);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              DesignConstants.spacingSmall,
            ),
            child: CachedNetworkImage(
              imageUrl: logo,
              width: DesignConstants.iconSizeSm,
              height: DesignConstants.iconSizeSm,
              fit: BoxFit.cover,
              placeholder: (_, _) => const SizedBox(
                width: DesignConstants.iconSizeSm,
                height: DesignConstants.iconSizeSm,
              ),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        name,
      ],
    );
  }
}
