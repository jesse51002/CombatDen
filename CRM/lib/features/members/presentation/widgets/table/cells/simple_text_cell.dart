import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A simple text cell for table data.
///
/// Reusable for dates, durations, prices, days
/// remaining, days late, and any other plain text
/// column.
class SimpleTextCell extends StatelessWidget {
  final String text;
  final Color? color;

  const SimpleTextCell({
    super.key,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: DesignConstants.h3.copyWith(
        color: color ?? DesignConstants.text,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
