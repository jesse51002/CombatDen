import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rank/rank_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Second card in the post-class flow — celebrates rank progress.
class RankScreen extends StatefulWidget {
  const RankScreen({super.key});

  @override
  State<RankScreen> createState() => _RankScreenState();
}

class _RankScreenState extends State<RankScreen> {
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
      body: RankBody(
        stats: mockRankStats,
        controller: _controller,
      ),
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
