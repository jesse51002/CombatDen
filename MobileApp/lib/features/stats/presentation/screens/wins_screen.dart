import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_stats_builder.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';
import 'package:theme_flutter/theme/theme_text.dart';

/// The LAST card in the post-class flow — the "Today's wins" recap, closing on
/// the nudge to book again.
///
/// It is **ungated**: its three tiles (classes this week, points earned, week
/// streak) are universal, so unlike the rewards and rank cards there is no gym
/// capability that could make it empty. `celebration_flow.dart` therefore
/// appends it to every composed flow.
///
/// It is also the one celebration screen that does **not** take its CTA from
/// `celebrationCtaLabel` — a card whose whole reason to exist is the nudge
/// can't end on "Done". The label is the themed
/// [CombatDenSlots.bookNextClassCta] slot (the same call `SummaryScreen`
/// makes), and it lands home like every other close.
class WinsScreen extends StatefulWidget {
  const WinsScreen({super.key});

  @override
  State<WinsScreen> createState() => _WinsScreenState();
}

class _WinsScreenState extends State<WinsScreen> {
  final _controller = PostClassController();

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
        return PostClassScaffold(
          controller: _controller,
          body: WinsBody(
            stats: buildWinsStats(state.profile, data),
            controller: _controller,
          ),
          ctaLabel: ThemeText.value(
            CombatDenSlots.bookNextClassCta,
            fallback: 'Book your next class',
          ),
          onClose: _toHome,
          // Booking lives on the home schedule, which is also where every other
          // card's close lands — so the nudge and the exit share one route.
          onCtaPressed: _toHome,
        );
      },
    );
  }
}
