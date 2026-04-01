import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A responsive layout that displays children in two
/// columns on desktop and stacks them on tablet/narrow.
///
/// Breakpoint at 900px of available width.
class ResponsiveTwoColumn extends StatelessWidget {
  final List<Widget> left;
  final List<Widget> right;

  const ResponsiveTwoColumn({
    super.key,
    required this.left,
    required this.right,
  });

  static const double _breakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _breakpoint) {
          return _desktopLayout();
        }
        return _tabletLayout();
      },
    );
  }

  Widget _desktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(children: left),
        ),
        const SizedBox(
          width: DesignConstants.spacingLarge,
        ),
        Expanded(
          child: Column(children: right),
        ),
      ],
    );
  }

  Widget _tabletLayout() {
    return Column(
      children: [
        ...left,
        ...right,
      ],
    );
  }
}
