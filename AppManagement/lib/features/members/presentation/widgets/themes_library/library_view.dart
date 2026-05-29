import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_search_bar.dart';
import 'package:app_management/features/members/presentation/widgets/themes_library/library_card.dart';
import 'package:app_management/shared/widgets/fill_grid.dart';
import 'package:app_management/shared/widgets/filter_pills.dart';
import 'package:app_management/shared/widgets/hairline.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';
import 'package:app_management/features/members/data/gyms_pager.dart';

const String _kAllChip = 'All';
const int _kPageSize = 50;
const double _kSearchMaxWidth = 480;

/// Themes library — title + search + filter pills, then a hairline,
/// then a 3-up `FillGrid` of theme cards. Centered chrome, system
/// object-card grid. Picking a card calls
/// [ThemeRuntime.selectDesign] then [onPicked].
class LibraryView extends StatefulWidget {
  const LibraryView({super.key, required this.onPicked});

  final VoidCallback onPicked;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final GymsPager _pager = GymsPager(pageSize: _kPageSize);
  String _selected = _kAllChip;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_pullUntilDone);
  }

  void _pullUntilDone() {
    if (!mounted) return;
    // The library is the gym-select screen — it deliberately does NOT
    // auto-select a gym; picking a card does (via `_pick`). (The phone-mode
    // side pane reconciles a deep-linked theme to its gym; the library doesn't.)
    if (!_pager.isLoading && _pager.hasMore) {
      _pager.loadMore();
    }
  }

  @override
  void dispose() {
    _pager.removeListener(_pullUntilDone);
    _pager.dispose();
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pager,
      builder: (context, _) {
        final chips = _chipsFor(_pager.items);
        final selectedIndex =
            chips.indexOf(_selected).clamp(0, chips.length - 1);
        final visible = _visible(_pager.items);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Chrome cluster: title → search → filters, all centered,
            // closer-related siblings get tighter gaps.
            Text(
              'Theme library',
              style: DesignConstants.h1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesignConstants.spacingLarge),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kSearchMaxWidth),
              child: ThemeSearchBar(onChanged: _pager.setQuery),
            ),
            const SizedBox(height: DesignConstants.spacingMedium),
            FilterPills(
              labels: chips,
              selectedIndex: selectedIndex,
              onSelected: (i) => setState(() => _selected = chips[i]),
            ),
            // Largest break on the page: chrome above, grid below.
            const SizedBox(height: DesignConstants.spacingBig),
            const Hairline(),
            const SizedBox(height: DesignConstants.spacingBig),
            Expanded(
              child: _Grid(
                visible: visible,
                isLoading: _pager.isLoading,
                errored: _pager.errored,
                onPick: _pick,
              ),
            ),
          ],
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
  });

  final List<ThemeStyle> visible;
  final bool isLoading;
  final bool errored;
  final ValueChanged<ThemeStyle> onPick;

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
          child: FillGrid(
            columns: 3,
            children: [
              for (final s in visible)
                LibraryCard(
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
