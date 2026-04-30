import 'package:flutter/material.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Fourth card in the post-class flow — celebrates rewards unlocked.
class RewardsCardScreen extends StatelessWidget {
  const RewardsCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PostClassScaffold(
      body: RewardsBody(stats: mockRewardsStats),
      ctaLabel: 'Continue',
      onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
      onCtaPressed: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.postClassWins),
    );
  }
}
