import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/customization/theme/theme_text.dart';
import 'package:mobile_app/features/videos/data/video_selectors.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_recc_flow.dart';

/// Post-class "Drill of the Day" screen — same layout as the post-booking
/// `VideoReccScreen`, fed by a live drill pick and different CTA copy.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VideoReccFlow(
      title: 'Drill of the Day',
      selectVideo: drillOfTheDay,
      ctaLabel: ThemeText.value(
        CombatDenSlots.bookNextClassCta,
        fallback: 'Book your next class',
      ),
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
