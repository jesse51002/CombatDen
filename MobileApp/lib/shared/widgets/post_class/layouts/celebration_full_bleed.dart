import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_close.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_cta.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_scrim.dart';
import 'package:mobile_app/shared/widgets/post_class/parts/celebration_stage.dart';

/// `CelebrationFormat.fullBleed` — the highest-impact value.
///
/// No frame: the stage runs the whole canvas top to bottom and the
/// chrome floats over it on a scrim instead of reserving rows in a
/// column. It hands the body the largest box of the five, which is what
/// the intros that size themselves to their box (the points sphere, the
/// streak orbit, the giftbox burst) turn into reach. The most dependent
/// on illustration quality, which makes it the riskiest default for a
/// tenant whose generated imagery is weak.
///
/// Two things it deliberately does NOT do. It keeps the screen inset on
/// the stage's sides: an edge-to-edge stage puts the Wins tiles and the
/// Streak week strip flush against the screen edge, and a layout cannot
/// inset just the content of an opaque body. And it keeps
/// [kCelebrationCtaZone] clear beneath the stage, because Points and
/// Rank pin a caption to the bottom of their own box and a truly
/// unbounded stage would park it under the action.
class CelebrationFullBleed extends StatelessWidget {
  const CelebrationFullBleed({super.key, required this.data});

  final CelebrationData data;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(
              left: DesignConstants.screenHorizontalPadding,
              right: DesignConstants.screenHorizontalPadding,
              bottom: kCelebrationCtaZone,
            ),
            child: CelebrationStage(data: data),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: CelebrationScrim(),
        ),
        Positioned(
          left: DesignConstants.screenHorizontalPadding,
          right: DesignConstants.screenHorizontalPadding,
          bottom: DesignConstants.spacingBig,
          child: CelebrationCta(data: data),
        ),
        if (data.header case final header?)
          Positioned(
            top: DesignConstants.spacingLarge,
            left: DesignConstants.screenHorizontalPadding,
            // Stops short of the close so the two never collide.
            right: DesignConstants.spacingLarge * 2 +
                DesignConstants.iconSizeXl,
            child: header,
          ),
        if (data.onClose case final close?)
          Positioned(
            top: DesignConstants.spacingLarge,
            right: DesignConstants.spacingLarge,
            child: CelebrationClose(onClose: close, plated: true),
          ),
      ],
    );
  }
}
