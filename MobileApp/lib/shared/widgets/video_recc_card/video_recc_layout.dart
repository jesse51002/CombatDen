import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_header.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/scale_reveal.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

// The video card scale-pops in a touch slower so it lands as the focal
// point before the chrome fills in around it.
const Duration _kVideoScaleDuration = Duration(milliseconds: 480);

/// Shared full-screen scaffold for "Video Before Class" / "Drill of the
/// Day" / any future video-recommendation moment. The video card lands
/// first; only after it settles do the titled header and the primary
/// CTA slide in around it.
class VideoReccLayout extends StatelessWidget {
  const VideoReccLayout({
    super.key,
    required this.title,
    required this.video,
    required this.ctaLabel,
    required this.onCtaPressed,
    required this.onClose,
  });

  final String title;
  final MockVideo video;
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
                    title: video.title,
                    metaLabel: video.metaLabel,
                    thumbnailAsset: video.thumbnailAsset,
                    creatorPfpAsset: video.creatorPfpAsset,
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
