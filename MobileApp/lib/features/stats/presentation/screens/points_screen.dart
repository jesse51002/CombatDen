import 'package:flutter/material.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/points/points_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Third card in the post-class flow — celebrates points earned.
class PointsScreen extends StatelessWidget {
  const PointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PostClassScaffold(
      body: PointsBody(stats: mockPointsStats),
      ctaLabel: 'Continue',
      onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
      onCtaPressed: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.postClassRewards),
    );
  }
}
