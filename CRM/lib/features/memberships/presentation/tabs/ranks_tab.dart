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
import 'package:crm/features/memberships/presentation/screens/rank_presets_screen.dart';
import 'package:crm/features/memberships/presentation/widgets/memberships_tab_scaffold.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_enabled_section.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_ladder_section.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/rank_sub_type_section.dart';
import 'package:crm/features/memberships/presentation/widgets/ranks/ready_to_promote_row.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// Ranks tab of the Gym screen — an internal view switcher over two
/// surfaces: the editable **Rank ladder** (toggle, sub-rank style, the
/// reorderable main-rank ladder, seed-from-preset) and the
/// **Ready to promote** board (a proximity-sorted roster of members
/// closest to their next belt, with one-tap promote).
class RanksTab extends StatefulWidget {
  final String gymId;

  const RanksTab({super.key, required this.gymId});

  @override
  State<RanksTab> createState() => _RanksTabState();
}

class _RanksTabState extends State<RanksTab> {
  static const _views = ['Rank ladder', 'Ready to promote'];
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: ViewSwitcher(
            labels: _views,
            selectedIndex: _view,
            onSelected: (i) => setState(() => _view = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view,
            children: [
              const _LadderView(),
              BlocProvider<ReadyToPromoteBloc>(
                create: (ctx) => ReadyToPromoteBloc(
                  repository: ctx.read<RanksRepository>(),
                )..add(ReadyToPromoteInitRequested(widget.gymId)),
                child: const _ReadyView(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The editable ladder surface.
class _LadderView extends StatelessWidget {
  const _LadderView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RanksBloc, RanksState>(
      listenWhen: (prev, curr) =>
          curr is RanksLoaded && curr.actionError != null,
      listener: (context, state) {
        if (state is RanksLoaded && state.actionError != null) {
          showTabActionError(context, state.actionError!);
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
          RanksLoaded() => _LadderBody(state: state),
        };
      },
    );
  }
}

class _LadderBody extends StatelessWidget {
  final RanksLoaded state;

  const _LadderBody({required this.state});

  void _openPresets(BuildContext context) {
    final bloc = context.read<RanksBloc>();
    // A bare MaterialPageRoute (no name) so the preset screen keeps the
    // parent Ranks tab's URL; the shared RanksBloc rides down so Apply
    // reloads the ladder the user returns to.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: RankPresetsScreen(gymId: state.gymId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: DesignConstants.paddingBig),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.screenHorizontalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            RankEnabledSection(state: state),
            RankSubTypeSection(state: state),
            RankLadderSection(state: state),
            Center(
              child: AppOutlineButton(
                text: 'Seed from preset',
                borderRadius: DesignConstants.radiusSmall,
                icon: Icon(
                  Symbols.auto_awesome_sharp,
                  size: DesignConstants.iconSizeSmall,
                  color: DesignConstants.text,
                  weight: DesignConstants.iconWeight,
                ),
                onPressed: () => _openPresets(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ready-to-promote board.
class _ReadyView extends StatelessWidget {
  const _ReadyView();

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
                style: DesignConstants.p
                    .copyWith(color: DesignConstants.onAccent),
              ),
              backgroundColor: DesignConstants.goodGreen,
            ),
          );
        }
      },
      builder: (context, state) {
        return switch (state) {
          ReadyToPromoteInitial() ||
          ReadyToPromoteLoading() =>
            const TabLoading(),
          ReadyToPromoteError() => TabError(
              message: state.message,
              onRetry: () => context
                  .read<ReadyToPromoteBloc>()
                  .add(ReadyToPromoteInitRequested(state.gymId)),
            ),
          ReadyToPromoteLoaded() => _ReadyList(state: state),
        };
      },
    );
  }
}

class _ReadyList extends StatefulWidget {
  final ReadyToPromoteLoaded state;

  const _ReadyList({required this.state});

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
    if (state.rows.isEmpty) return const _ReadyEmpty();

    return ListView.separated(
      controller: _controller,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ).copyWith(bottom: DesignConstants.paddingBig),
      itemCount: state.rows.length + (state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const Hairline(),
      itemBuilder: (context, index) {
        if (index == state.rows.length) {
          return const Padding(
            padding: EdgeInsets.all(DesignConstants.paddingSmall),
            child: Center(child: AppSpinner(size: DesignConstants.spinnerSizeSmall)),
          );
        }
        return ReadyToPromoteRow(
          row: state.rows[index],
          ladder: state.ladder,
          subRankType: state.subRankType,
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
