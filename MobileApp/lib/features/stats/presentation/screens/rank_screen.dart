import 'package:flutter/material.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rank/rank_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Second card in the post-class flow — celebrates rank progress.
class RankScreen extends StatelessWidget {
  const RankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PostClassScaffold(
      body: RankBody(stats: mockRankStats),
      ctaLabel: 'Continue',
      onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
      onCtaPressed: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.postClassPoints),
    );
  }
}
