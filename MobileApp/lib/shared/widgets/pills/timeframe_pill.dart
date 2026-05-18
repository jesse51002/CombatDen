import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Pill button used in time-range selectors (e.g. "1W", "1M", "1Y").
class TimeframePill extends StatelessWidget {
  const TimeframePill({
    super.key,
    required this.label,
    required this.isActive,
    this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => debugPrint('TODO: timeframe $label'),
      child: Container(
        height: DesignConstants.pillHeightMd,
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.screenHorizontalPadding,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: isActive
              ? Border.all(
                  color: DesignConstants.text,
                  width: DesignConstants.buttonBorder,
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: DesignConstants.h2.copyWith(
            color: isActive
                ? DesignConstants.text
                : DesignConstants.text3rd,
          ),
        ),
      ),
    );
  }
}
