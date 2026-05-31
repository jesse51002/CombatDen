import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/features/gym/data/gym_detail.dart';
import 'package:mobile_app/features/gym/data/gym_repository.dart';
import 'package:mobile_app/features/rewards/data/reward.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/reward_slide.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rewards/rewards_body.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_scaffold.dart';

/// Fourth card in the post-class flow — celebrates rewards unlocked.
class RewardsCardScreen extends StatefulWidget {
  const RewardsCardScreen({super.key});

  @override
  State<RewardsCardScreen> createState() => _RewardsCardScreenState();
}

class _RewardsCardScreenState extends State<RewardsCardScreen> {
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
      body: _RewardsCardBody(controller: _controller),
      ctaLabel: 'Continue',
      onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      ),
      onCtaPressed: () => Navigator.of(
        context,
      ).pushReplacementNamed(AppRoutes.postClassWins),
    );
  }
}

/// Feeds the carousel the active gym's **live** rewards from the
/// VideoService, falling back to the bundled CombatDen rewards when the
/// fetch fails or the gym has none — so the celebration always plays and
/// the user can always reach "Continue". Title / subtitle / featured index
/// are presentation chrome and stay sourced from [mockRewardsStats].
class _RewardsCardBody extends StatelessWidget {
  const _RewardsCardBody({required this.controller});

  final PostClassController controller;

  List<RewardSlide> get _fallbackSlides =>
      mockRewardsStats.items.map(RewardSlide.fromMock).toList();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GymDetail>(
      future: GymRepository.instance.detail(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const RewardsLoadStatus(null);
        }
        final List<RewardSlide> slides;
        if (snapshot.hasError) {
          slides = _fallbackSlides;
        } else {
          final rewards = snapshot.data?.rewards ?? const <Reward>[];
          slides = rewards.isEmpty
              ? _fallbackSlides
              : rewards.map(RewardSlide.fromReward).toList();
        }
        return RewardsBody(
          slides: slides,
          title: mockRewardsStats.title,
          subtitle: mockRewardsStats.subtitle,
          featuredIndex: mockRewardsStats.featuredIndex,
          controller: controller,
        );
      },
    );
  }
}
