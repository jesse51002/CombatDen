import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A quiet one-line caveat under a chart — "Only one period so far",
/// "Showing the last 40 …".
///
/// The section's own subtitle is owned by the page, so a renderer that has
/// something to say about ITS data says it here, attached to the chart it
/// applies to.
class ChartNote extends StatelessWidget {
  final String text;

  const ChartNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.text3rd,
      ),
    );
  }
}
