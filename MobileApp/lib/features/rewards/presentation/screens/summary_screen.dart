import 'package:flutter/material.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/videos/data/mock_videos.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/video_recc_layout.dart';

/// Post-class "Drill of the Day" screen — same layout as the post-booking
/// `VideoReccScreen`, just a different video and CTA copy.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VideoReccLayout(
      title: 'Drill of the Day',
      video: mockDrillOfTheDay,
      ctaLabel: 'Book your next class',
      onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
      onCtaPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
    );
  }
}
