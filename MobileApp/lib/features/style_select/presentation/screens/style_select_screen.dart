import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/style_select/data/gyms_pager.dart';
import 'package:mobile_app/features/style_select/presentation/widgets/style_card/style_card.dart';
import 'package:mobile_app/features/style_select/presentation/widgets/style_list/style_search_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

// Phones load 10 per page — small enough to feel instant on slow links,
// big enough to fill the visible viewport on a single roundtrip.
const int _kMobilePageSize = 10;
// Distance from the list bottom that triggers the next-page fetch. Big
// enough that the loader is already in flight before the user reaches
// the end, so the scroll feels seamless.
const double _kLoadMoreThreshold = 600;

/// Reached by double-tapping the home logo. A search bar over a
/// vertically-paged list of styles (design name + celebration image)
/// fetched from the ThemeService; tapping one switches the live
/// theme and pops back to the now-re-themed app.
class StyleSelectScreen extends StatefulWidget {
  const StyleSelectScreen({super.key});

  @override
  State<StyleSelectScreen> createState() => _StyleSelectScreenState();
}

class _StyleSelectScreenState extends State<StyleSelectScreen> {
  final GymsPager _pager = GymsPager(pageSize: _kMobilePageSize);
  final ScrollController _scroll = ScrollController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - _kLoadMoreThreshold) {
      _pager.loadMore();
    }
  }

  void _select(ThemeStyle style) {
    if (_busy) return;
    setState(() => _busy = true);
    // Record the gym (drives videos / classes / rewards) and re-brand to its
    // theme. Then land on a fresh Home for this gym — the theme re-key rebuilds
    // the tree too, but this also covers picking the gym whose theme is already
    // active (no re-key fires then).
    selectedGym.select(
      gymId: style.gymId,
      theme: style.id,
      name: style.displayName,
    );
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          const _StyleSelectHeader(),
          StyleSearchBar(onChanged: _pager.setQuery),
          Expanded(
            child: ListenableBuilder(
              listenable: _pager,
              builder: (context, _) => _StyleListView(
                pager: _pager,
                scroll: _scroll,
                onSelect: _select,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Back chevron + screen title.
class _StyleSelectHeader extends StatelessWidget {
  const _StyleSelectHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Icon(
            Symbols.chevron_left_sharp,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text,
            size: DesignConstants.iconSize2xl,
          ),
        ),
        Expanded(
          child: Text('Choose a gym', style: DesignConstants.h1),
        ),
      ],
    );
  }
}

/// Lazily-paged scroll list. Rebuilds on every pager state transition;
/// re-themes via ThemeRuntime.changes so the "active" card
/// border flips when the live theme switches under it.
class _StyleListView extends StatelessWidget {
  const _StyleListView({
    required this.pager,
    required this.scroll,
    required this.onSelect,
  });

  final GymsPager pager;
  final ScrollController scroll;
  final ValueChanged<ThemeStyle> onSelect;

  @override
  Widget build(BuildContext context) {
    if (!pager.hasLoadedFirstPage && pager.isLoading) {
      return const _StyleStatus(message: 'Loading gyms…');
    }
    if (pager.items.isEmpty) {
      if (pager.errored) {
        return const _StyleStatus(
          message: 'Could not load gyms. Pull to retry.',
        );
      }
      return _StyleStatus(
        message: pager.query.isEmpty
            ? 'No gyms available right now.'
            : 'No gyms match "${pager.query}".',
      );
    }
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) {
        final activeId = ThemeRuntime.activeDesignId;
        final showFooter = pager.hasMore || pager.isLoading || pager.errored;
        final itemCount = pager.items.length + (showFooter ? 1 : 0);
        return ListView.separated(
          controller: scroll,
          itemCount: itemCount,
          separatorBuilder: (_, _) => SizedBox(
            height: DesignConstants.spacingLarge,
          ),
          itemBuilder: (context, i) {
            if (i >= pager.items.length) return _ListFooter(pager: pager);
            final style = pager.items[i];
            return StyleCard(
              style: style,
              isActive: style.id == activeId,
              onTap: () => onSelect(style),
            );
          },
        );
      },
    );
  }
}

/// Trailing row under the last card: a loader while a page is in
/// flight, or a one-line error nudge if the last fetch failed.
class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.pager});

  final GymsPager pager;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingLarge),
      child: Center(
        child: pager.errored
            ? Text(
                'Could not load more gyms.',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              )
            : SizedBox(
                width: DesignConstants.iconSizeLg,
                height: DesignConstants.iconSizeLg,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              ),
      ),
    );
  }
}

/// Centered loading / empty / error message.
class _StyleStatus extends StatelessWidget {
  const _StyleStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Center(
        child: Text(
          message,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
