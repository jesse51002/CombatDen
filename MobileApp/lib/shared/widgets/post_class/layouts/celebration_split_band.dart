import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_close.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_cta.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_stage.dart';

/// `CelebrationFormat.splitBand` — the calmest of the five.
///
/// The celebration is contained in a band that bleeds to the top and
/// both side edges; the action sits alone on plain canvas beneath it.
/// The seam gives the figure its own surface, which is what keeps it
/// legible under a very busy tenant illustration, and it is the only
/// value that takes the action off the stage entirely.
///
/// The band is an `Expanded` against an intrinsic action block rather
/// than a fixed fraction. A true half-and-half split is not shippable:
/// the tallest card needs roughly 85% of the canvas before the layout
/// gets a vote, and there is nothing to move down into the lower half to
/// earn the space back, because the stat and caption live inside the
/// opaque body.
class CelebrationSplitBand extends StatelessWidget {
  const CelebrationSplitBand({super.key, required this.data});

  final CelebrationData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        Expanded(child: _Band(data: data)),
        Padding(
          padding: EdgeInsets.only(
            left: DesignConstants.screenHorizontalPadding,
            right: DesignConstants.screenHorizontalPadding,
            bottom: DesignConstants.spacingBig,
          ),
          child: CelebrationCta(data: data),
        ),
      ],
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.data});

  final CelebrationData data;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(DesignConstants.radiusBig),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.screenHorizontalPadding,
              vertical: DesignConstants.spacingLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingLarge,
              children: [
                ?data.header,
                Expanded(child: CelebrationStage(data: data)),
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
