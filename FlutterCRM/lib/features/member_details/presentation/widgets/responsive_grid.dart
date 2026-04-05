import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';

/// A responsive grid layout with fixed height on desktop.
///
/// Desktop (≥900px): 2-column grid at 2000px height.
/// Left column splits into personalInfoCard (1/3) and
/// retentionCard (2/3). Right column spans full height.
///
/// Tablet/narrow: stacks all items vertically.
class ResponsiveGrid extends StatelessWidget {
  final Widget personalInfoCard;
  final Widget retentionCard;
  final Widget membershipCard;
  final double spacing;

  const ResponsiveGrid({
    super.key,
    required this.personalInfoCard,
    required this.retentionCard,
    required this.membershipCard,
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
                  flex: 2,
                  child: personalInfoCard,
                ),
                Expanded(
                  flex: 3,
                  child: retentionCard,
                ),
              ],
            ),
          ),
          Expanded(
            child: membershipCard,
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
          Expanded(flex: 2, child: personalInfoCard),
          Expanded(flex: 3, child: retentionCard),
          Expanded(flex: 5, child: membershipCard),
        ],
      ),
    );
  }
}
