import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';
import 'package:mobile_app/features/stats/data/celebration_stats_builder.dart';
import 'package:mobile_app/features/stats/presentation/widgets/points/points_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Second card in the post-class flow — celebrates the points earned (the
/// attended class's worth) counting up against the member's live balance.
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
    final data = ModalRoute.of(context)?.settings.arguments as CelebrationData? ??
        const CelebrationData.empty();
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        // This is the ONE card whose successor depends on an async answer —
        // the rewards gate primed at flow-push time — so it re-derives its CTA
        // if the catalog lands after first build. The other three don't need
        // it: streak's successor is always points, rewards' is rank-or-null,
        // and rank's is always null.
        return ListenableBuilder(
          listenable: CelebrationRewardsGate.instance,
          builder: (context, _) {
            final next = nextCelebrationCard(
              current: AppRoutes.postClassPoints,
              hasRank: state.profile?.rank != null,
              pointsBalance: state.profile?.retention.pointsBalance,
            );
            void toHome() => Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.home,
                  (r) => false,
                );
            return PostClassScaffold(
              controller: _controller,
              body: PointsBody(
                stats: buildPointsStats(state.profile, data),
                controller: _controller,
              ),
              ctaLabel: celebrationCtaLabel(next),
              onClose: toHome,
              onCtaPressed: next == null
                  ? toHome
                  : () => Navigator.of(context)
                      .pushReplacementNamed(next, arguments: data),
            );
          },
        );
      },
    );
  }
}
