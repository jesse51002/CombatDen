import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_header.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/scale_reveal.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/creator_avatar.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

// The video card scale-pops in a touch slower so it lands as the focal point
// before the chrome fills in around it.
const Duration _kVideoScaleDuration = Duration(milliseconds: 480);

/// The loaded video-recommendation surface — the portal-model ([GymVideoCard])
/// twin of the shared `VideoReccLayout` (which stays on the old `Video` model
/// for its other, out-of-feature consumers). Same reveal choreography: the card
/// lands first, then the titled header and the CTA slide in around it.
class RecVideoLayout extends StatelessWidget {
  const RecVideoLayout({
    super.key,
    required this.title,
    required this.card,
    required this.ctaLabel,
    required this.onCtaPressed,
    required this.onClose,
  });

  final String title;
  final GymVideoCard card;
  final String ctaLabel;
  final VoidCallback onCtaPressed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final headerDelay = _kVideoScaleDuration;
    final ctaDelay = headerDelay + CelebrationTimings.revealStagger;

    return AppScreenScaffold(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            StaggeredReveal(
              delay: headerDelay,
              child: VideoReccHeader(title: title, onClose: onClose),
            ),
            Expanded(
              child: Center(
                child: ScaleReveal(
                  duration: _kVideoScaleDuration,
                  child: VideoReccCard(
                    title: card.title,
                    metaLabel: card.metaLabel,
                    thumbnail: CachedNetworkImageProvider(card.thumbnailUrl),
                    creatorPfp: creatorAvatarProvider(card.channelAvatarUrl),
                  ),
                ),
              ),
            ),
            StaggeredReveal(
              delay: ctaDelay,
              child: AppPrimaryButton(
                text: ctaLabel,
                fullWidth: true,
                borderRadius: DesignConstants.radiusBig,
                onPressed: onCtaPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
