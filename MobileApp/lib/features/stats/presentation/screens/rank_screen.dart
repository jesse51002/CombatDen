import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/stats/data/celebration_stats_builder.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rank/rank_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Final card in the post-class flow — celebrates the member's live rank and
/// progress toward the next step. When the member holds no rank (ranks disabled
/// / unranked) there's nothing to celebrate here, so the flow ends straight to
/// home. Closing / continuing both return home.
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
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final profile = state.profile;
        // Still loading — hold on the background until the profile lands (the
        // flow only reaches here after it has loaded, so this is transient).
        if (profile == null) {
          return ColoredBox(color: DesignConstants.backgroundColor);
        }
        final stats = buildRankStats(profile);
        if (stats == null) {
          // Loaded but unranked — no rank card; end the flow once the frame
          // is up (guarded so a rebuild doesn't schedule it twice).
          if (!_endScheduled) {
            _endScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _toHome();
            });
          }
          return ColoredBox(color: DesignConstants.backgroundColor);
        }
        return PostClassScaffold(
          controller: _controller,
          body: RankBody(stats: stats, controller: _controller),
          ctaLabel: 'Continue',
          onClose: _toHome,
          onCtaPressed: _toHome,
        );
      },
    );
  }
}
