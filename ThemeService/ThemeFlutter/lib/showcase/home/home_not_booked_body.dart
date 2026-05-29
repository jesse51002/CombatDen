import 'package:flutter/material.dart';

import 'package:theme_flutter/showcase/home/date_tab.dart';
import 'package:theme_flutter/showcase/home/day_class_group.dart';
import 'package:theme_flutter/showcase/home/home_schedule_generator.dart';
import 'package:theme_flutter/showcase/support/showcase_topbar.dart';
import 'package:theme_flutter/showcase/showcase_tokens.dart';

// How many date pills the static strip shows (no horizontal scroll in the
// preview). Three fits the device width comfortably.
const int _kVisibleDateTabs = 3;

/// Clone of MobileApp's `HomeNotBookedBody`, made STATIC for the preview:
/// the topbar, a fixed (non-scrolling) date strip, and the first day's class
/// schedule. The real screen scrolls vertically and the date strip scrolls
/// horizontally; the showcase removes both — content is laid out once and the
/// phone frame clips any overflow.
class HomeNotBookedBody extends StatelessWidget {
  const HomeNotBookedBody({super.key, required this.topbar});

  /// The branded topbar (gym logo + name + info bar).
  final ShowcaseTopbar topbar;

  @override
  Widget build(BuildContext context) {
    // Lay the static content out at its natural height (top-aligned) and
    // clip anything past the screen — no scrolling, no overflow error.
    return ClipRect(
      child: OverflowBox(
        minHeight: 0,
        maxHeight: double.infinity,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topbar,
            const _StaticDateStrip(),
            DayClassGroup(day: dayAt(0), showBookings: false),
          ],
        ),
      ),
    );
  }
}

class _StaticDateStrip extends StatelessWidget {
  const _StaticDateStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ShowcaseTokens.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: ShowcaseTokens.text3rd,
            width: ShowcaseTokens.dividerThickness,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ShowcaseTokens.paddingBig,
        vertical: ShowcaseTokens.spacingSmall,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < _kVisibleDateTabs; i++)
            DateTab(
              label: formatDayLabel(i),
              isSelected: i == 0,
              onTap: () {},
            ),
        ],
      ),
    );
  }
}
