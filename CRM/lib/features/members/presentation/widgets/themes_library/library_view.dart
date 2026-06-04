import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/theme_search_bar.dart';
import 'package:crm/features/members/presentation/widgets/themes_library/library_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/filter_pills.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';
import 'package:crm/features/members/data/gyms_pager.dart';

const String _kAllChip = 'All';
const int _kPageSize = 50;
const double _kSearchMaxWidth = 480;
// Responsive grid: the column count is whatever fits at this min card width, so
// the wider full-screen standalone browser shows more columns (≈4 on a typical
// desktop) than the narrower embedded admin tab. Never drop below 2 columns.
// See `FillGrid.minItemWidth` / `minColumns`.
const double _kGridMinItemWidth = 280;
const int _kGridMinColumns = 2;

/// Themes library — a collapsing title over a persistent search + filter-pill
/// bar, a hairline, then a responsive `FillGrid` of theme cards (column count
/// scales with width). Scrolling the grid collapses the title away and tightens
/// the chrome; the search + filters stay put. Centered chrome, system
/// object-card grid. Picking a card calls [ThemeRuntime.selectDesign] then
/// [onPicked].
class LibraryView extends StatefulWidget {
  const LibraryView({super.key, required this.onPicked});

  final VoidCallback onPicked;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final GymsPager _pager = GymsPager(pageSize: _kPageSize);
  final ScrollController _scrollController = ScrollController();
  // Tags the card of the already-selected gym so we can center it on entry.
  final GlobalKey _selectedCardKey = GlobalKey();
  bool _didAnchor = false;
  String _selected = _kAllChip;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_pullUntilDone);
    // Returning to the library after picking a gym: center its card once, the
    // same "build around the selection" the phone-mode side pane does.
    _anchorOnSelectedOnce();
  }

  void _pullUntilDone() {
    if (!mounted) return;
    // The library is the gym-select screen — it deliberately does NOT
    // auto-select a gym; picking a card does (via `_pick`). (The phone-mode
    // side pane reconciles a deep-linked theme to its gym; the library doesn't.)
    // The already-selected card may live on a later page; keep trying to center
    // as pages stream in.
    _anchorOnSelectedOnce();
    if (!_pager.isLoading && _pager.hasMore) {
      _pager.loadMore();
    }
  }

  // One-shot: once a gym is already selected and its card is built, center it in
  // the grid — by the card's context, instant (no scroll animation). Only fires
  // when there's a real selection (`selectedGym.designId`), so a fresh load with
  // nothing picked stays at the top. Retries until the card streams in.
  void _anchorOnSelectedOnce() {
    if (_didAnchor) return;
    if (selectedGym.designId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didAnchor || !mounted) return;
      final ctx = _selectedCardKey.currentContext;
      if (ctx == null) return; // card not built yet (later page / filtered out).
      _didAnchor = true;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
    });
  }

  @override
  void dispose() {
    _pager.removeListener(_pullUntilDone);
    _pager.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _chipsFor(List<ThemeStyle> items) {
    final seen = <String>{
      for (final s in items)
        if ((s.gymType ?? '').isNotEmpty) s.gymType!,
    };
    final sorted = seen.toList()..sort();
    return [_kAllChip, ...sorted];
  }

  List<ThemeStyle> _visible(List<ThemeStyle> items) {
    if (_selected == _kAllChip) return items;
    return items.where((s) => s.gymType == _selected).toList();
  }

  void _pick(ThemeStyle style) {
    // Records the gym globally (rewards/classes/spec) AND brands with its theme.
    selectedGym.selectStyle(style);
    widget.onPicked();
  }

  // Collapsed once the grid is scrolled past a small threshold: the big
  // "Theme library" title animates away and the chrome tightens, leaving the
  // search + filter pills at the top. The search/filters live above the
  // scrolling grid, so they're always visible — only the title collapses.
  bool _collapsed = false;

  bool _onScroll(ScrollNotification n) {
    final pixels = n.metrics.pixels;
    // Hysteresis: collapsing grows the viewport (the title's space is freed),
    // which can nudge `pixels` back across a single threshold and flicker.
    // Separate collapse/expand thresholds keep it stable.
    var next = _collapsed;
    if (!_collapsed && pixels > 24) {
      next = true;
    } else if (_collapsed && pixels < 8) {
      next = false;
    }
    if (next != _collapsed) setState(() => _collapsed = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pager,
      builder: (context, _) {
        final chips = _chipsFor(_pager.items);
        final selectedIndex =
            chips.indexOf(_selected).clamp(0, chips.length - 1);
        final visible = _visible(_pager.items);
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            // Tighter vertical rhythm once collapsed (reduced padding).
            spacing: _collapsed
                ? DesignConstants.spacingMedium
                : DesignConstants.spacingBig,
            children: [
              // Chrome cluster: a collapsing title above the persistent
              // search + filters. Closer-related siblings get tighter gaps.
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                // The title→search gap closes as the title collapses away.
                spacing:
                    _collapsed ? 0.0 : DesignConstants.spacingLarge,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _collapsed
                        ? const SizedBox(width: double.infinity)
                        : Text(
                            'Theme library',
                            style: DesignConstants.h1,
                            textAlign: TextAlign.center,
                          ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: DesignConstants.spacingMedium,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _kSearchMaxWidth,
                        ),
                        child: ThemeSearchBar(onChanged: _pager.setQuery),
                      ),
                      FilterPills(
                        labels: chips,
                        selectedIndex: selectedIndex,
                        onSelected: (i) =>
                            setState(() => _selected = chips[i]),
                      ),
                    ],
                  ),
                ],
              ),
              // Largest break on the page: chrome above, grid below.
              const Hairline(),
              Expanded(
                child: _Grid(
                  visible: visible,
                  isLoading: _pager.isLoading,
                  errored: _pager.errored,
                  onPick: _pick,
                  scrollController: _scrollController,
                  selectedDesignId: selectedGym.designId,
                  selectedCardKey: _selectedCardKey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.visible,
    required this.isLoading,
    required this.errored,
    required this.onPick,
    required this.scrollController,
    required this.selectedDesignId,
    required this.selectedCardKey,
  });

  final List<ThemeStyle> visible;
  final bool isLoading;
  final bool errored;
  final ValueChanged<ThemeStyle> onPick;
  final ScrollController scrollController;
  final String? selectedDesignId;
  final GlobalKey selectedCardKey;

  @override
  Widget build(BuildContext context) {
    if (visible.isEmpty) {
      return _EmptyState(
        text: isLoading
            ? 'Loading themes…'
            : errored
                ? 'Could not reach the video service (the gym browser, '
                      'port 8002).'
                : 'No themes match this filter.',
      );
    }
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) {
        final active = ThemeRuntime.activeDesignId;
        return SingleChildScrollView(
          controller: scrollController,
          child: FillGrid(
            minItemWidth: _kGridMinItemWidth,
            minColumns: _kGridMinColumns,
            // Keep the grid fixed on search: a single result is one normal-
            // width card in the top-left, not a card stretched full-width.
            stretchShortRows: false,
            children: [
              for (final s in visible)
                LibraryCard(
                  // Tag the already-selected gym's card so the view can center
                  // on it when re-entering the library.
                  key: s.id == selectedDesignId ? selectedCardKey : null,
                  style: s,
                  isActive: s.id == active,
                  onTap: () => onPick(s),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              Symbols.search_off_sharp,
              color: DesignConstants.text3rd,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeBig,
            ),
            Text(
              text,
              style:
                  DesignConstants.p.copyWith(color: DesignConstants.text2nd),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
