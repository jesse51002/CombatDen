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
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';
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
          itemCount: 2 + items.length + (state.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _Hero(
                rank: state.rank,
                isTop: _isTop,
                memberCount: state.totalCount,
              );
            }
            if (index == 1) {
              return items.isEmpty ? const _EmptyRoster() : const SizedBox.shrink();
            }
            final itemIndex = index - 2;
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
        if (state.isMutating)
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

/// The belt hero: back affordance, big belt, name, threshold, and the
/// count of members currently on the rank.
class _Hero extends StatelessWidget {
  final MainRank rank;
  final bool isTop;
  final int memberCount;

  const _Hero({
    required this.rank,
    required this.isTop,
    required this.memberCount,
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
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingMedium,
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          InstructorAvatar(
            photoUrl: member.avatarUrl,
            name: member.name,
            diameter: 32,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  member.name,
                  style: DesignConstants.p,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  member.stepDenominator == null ||
                          member.stepDenominator == 0
                      ? '${member.classesSince} classes attended'
                      : '${member.classesSince} / ${member.stepDenominator} '
                          'classes to next step',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text3rd,
                  ),
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
