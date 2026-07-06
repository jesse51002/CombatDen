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
import 'package:crm/features/memberships/data/models/rank_member_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_progress_bar.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/promotion_dialog.dart';
import 'package:crm/shared/widgets/rank_belt_image.dart';

/// A single main rank's detail page — its belt hero plus the roster of
/// members currently on it, sectioned by sub-position, each promotable
/// through the shared [PromotionDialog]. Deep-linkable by rank id
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

  /// Flattens the roster into hero + section headers + member rows so the
  /// whole page is a single lazily-built, paginating scroll view.
  List<Object> _items() {
    final items = <Object>[];
    int? group;
    var started = false;
    for (final m in widget.state.members) {
      if (!started || m.currentSubIndex != group) {
        items.add(_Header(_headerLabel(m.currentSubIndex)));
        group = m.currentSubIndex;
        started = true;
      }
      items.add(m);
    }
    return items;
  }

  String _headerLabel(int? subIndex) {
    if (subIndex == null) return 'No sub-rank';
    final label = widget.state.subRankType.subLabel(subIndex);
    return label.isEmpty ? 'Base position' : label;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final items = _items();

    return Stack(
      children: [
        ListView.builder(
          controller: _controller,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(DesignConstants.paddingBig),
          itemCount: 3 + items.length + (state.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _Hero(
                rank: state.rank,
                isTop: _isTop,
                memberCount: state.totalCount,
                onEdit: _edit,
                onDelete: _delete,
              );
            }
            if (index == 1) {
              return _SubRankBreakdown(
                rank: state.rank,
                subRankType: state.subRankType,
              );
            }
            if (index == 2) {
              return items.isEmpty ? const _EmptyRoster() : const SizedBox.shrink();
            }
            final itemIndex = index - 3;
            if (itemIndex >= items.length) {
              return const Padding(
                padding: EdgeInsets.all(DesignConstants.paddingSmall),
                child: Center(
                  child: AppSpinner(size: DesignConstants.spinnerSizeSmall),
                ),
              );
            }
            final item = items[itemIndex];
            if (item is _Header) return item;
            return _MemberRow(
              member: item as RankMemberRow,
              onPromote: () => _promote(item),
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
/// then the big belt, name, threshold, and the count of members
/// currently on the rank.
class _Hero extends StatelessWidget {
  final MainRank rank;
  final bool isTop;
  final int memberCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _Hero({
    required this.rank,
    required this.isTop,
    required this.memberCount,
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
                  Text(
                    '$memberCount ${memberCount == 1 ? 'member' : 'members'} '
                    'on this rank',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text3rd,
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

class _Header extends StatelessWidget {
  final String label;

  const _Header(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: DesignConstants.spacingBig,
        bottom: DesignConstants.spacingMedium,
      ),
      child: Text(
        label,
        style: DesignConstants.h3.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final RankMemberRow member;
  final VoidCallback onPromote;

  const _MemberRow({required this.member, required this.onPromote});

  @override
  Widget build(BuildContext context) {
    final denom = member.stepDenominator;
    final eligible = denom != null && denom > 0 && member.classesSince >= denom;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingMedium,
      ),
      child: Row(
        spacing: DesignConstants.spacingLarge,
        children: [
          InstructorAvatar(
            photoUrl: member.avatarUrl,
            name: member.name,
            diameter: 32,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text(
                  member.name,
                  style: DesignConstants.p,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                RankProgressBar(
                  done: member.classesSince,
                  target: denom,
                  eligible: eligible,
                ),
              ],
            ),
          ),
          AppOutlineButton(
            text: 'Promote',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: onPromote,
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
