import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';
import 'package:mobile_app/features/stats/data/celebration_stats_builder.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rank/rank_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Final card in the post-class flow — celebrates the member's live rank and
/// progress toward the next step. Closing / continuing both return home.
///
/// The flow no longer ROUTES here when the gym runs no rank ladder or the
/// member holds no rank: `celebration_flow.dart` composes the card out, so the
/// preceding card ends the flow itself instead of handing off to a blank
/// frame. The self-skip below stays as the DEEP-LINK backstop (PR 3's
/// after-class push can land straight on this route).
class RankScreen extends StatefulWidget {
  const RankScreen({super.key});

  @override
  State<RankScreen> createState() => _RankScreenState();
}

class _RankScreenState extends State<RankScreen> {
  final _controller = PostClassController();
  bool _endScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toHome() => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      );

  @override
  Widget build(BuildContext context) {
    final data = ModalRoute.of(context)?.settings.arguments as CelebrationData? ??
        const CelebrationData.empty();
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final profile = state.profile;
        // Still loading — hold on the background until the profile lands (the
        // flow only reaches here after it has loaded, so this is transient).
        if (profile == null) {
          return ColoredBox(color: DesignConstants.backgroundColor);
        }
        final stats =
            selectedMember.gymRankEnabled ? buildRankStats(profile) : null;
        if (stats == null) {
          // Loaded but ranks-off / unranked — no rank card; end the flow once
          // the frame is up (guarded so a rebuild doesn't schedule it twice).
          if (!_endScheduled) {
            _endScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _toHome();
            });
          }
          return ColoredBox(color: DesignConstants.backgroundColor);
        }
        // The rank card is last in every composed flow, so this resolves to
        // null and the CTA reads "Done" — but it is READ from the flow rather
        // than hardcoded, like its three siblings. A hardcoded "Continue" here
        // told the member there was another card and then dropped them home.
        final next = nextCelebrationCard(
          current: AppRoutes.postClassRank,
          hasRank: true,
          pointsBalance: profile.retention.pointsBalance,
        );
        return PostClassScaffold(
          controller: _controller,
          body: RankBody(stats: stats, controller: _controller),
          ctaLabel: celebrationCtaLabel(next),
          onClose: _toHome,
          onCtaPressed: next == null
              ? _toHome
              : () => Navigator.of(context)
                  .pushReplacementNamed(next, arguments: data),
        );
      },
    );
  }
}
