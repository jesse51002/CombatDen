import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Fifth card in the post-class flow — recaps today's session wins, then
/// hands off to the Summary screen.
class WinsScreen extends StatelessWidget {
  const WinsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PostClassScaffold(
      body: WinsBody(stats: mockWinsStats),
      ctaLabel: 'Book your next class',
      onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
      onCtaPressed: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.summary),
    );
  }
}
