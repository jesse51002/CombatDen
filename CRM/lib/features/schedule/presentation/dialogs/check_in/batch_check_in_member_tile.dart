import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One checkbox row in the batch check-in multi-select roster: a [name] with a
/// checkbox, highlighted when [selected]. Tapping anywhere toggles it.
class BatchCheckInMemberTile extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const BatchCheckInMemberTile({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingSmall),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor10
              : DesignConstants.backgroundColor,
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
          ),
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Checkbox(value: selected, onChanged: (_) => onTap()),
            Expanded(
              child: Text(
                name,
                style: DesignConstants.p,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
