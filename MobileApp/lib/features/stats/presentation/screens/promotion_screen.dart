import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/profile/data/models/member_promotion.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';
import 'package:mobile_app/features/stats/presentation/widgets/promotion/promotion_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// The belt-promotion card — card 0 of the app-open celebration flow, and the
/// only screen in the app whose whole job is one moment.
///
/// It is NOT a post-class card and its copy never implies a class caused it:
/// staff promote from the ready-to-promote board, minutes to days after a
/// class and often in bulk, so there is no honest way to attribute a promotion
/// to an attendance. It fires from its own watermark on the profile the app
/// already loaded, whether or not the member trained.
///
/// When a class celebration is pending on the same open the promotion plays
/// FIRST and the post-class rank card is composed out — one belt moment per
/// app open (see `celebration_flow.dart`). Closing (the ✕) returns home.
///
/// The self-skip below is the DEEP-LINK backstop: composition is what stops
/// the normal flow ever landing here without a promotion, exactly the
/// asymmetry `RankScreen` documents.
class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  final _controller = PostClassController();
  bool _endScheduled = false;

  /// Captured on the FIRST build that has a profile and never re-read: a
  /// silent refresh landing mid-animation must not be able to swap the belts
  /// under the member. This is the screen-level half of "an entrance never
  /// re-fires on a silent refresh"; `PromotionBody`'s `initState`-driven
  /// controller is the widget-level half.
  MemberPromotion? _promotion;
  bool _captured = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toHome() => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      );

  MemberPromotion? _capture(MemberProfile profile) {
    if (_captured) return _promotion;
    _captured = true;
    _promotion = profile.latestPromotion ?? _debugPreview(profile);
    return _promotion;
  }

  /// DEBUG-ONLY. The identity sheet's `Belt promotion` row opens this route on
  /// a member whose profile carries no promotion, and a trigger that silently
  /// does nothing is useless — so it previews the FIRST-ASSIGNMENT state with
  /// the member's own real current belt. Fabricating a fake belt would be a
  /// lie; this is the honest middle. With no rank at all it falls through to
  /// the self-skip. Compiled out of release builds (`kDebugMode` is a const).
  MemberPromotion? _debugPreview(MemberProfile profile) {
    if (!kDebugMode) return null;
    final rank = profile.rank;
    if (rank == null) return null;
    final sub = rank.subLabel?.trim() ?? '';
    return MemberPromotion(
      activityId: 'debug-preview',
      promotedAt: DateTime.now(),
      newRankName: sub.isEmpty ? rank.name : '${rank.name} · $sub',
      newImageUrl: rank.imageUrl,
    );
  }

  void _scheduleEnd() {
    if (_endScheduled) return;
    _endScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _toHome();
    });
  }

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
        final promotion = _capture(profile);
        // `new_rank_name` is the one string the copy cannot do without. The
        // detector already marks such a row rather than showing it, so this is
        // the deep-link backstop for the same case.
        final name = promotion?.newRankName?.trim() ?? '';
        if (promotion == null ||
            name.isEmpty ||
            !selectedMember.gymRankEnabled) {
          _scheduleEnd();
          return ColoredBox(color: DesignConstants.backgroundColor);
        }
        final next = nextCelebrationCard(
          current: AppRoutes.promotion,
          data: data,
          hasRank: profile.rank != null,
          pointsBalance: profile.retention.pointsBalance,
        );
        return PostClassScaffold(
          controller: _controller,
          body: PromotionBody(promotion: promotion, controller: _controller),
          // READ from the flow, never hardcoded: with no class pending the
          // promotion is the ONLY card, and its CTA has to say "Done".
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
