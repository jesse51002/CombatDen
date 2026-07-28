import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The `sectionTabs` selector: one tab per section sharing the pane
/// below it.
///
/// Presentation only — it selects which of the screen's existing
/// sections is on top, and adds no content of its own.
class ClassTabBar extends StatelessWidget {
  const ClassTabBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: _Tab(
              label: labels[i],
              isActive: i == index,
              onTap: () => onSelect(i),
            ),
          ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingMedium),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? DesignConstants.accent
                  : DesignConstants.divider,
              width: DesignConstants.buttonBorder,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: DesignConstants.h3.copyWith(
            color: isActive
                ? DesignConstants.accent
                : DesignConstants.text3rd,
          ),
        ),
      ),
    );
  }
}
