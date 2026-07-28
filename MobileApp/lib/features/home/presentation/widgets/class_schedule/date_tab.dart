import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// How a [DateTab] draws its selected state.
enum DateTabStyle {
  /// Shipped today: bare label with a rule under the selected day.
  underline,

  /// A filled chip per day, for formats that want the date rail to read
  /// as a control rather than as a rail.
  segmented,
}

/// Single date pill rendered inside `DateRow`. Tappable; the selected
/// day is marked according to [style].
class DateTab extends StatelessWidget {
  const DateTab({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.style = DateTabStyle.underline,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final DateTabStyle style;

  BoxDecoration? get _decoration {
    final primary = DesignConstants.primaryColor;
    if (style == DateTabStyle.segmented) {
      return BoxDecoration(
        color: isSelected ? primary : null,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(
          color: isSelected ? primary : DesignConstants.divider,
          width: DesignConstants.dividerThickness,
        ),
      );
    }
    if (!isSelected) return null;
    return BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: primary,
          width: DesignConstants.buttonBorder,
        ),
      ),
    );
  }

  Color get _labelColor {
    if (style == DateTabStyle.segmented && isSelected) {
      return DesignConstants.primaryButtonText;
    }
    return isSelected
        ? DesignConstants.primaryColor
        : DesignConstants.text2nd;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: _decoration,
        padding: EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
          horizontal: DesignConstants.spacingLarge,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: DesignConstants.h2.copyWith(color: _labelColor),
        ),
      ),
    );
  }
}
