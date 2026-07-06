import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/memberships/bloc/rank_detail/rank_detail_bloc.dart';
import 'package:crm/features/memberships/bloc/rank_detail/rank_detail_event.dart';
import 'package:crm/features/memberships/bloc/rank_detail/rank_detail_state.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/promotion_choice.dart';
import 'package:crm/features/memberships/data/models/rank_member_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/promotable_member_row.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/promotion_dialog.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// Fixed column widths for the "On this rank" counts ledger, so every
/// position's distribution bar starts and ends on the same x across
/// rows (the label + count columns are pinned, the bar flexes between).
const double _kCountLabelWidth = 88;
const double _kCountValueWidth = 32;

/// A single main rank's detail page — its belt hero, an "On this rank"
/// counts summary (total + per-sub-position headcount), the per-step
/// progression breakdown, and a flat, proximity-sorted roster of the
/// members currently on it (closest to their next leaf first — the same
/// order and row as the ready-to-promote board), each promotable inline
/// or through the shared [PromotionDialog]. Deep-linkable by rank id
/// (`/memberships/ranks/detail/<id>`), self-provides its repository +
/// [RankDetailBloc].
class RankDetailScreen extends StatelessWidget {
  const RankDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mainRankId =
        ModalRoute.of(context)?.settings.arguments as String? ?? '';
    final gymId = selectedGym.gymId ?? '';

    return RepositoryProvider<RanksRepository>(
      create: (_) => RanksRepository(apiClient: ApiClient()),
      child: BlocProvider<RankDetailBloc>(
        create: (ctx) => RankDetailBloc(
          repository: ctx.read<RanksRepository>(),
        )..add(RankDetailInitRequested(gymId: gymId, rankId: mainRankId)),
        child: AppShell(
          activeRoute: AppRoutes.memberships,
          child: _RankDetailView(gymId: gymId, rankId: mainRankId),
        ),
      ),
    );
  }
}

class _RankDetailView extends StatelessWidget {
  final String gymId;
  final String rankId;

  const _RankDetailView({required this.gymId, required this.rankId});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RankDetailBloc, RankDetailState>(
      listenWhen: (prev, curr) =>
          curr is RankDetailLoaded &&
          (curr.actionError != null ||
              (prev is RankDetailLoaded &&
                  curr.actionSuccessCount != prev.actionSuccessCount)),
      listener: (context, state) {
        if (state is! RankDetailLoaded) return;
        final error = state.actionError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error ?? 'Member promoted.',
              style: DesignConstants.p.copyWith(color: DesignConstants.onAccent),
            ),
            backgroundColor:
                error != null ? DesignConstants.badRed : DesignConstants.goodGreen,
          ),
        );
      },
      builder: (context, state) {
        return switch (state) {
          RankDetailInitial() ||
          RankDetailLoading() =>
            const Center(child: AppSpinner()),
          RankDetailError() => _ErrorView(
              message: state.message,
              onRetry: () => context.read<RankDetailBloc>().add(
                    RankDetailInitRequested(gymId: gymId, rankId: rankId),
                  ),
            ),
          RankDetailLoaded() => _Loaded(state: state),
        };
      },
    );
  }
}

class _Loaded extends StatefulWidget {
  final RankDetailLoaded state;

  const _Loaded({required this.state});

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  final ScrollController _controller = ScrollController();

  /// True while a repository-direct delete is in flight (the promote
  /// path has its own `state.isMutating`); both drive the scrim overlay.
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final state = widget.state;
    if (state.isLoadingMore || state.hasReachedEnd) return;
    if (_controller.offset >= _controller.position.maxScrollExtent * 0.8) {
      context.read<RankDetailBloc>().add(const RankDetailNextPageRequested());
    }
  }

  bool get _isTop {
    final ladder = widget.state.ladder;
    return ladder.isNotEmpty &&
        ladder.last.rankId == widget.state.rank.rankId;
  }

  /// One-tap Promote: advance the member one leaf (the next sub-position,
  /// else the base of the next rank) — mirrors the ready-to-promote
  /// board's quick action.
  void _quickPromote(RankMemberRow member) {
    context.read<RankDetailBloc>().add(RankDetailPromoteRequested(
          memberId: member.memberId,
          choice: const PromoteNextSub(),
        ));
  }

  /// The overflow action: open the full [PromotionDialog] for any other
  /// move (skip to next major, set an explicit leaf).
  Future<void> _promote(RankMemberRow member) async {
    final bloc = context.read<RankDetailBloc>();
    final choice = await PromotionDialog.show(
      context: context,
      ladder: widget.state.ladder,
      subRankType: widget.state.subRankType,
      currentMainRankId: widget.state.rank.rankId,
      currentSubIndex: member.currentSubIndex,
    );
    if (choice == null) return;
    bloc.add(RankDetailPromoteRequested(
      memberId: member.memberId,
      choice: choice,
    ));
  }

  /// Opens the full-screen rank editor for this rank, then reloads the
  /// detail so the hero + breakdown reflect any saved change.
  Future<void> _edit() async {
    final bloc = context.read<RankDetailBloc>();
    await Navigator.of(context).pushNamed(
      AppRoutes.membershipsRankEditor,
      arguments: widget.state.rank,
    );
    bloc.add(RankDetailInitRequested(
      gymId: widget.state.gymId,
      rankId: widget.state.rank.rankId,
    ));
  }

  /// Confirms, then deletes this rank (the backend reassigns its members
  /// to a neighbour rank first) and pops back to the ladder. Repository-
  /// direct — the delete is a one-shot that ends this screen, mirroring
  /// the repository-direct editor.
  Future<void> _delete() async {
    final rank = widget.state.rank;
    final repository = context.read<RanksRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Delete ${rank.name}',
      message: 'Members on this rank move to a neighbouring rank. Its '
          '${rank.subRankCount} sub-position(s) go with it. This cannot '
          'be undone.',
      confirmLabel: 'Delete',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed) return;
    setState(() => _deleting = true);
    try {
      await repository.deleteRank(rank.rankId);
      navigator.pop();
    } catch (e, st) {
      log('Failed to delete rank', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete the rank. Please try again.',
            style:
                DesignConstants.p.copyWith(color: DesignConstants.onAccent),
          ),
          backgroundColor: DesignConstants.badRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final members = state.members;
    final hasMembers = members.isNotEmpty;
    // Leading blocks: hero, counts summary, progression, then either the
    // roster title (when populated) or the empty state — followed by the
    // flat, backend-proximity-sorted member rows and an optional trailing
    // load-more spinner. The list order is exactly as received; never
    // re-sorted or grouped here.
    const leadingCount = 4;
    final itemCount = leadingCount +
        (hasMembers ? members.length : 0) +
        (state.isLoadingMore ? 1 : 0);

    return Stack(
      children: [
        ListView.builder(
          controller: _controller,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            switch (index) {
              case 0:
                return _Hero(
                  rank: state.rank,
                  isTop: _isTop,
                  onEdit: _edit,
                  onDelete: _delete,
                );
              case 1:
                return _RankCounts(state: state);
              case 2:
                return _SubRankBreakdown(
                  rank: state.rank,
                  subRankType: state.subRankType,
                );
              case 3:
                return hasMembers
                    ? const _RosterTitle()
                    : const _EmptyRoster();
            }
            final rowIndex = index - leadingCount;
            if (rowIndex >= members.length) {
              return const Padding(
                padding: EdgeInsets.all(DesignConstants.paddingSmall),
                child: Center(
                  child: AppSpinner(size: DesignConstants.spinnerSizeSmall),
                ),
              );
            }
            final member = members[rowIndex];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hairline between rows (not above the first) — the row's
                // own vertical padding centres it, matching the ready
                // board's separated list.
                if (rowIndex > 0) const Hairline(),
                PromotableMemberRow(
                  imageUrl: _beltFor(state.rank, member),
                  avatarUrl: member.avatarUrl,
                  name: member.name,
                  rankLabel: _subLabelFor(state.subRankType, state.rank, member),
                  classesSince: member.classesSince,
                  stepDenominator: member.stepDenominator,
                  onQuickPromote: () => _quickPromote(member),
                  onOpenDialog: () => _promote(member),
                ),
              ],
            );
          },
        ),
        if (state.isMutating || _deleting)
          Positioned.fill(
            child: ColoredBox(
              color: DesignConstants.text.withValues(alpha: 0.08),
              child: const Center(child: AppSpinner()),
            ),
          ),
      ],
    );
  }
}

/// The belt hero: a top bar (back affordance + Edit / Delete actions),
/// then the big belt, name, and threshold. The member headcount lives in
/// the [_RankCounts] summary just below, not here.
class _Hero extends StatelessWidget {
  final MainRank rank;
  final bool isTop;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _Hero({
    required this.rank,
    required this.isTop,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final threshold = isTop
        ? 'Top of the ladder'
        : '${rank.classesToNextMajor} classes to next rank';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.all(DesignConstants.spacingSmall),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    Icon(
                      Symbols.arrow_back_sharp,
                      size: DesignConstants.iconSizeMedium,
                      weight: DesignConstants.iconWeight,
                      color: DesignConstants.text,
                    ),
                    Text('Ranks', style: DesignConstants.h3),
                  ],
                ),
              ),
            ),
            const Spacer(),
            AppOutlineButton(
              text: 'Edit',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: onEdit,
            ),
            const SizedBox(width: DesignConstants.spacingMedium),
            AppOutlineButton(
              text: 'Delete',
              borderRadius: DesignConstants.radiusSmall,
              borderColor: DesignConstants.badRed,
              textColor: DesignConstants.badRed,
              onPressed: onDelete,
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingBig,
          children: [
            RankBeltImage(
              imageUrl: rank.imageUrl,
              size: 120,
              radius: DesignConstants.radiusCard,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingSmall,
                children: [
                  Text(rank.name, style: DesignConstants.big2Bold),
                  Text(
                    threshold,
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The belt art for [member]'s current leaf: its per-sub image (an
/// override, else the main belt) when the member carries a sub-index,
/// else the rank's own belt. All members on a rank share the belt, so
/// this is derived from the rank, not the row.
String? _beltFor(MainRank rank, RankMemberRow member) {
  final sub = member.currentSubIndex;
  return sub != null ? rank.imageForSub(sub) : rank.imageUrl;
}

/// The trailing rank label for a roster row — just the sub-position
/// ("Base", "1 Stripe", "Div 2"), since every row here is on the same
/// main rank. `null` for a sub-less gym (no label to show).
String? _subLabelFor(RankSubType type, MainRank rank, RankMemberRow member) {
  if (type == RankSubType.none || rank.subRankCount == 0) return null;
  final label = type.subLabel(member.currentSubIndex ?? 0);
  return label.isEmpty ? 'Base' : label;
}

/// The "On this rank" counts summary: the total headcount and, when the
/// rank has sub-positions, a per-position distribution — one row per
/// position (`0..subRankCount-1`) with its label, a max-normalized bar,
/// and its count. A sub-less rank (or a gym with sub-positions off) shows
/// only the total. When the counts read is unavailable the total falls
/// back to the loaded member total and the breakdown is omitted.
class _RankCounts extends StatelessWidget {
  final RankDetailLoaded state;

  const _RankCounts({required this.state});

  @override
  Widget build(BuildContext context) {
    final rank = state.rank;
    final type = state.subRankType;
    final counts = state.subRankCounts;
    final total = counts?.totalCount ?? state.totalCount;
    final hasSubs = type != RankSubType.none && rank.subRankCount > 0;
    final showBreakdown = hasSubs && counts != null;

    final byIndex = counts?.countBySubIndex() ?? const <int, int>{};
    final maxCount =
        byIndex.values.fold<int>(0, (m, v) => v > m ? v : m);

    return Padding(
      padding: const EdgeInsets.only(top: DesignConstants.spacingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Row(
            children: [
              Text('On this rank', style: DesignConstants.h2),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$total ',
                      style: DesignConstants.h2Bold,
                    ),
                    TextSpan(
                      text: total == 1 ? 'member' : 'members',
                      style: DesignConstants.h2.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showBreakdown)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingLarge,
              children: [
                for (var i = 0; i < rank.subRankCount; i++)
                  _CountRow(
                    label: _positionLabel(type, i),
                    count: byIndex[i] ?? 0,
                    maxCount: maxCount,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _positionLabel(RankSubType type, int index) {
    final label = type.subLabel(index);
    return label.isEmpty ? 'Base' : label;
  }
}

/// One position row of the counts distribution: a fixed label column, a
/// flexible max-normalized bar, and the count (muted when zero, so empty
/// positions recede).
class _CountRow extends StatelessWidget {
  final String label;
  final int count;
  final int maxCount;

  const _CountRow({
    required this.label,
    required this.count,
    required this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    final factor =
        maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;
    final valueColor =
        has ? DesignConstants.text : DesignConstants.text3rd;

    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        SizedBox(
          width: _kCountLabelWidth,
          child: Text(
            label,
            style: DesignConstants.h3.copyWith(color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(DesignConstants.radiusSmall),
            child: LinearProgressIndicator(
              value: factor,
              minHeight: DesignConstants.spacingMedium,
              color: DesignConstants.primaryColor,
              backgroundColor: DesignConstants.primaryColor10,
            ),
          ),
        ),
        SizedBox(
          width: _kCountValueWidth,
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            style: DesignConstants.pSemibold.copyWith(color: valueColor),
          ),
        ),
      ],
    );
  }
}

/// The roster's section title, naming the list and its ordering (the
/// backend returns members closest-to-promotion first).
class _RosterTitle extends StatelessWidget {
  const _RosterTitle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: DesignConstants.spacingBig,
        bottom: DesignConstants.spacingMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text('Members', style: DesignConstants.h2),
          Text(
            'Ordered by who is closest to their next promotion.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}

/// The rank's per-step progression: one row per sub-position with its
/// label + the classes to advance through it, else a single row with the
/// main rank's own threshold when the belt has no sub-positions.
///
/// The per-step threshold is derived client-side as
/// `ceil(classesToNextMajor / subRankCount)`, matching how the backend
/// derives each member's `step_denominator` (an even ceil split of the
/// major threshold across the belt's positions).
class _SubRankBreakdown extends StatelessWidget {
  final MainRank rank;
  final RankSubType subRankType;

  const _SubRankBreakdown({required this.rank, required this.subRankType});

  int get _stepThreshold {
    final count = rank.subRankCount;
    if (count <= 0) return rank.classesToNextMajor;
    return (rank.classesToNextMajor + count - 1) ~/ count;
  }

  @override
  Widget build(BuildContext context) {
    final hasSubs =
        subRankType != RankSubType.none && rank.subRankCount > 0;

    final rows = <Widget>[];
    if (hasSubs) {
      final step = _stepThreshold;
      for (var i = 0; i < rank.subRankCount; i++) {
        final label = subRankType.subLabel(i);
        rows.add(_BreakdownRow(
          imageUrl: rank.imageForSub(i),
          label: label.isEmpty ? 'Base position' : label,
          threshold: step,
        ));
      }
    } else {
      rows.add(_BreakdownRow(
        imageUrl: rank.imageUrl,
        label: 'Advance to next rank',
        threshold: rank.classesToNextMajor,
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: DesignConstants.spacingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('Progression', style: DesignConstants.h2),
          Text(
            hasSubs
                ? 'Classes to earn each position within this belt.'
                : 'Classes to reach the next belt.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Hairline(),
                rows[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String? imageUrl;
  final String label;
  final int threshold;

  const _BreakdownRow({
    required this.imageUrl,
    required this.label,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingMedium,
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          RankBeltImage(imageUrl: imageUrl, size: 40),
          Expanded(
            child: Text(
              label,
              style: DesignConstants.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$threshold classes',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRoster extends StatelessWidget {
  const _EmptyRoster();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DesignConstants.paddingBig),
      child: Column(
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.groups_sharp,
            size: DesignConstants.iconSizeBig,
            color: DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            'No members on this rank yet',
            style: DesignConstants.h2.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            Icon(
              Symbols.error_sharp,
              size: DesignConstants.iconSizeBig,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.badRed,
            ),
            Text(
              'Failed to load rank',
              style: DesignConstants.h2.copyWith(color: DesignConstants.badRed),
              textAlign: TextAlign.center,
            ),
            Text(
              message,
              style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
              textAlign: TextAlign.center,
            ),
            AppOutlineButton(
              text: 'Retry',
              borderRadius: DesignConstants.radiusSmall,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
