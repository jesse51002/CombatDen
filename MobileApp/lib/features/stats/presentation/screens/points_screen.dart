import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/points/points_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Third card in the post-class flow — celebrates points earned.
class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> {
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
      body: PointsBody(stats: mockPointsStats, controller: _controller),
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
