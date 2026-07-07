import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_bloc.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_event.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_state.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_tab_scaffold.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_enabled_section.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_ladder_section.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_sub_type_section.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/ready_to_promote_row.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

const List<String> _kRankViews = ['Rank ladder', 'Ready to promote'];

/// Ranks tab of the Gym screen.
///
/// The rank-system on/off toggle, the sub-rank style selector, and the
/// ladder/board view switcher sit at the top of the tab and **scroll with
/// the content** (nothing is pinned) — the whole tab is one scroll. When
/// the system is **off**, everything but the toggle is hidden; the ladder
/// is persisted server-side and reappears on re-enable, so nothing is
/// lost.
class RanksTab extends StatefulWidget {
  final String gymId;

  const RanksTab({super.key, required this.gymId});

  @override
  State<RanksTab> createState() => _RanksTabState();
}

class _RanksTabState extends State<RanksTab> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RanksBloc, RanksState>(
      // Surface a failed mutation as an error, and every committed
      // mutation (seed / enable toggle / sub-type / reorder — each bumps
      // mutationCount) as a green confirmation, so no ladder change ends
      // with just a spinner that quietly disappears.
      listenWhen: (prev, curr) =>
          curr is RanksLoaded &&
          (curr.actionError != null ||
              (prev is RanksLoaded &&
                  curr.mutationCount != prev.mutationCount)),
      listener: (context, state) {
        if (state is! RanksLoaded) return;
        final error = state.actionError;
        if (error != null) {
          showTabActionError(context, error);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Ranks updated.',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.onFill(DesignConstants.goodGreen),
                ),
              ),
              backgroundColor: DesignConstants.goodGreen,
            ),
          );
        }
      },
      builder: (context, state) {
        return switch (state) {
          RanksInitial() || RanksLoading() => const TabLoading(),
          RanksError() => TabError(
              message: state.message,
              onRetry: () => context
                  .read<RanksBloc>()
                  .add(RanksInitRequested(state.gymId)),
            ),
          RanksLoaded() => _loaded(context, state),
        };
      },
    );
  }

  Widget _loaded(BuildContext context, RanksLoaded state) {
    // Off: only the toggle, in a scroll for a consistent, non-jumpy tab.
    if (!state.isRankEnabled) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.screenHorizontalPadding,
        ).copyWith(bottom: DesignConstants.paddingBig),
        child: RankEnabledSection(state: state),
      );
    }

    // On: the header rides the TOP of whichever view is active so the
    // whole tab scrolls as one page (nothing pinned). Both views stay
    // alive in an IndexedStack so the board keeps its scroll position
    // across switches.
    final header = _TabHeader(
      state: state,
      selectedIndex: _view,
      onSelected: (i) => setState(() => _view = i),
    );
    // The ready-to-promote board runs on its own bloc; lift its provider
    // above the stack and reload it whenever the ladder mutates (seed /
    // create / delete / reorder / sub-type change) so its paginated list
    // never goes stale under a ladder change.
    return BlocProvider<ReadyToPromoteBloc>(
      create: (ctx) => ReadyToPromoteBloc(
        repository: ctx.read<RanksRepository>(),
      )..add(ReadyToPromoteInitRequested(widget.gymId)),
      child: BlocListener<RanksBloc, RanksState>(
        listenWhen: (prev, curr) =>
            prev is RanksLoaded &&
            curr is RanksLoaded &&
            curr.mutationCount != prev.mutationCount,
        listener: (ctx, _) => ctx
            .read<ReadyToPromoteBloc>()
            .add(ReadyToPromoteInitRequested(widget.gymId)),
        child: IndexedStack(
          index: _view,
          children: [
            _LadderBody(state: state, header: header),
            _ReadyView(header: header),
          ],
        ),
      ),
    );
  }
}

/// The always-at-the-top header: the on/off toggle, the sub-rank style
/// selector, and the ladder/board view switcher. Rendered inside each
/// view's scroll so it scrolls away with the content instead of pinning.
class _TabHeader extends StatelessWidget {
  final RanksLoaded state;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _TabHeader({
    required this.state,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          RankEnabledSection(state: state),
          RankSubTypeSection(state: state),
          ViewSwitcher(
            labels: _kRankViews,
            selectedIndex: selectedIndex,
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

/// The editable ladder surface — the header then the reorderable
/// main-rank ladder, all in one scroll.
class _LadderBody extends StatelessWidget {
  final RanksLoaded state;
  final Widget header;

  const _LadderBody({required this.state, required this.header});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.screenHorizontalPadding,
            ),
            child: RankLadderSection(state: state),
          ),
        ],
      ),
    );
  }
}

/// The ready-to-promote board — the header rides the top of the roster so
/// it scrolls with it.
class _ReadyView extends StatelessWidget {
  final Widget header;

  const _ReadyView({required this.header});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReadyToPromoteBloc, ReadyToPromoteState>(
      listenWhen: (prev, curr) =>
          curr is ReadyToPromoteLoaded &&
          (curr.actionError != null ||
              (prev is ReadyToPromoteLoaded &&
                  curr.actionSuccessCount != prev.actionSuccessCount)),
      listener: (context, state) {
        if (state is! ReadyToPromoteLoaded) return;
        if (state.actionError != null) {
          showTabActionError(context, state.actionError!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Member promoted.',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.onFill(DesignConstants.goodGreen),
                ),
              ),
              backgroundColor: DesignConstants.goodGreen,
            ),
          );
        }
      },
      builder: (context, state) {
        return switch (state) {
          ReadyToPromoteInitial() || ReadyToPromoteLoading() =>
            _headerThen(const TabLoading()),
          ReadyToPromoteError() => _headerThen(
              TabError(
                message: state.message,
                onRetry: () => context
                    .read<ReadyToPromoteBloc>()
                    .add(ReadyToPromoteInitRequested(state.gymId)),
              ),
            ),
          ReadyToPromoteLoaded() => _ReadyList(state: state, header: header),
        };
      },
    );
  }

  /// Loading / error: header at the top, the transient state filling the
  /// rest (there's nothing to scroll in those states yet).
  Widget _headerThen(Widget body) {
    return Column(
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }
}

class _ReadyList extends StatefulWidget {
  final ReadyToPromoteLoaded state;
  final Widget header;

  const _ReadyList({required this.state, required this.header});

  @override
  State<_ReadyList> createState() => _ReadyListState();
}

class _ReadyListState extends State<_ReadyList> {
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
    if (widget.state.isLoadingMore || widget.state.hasReachedEnd) return;
    if (_controller.offset >=
        _controller.position.maxScrollExtent * 0.8) {
      context
          .read<ReadyToPromoteBloc>()
          .add(const ReadyToPromoteNextPageRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    // Empty: header + the empty message, scrollable as one page.
    if (state.rows.isEmpty) {
      return ListView(
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: DesignConstants.paddingBig),
        children: [
          widget.header,
          const SizedBox(height: DesignConstants.spacingBig),
          const _ReadyEmpty(),
        ],
      );
    }

    // header (item 0) + roster rows + an optional trailing spinner.
    final rowCount = state.rows.length + (state.isLoadingMore ? 1 : 0);
    return ListView.separated(
      controller: _controller,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: DesignConstants.paddingBig),
      itemCount: 1 + rowCount,
      separatorBuilder: (_, index) => index == 0
          // No divider between the header and the first row.
          ? const SizedBox(height: DesignConstants.spacingBig)
          : const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.screenHorizontalPadding,
              ),
              child: Hairline(),
            ),
      itemBuilder: (context, index) {
        if (index == 0) return widget.header;
        final rowIndex = index - 1;
        if (rowIndex == state.rows.length) {
          return const Padding(
            padding: EdgeInsets.all(DesignConstants.paddingSmall),
            child: Center(
              child: AppSpinner(size: DesignConstants.spinnerSizeSmall),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: ReadyToPromoteRow(
            row: state.rows[rowIndex],
            ladder: state.ladder,
            subRankType: state.subRankType,
          ),
        );
      },
    );
  }
}

class _ReadyEmpty extends StatelessWidget {
  const _ReadyEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.trending_up_sharp,
            size: DesignConstants.iconSizeBig,
            color: DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                'No one is close to a promotion yet',
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              Text(
                'Members appear here as they log classes toward their '
                'next belt.',
                textAlign: TextAlign.center,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
