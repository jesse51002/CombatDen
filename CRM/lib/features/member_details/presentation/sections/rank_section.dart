import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/rank.dart';
import 'package:crm/features/member_details/presentation/dialogs/set_rank_dialog.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_color.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Member's rank: belt + real progress toward the next rank
/// (classes attended since the last promotion / the gym threshold),
/// with Promote / Change / Assign actions. The current rank comes
/// from the member payload; the ladder + enabled flag are a
/// read-only side fetch (per the documented member-detail pattern).
class RankSection extends StatefulWidget {
  final Rank? rank;
  final String gymId;
  final String memberId;

  /// Bumped by the bloc on every member mutation (the member-detail
  /// `refreshToken`). A change re-fetches the ladder + enabled flag,
  /// like the other documented side-read sections.
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

class _RankLadder {
  final List<RankFullResponse> ladder;
  final bool enabled;
  const _RankLadder({required this.ladder, required this.enabled});
}

class _RankSectionState extends State<RankSection> {
  late Future<_RankLadder> _future = _load();

  @override
  void didUpdateWidget(covariant RankSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      setState(() => _future = _load());
    }
  }

  Future<_RankLadder> _load() async {
    final repo = RanksRepository(apiClient: ApiClient());
    final results = await Future.wait([
      repo.listRanks(widget.gymId),
      repo.getRankEnabled(widget.gymId),
    ]);
    return _RankLadder(
      ladder: results[0] as List<RankFullResponse>,
      enabled: (results[1] as RankEnabledResponse).isRankEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RankLadder>(
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
          return _card(_UnrankedBody(ladder: data.ladder));
        }
        return _card(
          _RankedBody(
            rank: widget.rank!,
            ladder: data.ladder,
            enabled: data.enabled,
          ),
        );
      },
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

/// The member has a rank: belt + progress + actions.
class _RankedBody extends StatelessWidget {
  final Rank rank;
  final List<RankFullResponse> ladder;
  final bool enabled;

  const _RankedBody({
    required this.rank,
    required this.ladder,
    required this.enabled,
  });

  RankFullResponse? get _nextRank {
    final index = ladder.indexWhere((r) => r.rankId == rank.rankId);
    if (index < 0 || index >= ladder.length - 1) return null;
    return ladder[index + 1];
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextRank;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        _BeltRow(rank: rank),
        _RankProgress(rank: rank, atTop: next == null),
        if (enabled) ...[
          AppOutlineButton(
            fullWidth: true,
            borderRadius: DesignConstants.radiusSmall,
            text: next == null
                ? 'Highest rank achieved'
                : 'Promote to ${next.displayLabel}',
            onPressed: next == null
                ? null
                : () => context
                    .read<MemberDetailBloc>()
                    .add(const MemberRankChangeRequested(promote: true)),
          ),
          Center(
            child: TextButton(
              onPressed: () => SetRankDialog.show(
                context: context,
                bloc: context.read<MemberDetailBloc>(),
                ladder: ladder,
                currentRankId: rank.rankId,
              ),
              child: Text(
                'Change rank',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.primaryColor,
                ),
              ),
            ),
          ),
        ] else
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
  final List<RankFullResponse> ladder;

  const _UnrankedBody({required this.ladder});

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
          onPressed: () => SetRankDialog.show(
            context: context,
            bloc: context.read<MemberDetailBloc>(),
            ladder: ladder,
            currentRankId: null,
          ),
        ),
      ],
    );
  }
}

/// Belt glyph + main/sub name.
class _BeltRow extends StatelessWidget {
  final Rank rank;

  const _BeltRow({required this.rank});

  @override
  Widget build(BuildContext context) {
    final color = parseRankColor(rank.color) ?? DesignConstants.primaryColor;
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          Symbols.workspace_premium_sharp,
          color: color,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(rank.mainName, style: DesignConstants.h2),
              if (rank.subName != rank.mainName)
                Text(
                  rank.subName,
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

/// Real attendance progress toward the next rank: "X / Y classes"
/// (classes since the last promotion vs the gym-set threshold).
class _RankProgress extends StatelessWidget {
  final Rank rank;
  final bool atTop;

  const _RankProgress({required this.rank, required this.atTop});

  @override
  Widget build(BuildContext context) {
    if (atTop || rank.classesTillRankup == 0) {
      return Text(
        atTop ? 'Top of the ladder.' : 'No further progression.',
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    final done = rank.classesSinceRank;
    final target = rank.classesTillRankup;
    final ratio = (done / target).clamp(0.0, 1.0);
    final eligible = done >= target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          children: [
            Text(
              '$done / $target classes',
              style: DesignConstants.h3,
            ),
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
            backgroundColor:
                DesignConstants.text3rd.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}
