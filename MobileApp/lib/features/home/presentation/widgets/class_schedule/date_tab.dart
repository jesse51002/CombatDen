import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Single date pill rendered inside [DateRow]. Bottom-bordered when
/// selected; tappable.
class DateTab extends StatelessWidget {
  const DateTab({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? DesignConstants.primaryColor
        : DesignConstants.text2nd;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: DesignConstants.primaryColor,
                    width: DesignConstants.buttonBorder,
                  ),
                ),
              )
            : null,
        padding: EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
          horizontal: DesignConstants.spacingLarge,
        ),
        alignment: Alignment.center,
        child: Text(label, style: DesignConstants.h2.copyWith(color: color)),
      ),
    );
  }
}
