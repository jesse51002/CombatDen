import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_agenda_list.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_board_grid.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_day_pager.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_next_up_hero.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_time_spine.dart';

/// The schedule, arranged by the tenant's `home_format` slot.
///
/// Takes its data as an argument and fetches nothing, so the arrangement
/// can be exercised in every state without a repository — see
/// `test/home_invariants_test.dart`, which is the gate that proves each
/// value renders the same element set.
///
/// The switch sits under a [FormatBuilder] so the in-app dev picker can
/// swap layouts in place: only this subtree rebuilds, the loaded classes
/// above it survive, and the Navigator is never re-keyed.
class HomeLayoutBody extends StatelessWidget {
  const HomeLayoutBody({
    super.key,
    required this.data,
    this.formatOverride,
  });

  final HomeLayoutData data;

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant tests and the preview sheet; null in
  /// normal app use.
  final HomeFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    return FormatBuilder(builder: _build);
  }

  Widget _build(BuildContext context) {
    // Double-tap the schedule to jump straight into the post-class stats
    // flow — a quick-demo shortcut. Discrete double-tap, so it doesn't
    // fight the vertical scroll. Mirrors the class screen's entry
    // (replace, not push: the flow exits back to home on its own).
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () =>
          Navigator.of(context).pushReplacementNamed(AppRoutes.postClassStreak),
      child: switch (formatOverride ?? ThemeLayout.home()) {
        HomeFormat.agendaList => HomeAgendaList(data: data),
        HomeFormat.dayPager => HomeDayPager(data: data),
        HomeFormat.timeSpine => HomeTimeSpine(data: data),
        HomeFormat.nextUpHero => HomeNextUpHero(data: data),
        HomeFormat.boardGrid => HomeBoardGrid(data: data),
      },
    );
  }
}
