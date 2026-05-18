import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_layout.dart';

/// Full-screen video recommendation surfaced after booking a class.
///
/// Mirrors Figma `VideoRecc`: a centered "Video Before Class" header with
/// a close button, the [VideoReccCard] body, and a primary Watch CTA at
/// the bottom. Accepts an optional [MockVideo] via route arguments and
/// falls back to [mockVideoBeforeClass].
class VideoReccScreen extends StatelessWidget {
  const VideoReccScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final video = args is MockVideo ? args : mockVideoBeforeClass;

    return VideoReccLayout(
      title: 'Video Before Class',
      video: video,
      ctaLabel: 'Watch',
      onClose: () => Navigator.of(context).pop(),
      onCtaPressed: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.videoDetail),
    );
  }
}
