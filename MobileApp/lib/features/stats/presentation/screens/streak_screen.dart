import 'package:flutter/material.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_body.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_branding_header.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// First card in the post-class flow — celebrates the user's weekly streak.
class StreakScreen extends StatelessWidget {
  const StreakScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PostClassScaffold(
      header: StreakBrandingHeader(
        gymName: mockGymGlobalMma.name,
        logoAsset: mockGymGlobalMma.logoAsset,
      ),
      body: StreakBody(stats: mockStreakStats),
      ctaLabel: 'Continue',
      onCtaPressed: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.postClassRank),
    );
  }
}
