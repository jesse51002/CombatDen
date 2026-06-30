import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

final DateFormat _dateLabel = DateFormat('EEEE, MMM d, yyyy');

/// The occurrence screen's header: a back arrow, the class name, and the
/// tapped occurrence's date (e.g. "Tuesday, Jun 30, 2026") as a subtitle.
class ClassOccurrenceHeader extends StatelessWidget {
  final String className;
  final DateTime date;
  final VoidCallback onBack;

  const ClassOccurrenceHeader({
    super.key,
    required this.className,
    required this.date,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.all(DesignConstants.spacingSmall),
            child: Icon(
              Symbols.arrow_back_sharp,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                className,
                style: DesignConstants.h1.copyWith(color: DesignConstants.text),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _dateLabel.format(date),
                style: DesignConstants.pBig
                    .copyWith(color: DesignConstants.text2nd),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
