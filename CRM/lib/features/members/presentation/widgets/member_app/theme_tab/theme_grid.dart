import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_card.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_search_bar.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/styles_pager.dart';

// Web admin: bigger viewport than the phone picker, so 50 per page keeps
// the side scroll snug and eager-loads the whole catalog quickly, so the
// active theme's index is resolvable for the first-load centering.
const int _kWebPageSize = 50;
// Where the active card lands on first load: 0.5 puts its top at the
// vertical middle of the list, so a compact row reads as centered.
const double _kActiveAlignment = 0.5;

/// Side-pane theme picker shown next to the phone-frame preview.
///
/// Eager-loads every page so search never misses an item, then anchors the
/// list **once** on first load so the entered theme sits centered — by
/// index, not by offset. Later card picks leave the list exactly as it is.
class ThemeGrid extends StatefulWidget {
  const ThemeGrid({super.key, required this.onBackToLibrary});

  final VoidCallback onBackToLibrary;

  @override
  State<ThemeGrid> createState() => _ThemeGridState();
}

class _ThemeGridState extends State<ThemeGrid> {
  final StylesPager _pager = StylesPager(pageSize: _kWebPageSize);
  final ItemScrollController _itemScroll = ItemScrollController();
  bool _didCenter = false;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_pullUntilDone);
    // First load only: center once on whatever's already active. We
    // deliberately do NOT listen to `ThemeRuntime.changes` — picking a card
    // must leave the list exactly where it is.
    _centerOnActiveOnce();
  }

  void _pullUntilDone() {
    if (!mounted) return;
    // Seed/heal the global selection from the loaded catalog (the active
    // theme's gym id isn't known until its card streams in).
    selectedGym.reconcileFromCatalog(_pager.items);
    // The active theme may live on a later page; keep trying to center as
    // pages stream in, and eager-load the rest so search has the full set.
    _centerOnActiveOnce();
    if (!_pager.isLoading && _pager.hasMore) {
      _pager.loadMore();
    }
  }

  // One-shot: anchors the list so the active card is centered, the first
  // frame its index is known and the positioned list is attached. By index,
  // not offset — so lazy loading and viewport height never throw it off.
  // Once it fires it never runs again, so selecting a card never moves it.
  void _centerOnActiveOnce() {
    if (_didCenter) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didCenter || !mounted || !_itemScroll.isAttached) return;
      final active = ThemeRuntime.activeDesignId;
      if (active == null) return;
      final i = _pager.items.indexWhere((s) => s.id == active);
      if (i < 0) return; // not loaded yet — retry on the next page tick.
      _didCenter = true;
      _itemScroll.jumpTo(index: i, alignment: _kActiveAlignment);
    });
  }

  @override
  void dispose() {
    _pager.removeListener(_pullUntilDone);
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('App Theme', style: DesignConstants.h2),
        ThemeSearchBar(onChanged: _pager.setQuery),
        AppOutlineButton(
          text: '← Back to library',
          fullWidth: true,
          onPressed: widget.onBackToLibrary,
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _pager,
            builder: (context, _) =>
                _ThemeListView(pager: _pager, itemScroll: _itemScroll),
          ),
        ),
      ],
    );
  }
}

/// The scrollable theme list itself, plus its loading / empty / error
/// states. Wraps in `ListenableBuilder(ThemeRuntime.changes)`
/// so the active-card border flips when the live theme switches.
class _ThemeListView extends StatelessWidget {
  const _ThemeListView({required this.pager, required this.itemScroll});

  final StylesPager pager;
  final ItemScrollController itemScroll;

  @override
  Widget build(BuildContext context) {
    if (!pager.hasLoadedFirstPage && pager.isLoading) {
      return const _CatalogMessage.loading();
    }
    if (pager.items.isEmpty) {
      if (pager.errored) {
        return const _CatalogMessage(
          'Could not reach the theme service. '
          'Start it and reopen this tab to load the themes.',
        );
      }
      return _CatalogMessage(
        pager.query.isEmpty
            ? 'No themes generated yet.'
            : 'No themes match "${pager.query}".',
      );
    }
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) {
        final active = ThemeRuntime.activeDesignId;
        return ScrollablePositionedList.separated(
          itemScrollController: itemScroll,
          itemCount: pager.items.length,
          // A positioned list has no `spacing:`; the separator builder is
          // the idiomatic gap, so SizedBox here is intentional, not a
          // spacing-rule violation.
          separatorBuilder: (_, _) => const SizedBox(
            height: DesignConstants.spacingMedium,
          ),
          itemBuilder: (context, i) {
            final style = pager.items[i];
            return ThemeCard(style: style, isActive: style.id == active);
          },
        );
      },
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  final String? message;

  const _CatalogMessage(this.message);
  const _CatalogMessage.loading() : message = null;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? const AppSpinner()
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
