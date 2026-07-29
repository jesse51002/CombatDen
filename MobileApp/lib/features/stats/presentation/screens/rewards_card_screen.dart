import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/rewards/data/models/reward_item.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_flow.dart';
import 'package:mobile_app/features/stats/data/celebration_rewards_gate.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/data/reward_slide.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Third card in the post-class flow — the gym's ACTIVE reward catalog, with
/// each slide showing whether the member can redeem it right now or how far
/// off they are. Falls back to the bundled rewards when the fetch fails, so
/// the flow always reaches the next card.
///
/// A gym with NO rewards, and a member who can't reach even the cheapest one,
/// never get here: `celebration_flow.dart` composes the card out up front.
///
/// **This screen never self-skips.** Once pushed it renders — always — which is
/// what makes the flow's "undecided gate → show" default safe: the worst case
/// is a card the member could have been spared, never one that appears and
/// vanishes. (`RankScreen`'s self-skip is the deliberate asymmetry: it can
/// render literally nothing, so it needs a deep-link backstop.)
///
/// Whether the rank card follows is read from the live profile: at a rank-off
/// gym, or for a member with no rank, this is the LAST card, so its CTA says
/// "Done" and returns home.
class RewardsCardScreen extends StatefulWidget {
  const RewardsCardScreen({super.key, this.repository});

  /// Injected by tests; the app builds the live member-portal repository.
  /// (Same seam as `VideoReccScreen` — no test may hit a live backend.)
  final MemberRewardsRepository? repository;

  @override
  State<RewardsCardScreen> createState() => _RewardsCardScreenState();
}

class _RewardsCardScreenState extends State<RewardsCardScreen> {
  final _controller = PostClassController();

  /// The catalog the flow's gate already fetched, mapped to slides — normally
  /// non-null, which removes both a second round trip and the load state.
  late final List<RewardSlide>? _primedSlides = _fromPrimedCatalog();

  /// Only built when the gate had nothing: a PR-3 deep link straight to this
  /// route, or a prime that failed.
  late final Future<List<RewardSlide>>? _slidesFuture =
      _primedSlides == null ? _loadSlides() : null;

  List<RewardSlide>? _fromPrimedCatalog() =>
      _slidesFor(CelebrationRewardsGate.instance.catalog);

  Future<List<RewardSlide>> _loadSlides() async {
    final gymId = selectedMember.gymId;
    final memberId = selectedMember.memberId;
    if (gymId == null || memberId == null) return _fallbackSlides;
    try {
      final repository = widget.repository ??
          MemberRewardsRepository(apiClient: ApiClient());
      final catalog =
          await repository.listCatalog(gymId: gymId, memberId: memberId);
      return _slidesFor(catalog) ?? _fallbackSlides;
    } catch (_) {
      return _fallbackSlides;
    }
  }

  /// A null catalog is UNDECIDED (fetch it); an empty one is decided-and-empty,
  /// which falls back to the bundled slides rather than an empty carousel.
  List<RewardSlide>? _slidesFor(List<RewardItem>? catalog) {
    if (catalog == null) return null;
    if (catalog.isEmpty) return _fallbackSlides;
    return catalog.map(RewardSlide.fromRewardItem).toList();
  }

  /// The bundled resilience fallback. Its costs are DEMO numbers, so every
  /// slide reports `isLive: false` and renders the unknown affordance — a
  /// shortfall measured against a demo price would be a false statement.
  List<RewardSlide> get _fallbackSlides =>
      mockRewardsStats.items.map(RewardSlide.fromMock).toList();

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
        final balance = state.profile?.retention.pointsBalance;
        final next = nextCelebrationCard(
          current: AppRoutes.postClassRewards,
          data: data,
          hasRank: state.profile?.rank != null,
          pointsBalance: balance,
        );
        void toHome() => Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.home,
              (r) => false,
            );
        return PostClassScaffold(
          controller: _controller,
          body: _body(balance),
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

  Widget _body(int? pointsBalance) {
    final primed = _primedSlides;
    if (primed != null) return _card(primed, pointsBalance);
    return FutureBuilder<List<RewardSlide>>(
      future: _slidesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const RewardsLoadStatus(null);
        }
        return _card(snapshot.data ?? _fallbackSlides, pointsBalance);
      },
    );
  }

  Widget _card(List<RewardSlide> slides, int? pointsBalance) => RewardsBody(
        view: buildRewardsCardView(
          slides: slides,
          pointsBalance: pointsBalance,
        ),
        controller: _controller,
      );
}
