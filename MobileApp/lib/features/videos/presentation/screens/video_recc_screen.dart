import 'package:flutter/material.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_flow.dart';

/// Full-screen video recommendation surfaced after booking a class. Pulls the
/// most-viewed beginner/educational video from the live feed.
class VideoReccScreen extends StatelessWidget {
  const VideoReccScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VideoReccFlow(
      title: 'Video Before Class',
      selectVideo: videoBeforeClass,
      ctaLabel: 'Watch',
      onClose: () => Navigator.of(context).pop(),
      onCtaPressed: () => Navigator.of(context).pop(),
    );
  }
}
