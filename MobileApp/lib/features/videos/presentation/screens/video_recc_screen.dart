import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_header.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_card.dart';

/// Full-screen video recommendation surfaced after booking a class.
///
/// Mirrors Figma `VideoRecc`: a centered "Video Before Class" header with
/// a close button, the [VideoReccCard] body, and a primary Watch CTA at
/// the bottom. The screen accepts an optional [MockVideo] via route
/// arguments and falls back to [mockVideoBeforeClass].
class VideoReccScreen extends StatelessWidget {
  const VideoReccScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final video = args is MockVideo ? args : mockVideoBeforeClass;

    return AppScreenScaffold(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            VideoReccHeader(
              title: 'Video Before Class',
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(child: _Body(video: video)),
            AppPrimaryButton(
              text: 'Watch',
              fullWidth: true,
              borderRadius: DesignConstants.radiusBig,
              onPressed: () => Navigator.of(
                context,
              ).pushReplacementNamed(AppRoutes.videoDetail),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.video});

  final MockVideo video;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: VideoReccCard(
        title: video.title,
        metaLabel: video.metaLabel,
        thumbnailAsset: video.thumbnailAsset,
        creatorPfpAsset: video.creatorPfpAsset,
      ),
    );
  }
}
