import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The custom-discount form's end-date field: a tappable
/// pill that opens the date picker, shown when an ongoing
/// custom ends on an explicit date.
class CustomDiscountEndDateField
    extends StatelessWidget {
  final DateTime? endDate;
  final VoidCallback onTap;

  const CustomDiscountEndDateField({
    super.key,
    required this.endDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = endDate == null
        ? 'Pick a date'
        : DateFormat('MMM d, y').format(endDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('End date', style: DesignConstants.h3),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          child: Container(
            padding: const EdgeInsets.all(
              DesignConstants.paddingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusBig,
              ),
              border: Border.all(
                color: DesignConstants.text,
                width: DesignConstants.buttonBorder,
              ),
            ),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Icon(
                  Icons.calendar_today,
                  size: DesignConstants.iconSizeSmall,
                  color: DesignConstants.text2nd,
                ),
                Text(
                  label,
                  style: DesignConstants.p.copyWith(
                    color: endDate == null
                        ? DesignConstants.text3rd
                        : DesignConstants.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
