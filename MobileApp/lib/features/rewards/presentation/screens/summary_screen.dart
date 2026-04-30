import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_header.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// Post-class "Drill of the Day" screen — same layout as the post-booking
/// `VideoReccScreen`, just a different video.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const video = mockDrillOfTheDay;
    return AppScreenScaffold(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            VideoReccHeader(
              title: 'Drill of the Day',
              onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.home,
                (r) => false,
              ),
            ),
            Expanded(
              child: Center(
                child: VideoReccCard(
                  title: video.title,
                  metaLabel: video.metaLabel,
                  thumbnailAsset: video.thumbnailAsset,
                  creatorPfpAsset: video.creatorPfpAsset,
                ),
              ),
            ),
            AppPrimaryButton(
              text: 'Book your next class',
              fullWidth: true,
              borderRadius: DesignConstants.radiusBig,
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                AppRoutes.home,
                (r) => false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
