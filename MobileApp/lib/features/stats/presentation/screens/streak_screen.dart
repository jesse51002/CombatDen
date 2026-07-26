import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';
import 'package:mobile_app/features/stats/data/celebration_stats_builder.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// First card in the post-class flow — celebrates the member's live weekly
/// streak, this week's day strip, and the points the attended class was worth.
/// Continues to whatever card `celebration_flow.dart` says comes next for this
/// gym (wins removed from the flow).
class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
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
        final next = nextCelebrationCard(
          current: AppRoutes.postClassStreak,
          hasRank: state.profile?.rank != null,
        );
        void toHome() => Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.home,
              (r) => false,
            );
        return PostClassScaffold(
          controller: _controller,
          body: StreakBody(
            stats: buildStreakStats(state.profile, data),
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
  }
}
