import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';

/// "N attending" with its person icon.
///
/// Its own widget because both meta treatments carry it — the stacked
/// block and the spec table — and the icon must not quietly disappear
/// from one of them.
class ClassAttendingRow extends StatelessWidget {
  const ClassAttendingRow({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.person_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.primaryColor,
          size: DesignConstants.iconSizeSm,
        ),
        Text(
          '$count attending',
          style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
