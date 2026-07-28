import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_close.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_cta.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_stage.dart';

/// `CelebrationFormat.centerHero` — the arrangement that ships today.
///
/// Header on top, the card's body centred in everything left over, the
/// action pinned full-width at the bottom, close in the top-right of the
/// screen inset. This reproduces the previous `PostClassScaffold`
/// rendering value for value, so a tenant with no layout slot sees no
/// change: the horizontal inset the scaffold used to apply is applied
/// here instead, because the other four values need the canvas edge.
class CelebrationCenterHero extends StatelessWidget {
  const CelebrationCenterHero({super.key, required this.data});

  final CelebrationData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: DesignConstants.spacingBig,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                ?data.header,
                Expanded(child: CelebrationStage(data: data)),
                CelebrationCta(data: data),
              ],
            ),
          ),
          if (data.onClose case final close?)
            Positioned(
              top: DesignConstants.spacingLarge,
              right: DesignConstants.spacingLarge,
              child: CelebrationClose(onClose: close),
            ),
        ],
      ),
    );
  }
}
