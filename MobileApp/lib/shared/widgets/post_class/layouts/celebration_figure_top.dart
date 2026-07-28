import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_close.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_cta.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_stage.dart';

/// `CelebrationFormat.figureTop` — the earned figure at the top of the
/// read.
///
/// The frame opens tighter and the body settles against the TOP of the
/// stage instead of its centre, so on a screen opened at arm's length
/// the number is where the eye lands first. The action keeps the same
/// resting place it has in every other value.
///
/// The body is one opaque widget, so the doc's "illustration bleeds off
/// the bottom edge behind the CTA" is not reachable — a layout cannot
/// move a part of the body, and running the stage under the action would
/// hide the captions two of the cards pin to their own bottom edge. What
/// survives is the anchor: three of the five cards visibly ride up.
/// Points and Rank fill the stage in both states and are unmoved.
class CelebrationFigureTop extends StatelessWidget {
  const CelebrationFigureTop({super.key, required this.data});

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
            padding: EdgeInsets.only(
              top: DesignConstants.spacingLarge,
              bottom: DesignConstants.spacingBig,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingLarge,
              children: [
                ?data.header,
                Expanded(
                  child: CelebrationStage(
                    data: data,
                    alignment: Alignment.topCenter,
                  ),
                ),
                CelebrationCta(data: data),
              ],
            ),
          ),
          if (data.onClose case final close?)
            Positioned(
              top: DesignConstants.spacingLarge,
              right: DesignConstants.spacingLarge,
              child: CelebrationClose(onClose: close, plated: true),
            ),
        ],
      ),
    );
  }
}
