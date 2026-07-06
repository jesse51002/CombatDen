import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/rank.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/promotion_dialog.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Member's rank: their belt image + real attendance progress toward the
/// next step (classes since their last promotion vs the leaf threshold),
/// with a single action that opens the shared [PromotionDialog].
///
/// The current rank comes from the member payload; the gym's ladder,
/// sub-rank type, and enabled flag are a read-only side fetch (the
/// documented member-detail side-read pattern — re-run whenever the
/// bloc's `refreshToken` changes).
class RankSection extends StatefulWidget {
  final Rank? rank;
  final String gymId;
  final String memberId;

  /// The member-detail `refreshToken`. A change re-fetches the ladder +
  /// enabled flag, like the other side-read sections.
  final int refreshKey;

  const RankSection({
    super.key,
    required this.rank,
    required this.gymId,
    required this.memberId,
    required this.refreshKey,
  });

  @override
  State<RankSection> createState() => _RankSectionState();
}

/// The gym-level rank context needed to render + drive the section.
class _RankData {
  final List<MainRank> ladder;
  final RankSubType subRankType;
  final bool enabled;

  const _RankData({
    required this.ladder,
    required this.subRankType,
    required this.enabled,
  });
}

class _RankSectionState extends State<RankSection> {
  late Future<_RankData> _future = _load();

  @override
  void didUpdateWidget(covariant RankSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      setState(() => _future = _load());
    }
  }

  Future<_RankData> _load() async {
    final repo = RanksRepository(apiClient: ApiClient());
    final results = await Future.wait([
      repo.listRanks(widget.gymId),
      repo.getRankEnabled(widget.gymId),
    ]);
    final ladder = results[0] as RankLadder;
    final enabled = results[1] as RankEnabledResponse;
    return _RankData(
      ladder: ladder.ranks,
      subRankType: ladder.subRankType,
      enabled: enabled.isRankEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberDetailBloc, MemberDetailState>(
      listenWhen: (prev, curr) =>
          prev is MemberDetailLoaded &&
          curr is MemberDetailLoaded &&
          prev.rankChangeSuccessCount != curr.rankChangeSuccessCount,
      listener: (context, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rank updated.',
              style:
                  DesignConstants.p.copyWith(color: DesignConstants.onAccent),
            ),
            backgroundColor: DesignConstants.goodGreen,
          ),
        );
      },
      child: FutureBuilder<_RankData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _card(
              const ErrorMessage(message: 'Could not load rank data.'),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            // Loading: don't flash an empty card for an unranked member.
            if (widget.rank == null) return const SizedBox.shrink();
            return _card(const Center(child: AppSpinner()));
          }
          if (widget.rank == null) {
            if (!data.enabled || data.ladder.isEmpty) {
              return const SizedBox.shrink();
            }
            return _card(_UnrankedBody(data: data));
          }
          return _card(_RankedBody(rank: widget.rank!, data: data));
        },
      ),
    );
  }

  Widget _card(Widget child) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Rank', style: DesignConstants.h2),
          child,
        ],
      ),
    );
  }
}

/// The member has a rank: belt + progress + a single manage action.
class _RankedBody extends StatelessWidget {
  final Rank rank;
  final _RankData data;

  const _RankedBody({required this.rank, required this.data});

  /// True when the member is on the last leaf of the last belt — nothing
  /// higher to promote to (correction/demotion is still possible).
  bool get _atTop {
    final ladder = data.ladder;
    if (ladder.isEmpty || ladder.last.rankId != rank.rankId) return false;
    final main = _mainRank;
    if (main == null) return false;
    return main.subRankCount == 0 || rank.subIndex == main.subRankCount - 1;
  }

  MainRank? get _mainRank {
    for (final r in data.ladder) {
      if (r.rankId == rank.rankId) return r;
    }
    return null;
  }

  Future<void> _manage(BuildContext context) async {
    final bloc = context.read<MemberDetailBloc>();
    final choice = await PromotionDialog.show(
      context: context,
      ladder: data.ladder,
      subRankType: data.subRankType,
      currentMainRankId: rank.rankId,
      currentSubIndex: rank.subIndex,
    );
    if (choice == null) return;
    bloc.add(MemberRankChangeRequested(choice));
  }

  @override
  Widget build(BuildContext context) {
    final atTop = _atTop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        _BeltRow(rank: rank),
        _RankProgress(rank: rank, atTop: atTop),
        if (data.enabled)
          AppOutlineButton(
            fullWidth: true,
            borderRadius: DesignConstants.radiusSmall,
            text: atTop ? 'Change rank' : 'Promote',
            onPressed: () => _manage(context),
          )
        else
          Text(
            'Rank system is disabled.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

/// No rank yet (gym ranks enabled, ladder non-empty): assign one.
class _UnrankedBody extends StatelessWidget {
  final _RankData data;

  const _UnrankedBody({required this.data});

  Future<void> _assign(BuildContext context) async {
    final bloc = context.read<MemberDetailBloc>();
    final choice = await PromotionDialog.show(
      context: context,
      ladder: data.ladder,
      subRankType: data.subRankType,
      currentMainRankId: null,
      currentSubIndex: null,
    );
    if (choice == null) return;
    bloc.add(MemberRankChangeRequested(choice));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          'No rank assigned.',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        AppOutlineButton(
          fullWidth: true,
          text: 'Assign rank',
          borderRadius: DesignConstants.radiusSmall,
          onPressed: () => _assign(context),
        ),
      ],
    );
  }
}

/// Belt image + main/sub name.
class _BeltRow extends StatelessWidget {
  final Rank rank;

  const _BeltRow({required this.rank});

  @override
  Widget build(BuildContext context) {
    final sub = rank.subLabel;
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        RankBeltImage(imageUrl: rank.imageUrl, size: 64),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(rank.name, style: DesignConstants.h2),
              if (sub != null && sub.isNotEmpty)
                Text(
                  sub,
                  style: DesignConstants.h3.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Real attendance progress toward the next leaf: "X / Y classes"
/// (classes since the last promotion vs the leaf threshold).
class _RankProgress extends StatelessWidget {
  final Rank rank;
  final bool atTop;

  const _RankProgress({required this.rank, required this.atTop});

  @override
  Widget build(BuildContext context) {
    if (atTop || rank.classesTillNextStep == 0) {
      return Text(
        atTop ? 'Top of the ladder.' : 'No further progression.',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    final done = rank.classesSinceRank;
    final target = rank.classesTillNextStep;
    final ratio = (done / target).clamp(0.0, 1.0);
    final eligible = done >= target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          children: [
            Text('$done / $target classes', style: DesignConstants.h3),
            const Spacer(),
            Text(
              eligible ? 'Eligible to promote' : 'To next rank',
              style: DesignConstants.pSmall.copyWith(
                color: eligible
                    ? DesignConstants.goodGreen
                    : DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: LinearProgressIndicator(
            value: ratio,
            color: eligible
                ? DesignConstants.goodGreen
                : DesignConstants.primaryColor,
            backgroundColor: DesignConstants.text3rd.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}
