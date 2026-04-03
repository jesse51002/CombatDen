import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';

/// A responsive grid layout with fixed height on desktop.
///
/// Desktop (≥900px): 2-column grid at 2000px height.
/// Left column splits into topLeft (1/3) and
/// bottomLeft (2/3). Right column spans full height.
///
/// Tablet/narrow: stacks all items vertically.
class ResponsiveGrid extends StatelessWidget {
  final Widget topLeft;
  final Widget bottomLeft;
  final Widget right;
  final double spacing;

  const ResponsiveGrid({
    super.key,
    required this.topLeft,
    required this.bottomLeft,
    required this.right,
    this.spacing = DesignConstants.spacingBig,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >=
            AppConstants.breakpointTablet) {
          return _desktopLayout();
        }
        return _tabletLayout();
      },
    );
  }

  Widget _desktopLayout() {
    return SizedBox(
      height: 1400,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: spacing,
        children: [
          Expanded(
            child: Column(
              spacing: spacing,
              children: [
                Expanded(
                  child: topLeft,
                ),
                Expanded(
                  flex: 2,
                  child: bottomLeft,
                ),
              ],
            ),
          ),
          Expanded(
            child: right,
          ),
        ],
      ),
    );
  }

  Widget _tabletLayout() {
    return SizedBox(
      height: 2800,
      child: Column(
        spacing: spacing,
        children: [
          Expanded(child: topLeft),
          Expanded(flex: 2, child: bottomLeft),
          Expanded(flex: 3, child: right),
        ],
      ),
    );
  }
}
