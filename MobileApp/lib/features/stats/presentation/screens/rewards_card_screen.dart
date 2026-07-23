import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/rewards/data/repositories/member_rewards_repository.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/reward_slide.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Third card in the post-class flow — a motivational "rewards you can get"
/// carousel of the gym's ACTIVE catalog (member portal), falling back to the
/// bundled rewards when the fetch fails or the gym has none so the flow always
/// reaches the next card. Continues to the rank card.
class RewardsCardScreen extends StatefulWidget {
  const RewardsCardScreen({super.key});

  @override
  State<RewardsCardScreen> createState() => _RewardsCardScreenState();
}

class _RewardsCardScreenState extends State<RewardsCardScreen> {
  final _controller = PostClassController();
  late final Future<List<RewardSlide>> _slidesFuture = _loadSlides();

  Future<List<RewardSlide>> _loadSlides() async {
    final gymId = selectedMember.gymId;
    final memberId = selectedMember.memberId;
    if (gymId == null || memberId == null) return _fallbackSlides;
    try {
      final catalog = await MemberRewardsRepository(apiClient: ApiClient())
          .listCatalog(gymId: gymId, memberId: memberId);
      if (catalog.isEmpty) return _fallbackSlides;
      return catalog.map(RewardSlide.fromRewardItem).toList();
    } catch (_) {
      return _fallbackSlides;
    }
  }

  // Title / subtitle / featured index are presentation chrome; the bundled
  // items are the resilience fallback — both stay sourced from the demo config.
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
    return PostClassScaffold(
      controller: _controller,
      body: FutureBuilder<List<RewardSlide>>(
        future: _slidesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const RewardsLoadStatus(null);
          }
          return RewardsBody(
            slides: snapshot.data ?? _fallbackSlides,
            title: mockRewardsStats.title,
            subtitle: mockRewardsStats.subtitle,
            featuredIndex: mockRewardsStats.featuredIndex,
            controller: _controller,
          );
        },
      ),
      ctaLabel: 'Continue',
      onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
      onCtaPressed: () => Navigator.of(context).pushReplacementNamed(
        AppRoutes.postClassRank,
        arguments: data,
      ),
    );
  }
}
