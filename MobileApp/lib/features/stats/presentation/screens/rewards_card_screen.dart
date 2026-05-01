import 'package:flutter/material.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Fourth card in the post-class flow — celebrates rewards unlocked.
class RewardsCardScreen extends StatefulWidget {
  const RewardsCardScreen({super.key});

  @override
  State<RewardsCardScreen> createState() => _RewardsCardScreenState();
}

class _RewardsCardScreenState extends State<RewardsCardScreen> {
  final _controller = PostClassController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PostClassScaffold(
      controller: _controller,
      body: RewardsBody(stats: mockRewardsStats, controller: _controller),
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
