import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// How the top-filter pills are laid out.
enum VideoCategoryTabsAxis {
  /// A centred pill strip across the top, scrolling sideways once the
  /// tenant's feed carries more groups than the width holds.
  horizontal,

  /// A pill column, for the layouts that put the filter in a rail
  /// beside the feed.
  vertical,
}

/// The top-filter pills for the videos screen (All + one per
/// `big_group` present in the loaded feed). Selecting a pill re-filters
/// the feed in place via [onTabSelected].
class VideoCategoryTabs extends StatelessWidget {
  const VideoCategoryTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    this.axis = VideoCategoryTabsAxis.horizontal,
    this.onTabSelected,
  });

  final List<String> tabs;
  final int selectedIndex;
  final VideoCategoryTabsAxis axis;
  final ValueChanged<int>? onTabSelected;

  List<Widget> _pills() => [
    for (var i = 0; i < tabs.length; i++)
      _CategoryPill(
        label: tabs[i],
        isActive: i == selectedIndex,
        onTap: () => onTabSelected?.call(i),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    if (axis == VideoCategoryTabsAxis.vertical) {
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingLarge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: _pills(),
        ),
      );
    }

    // Centred while the pills fit, scrollable once they don't: the app
    // owns no tag vocabulary, so the number of groups is the tenant's,
    // not ours.
    const inset = DesignConstants.screenHorizontalPadding;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: inset,
          vertical: DesignConstants.spacingLarge,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth.isFinite
                ? constraints.maxWidth - inset * 2
                : 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: DesignConstants.spacingLarge,
            children: _pills(),
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isActive
        ? DesignConstants.primaryColor
        : DesignConstants.backgroundColor;
    final fg = isActive ? DesignConstants.text : DesignConstants.text2nd;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Text(label, style: DesignConstants.h3.copyWith(color: fg)),
      ),
    );
  }
}
