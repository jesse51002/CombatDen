import 'package:flutter/material.dart';

import 'package:customization_engine/showcase/showcase_tokens.dart';

/// Clone of MobileApp's `DateTab`. Single date pill rendered inside
/// `DateRow`. Bottom-bordered when selected; tappable.
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
    final primary = ShowcaseTokens.primaryColor;
    final color = isSelected ? primary : ShowcaseTokens.text2nd;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: primary,
                    width: ShowcaseTokens.buttonBorder,
                  ),
                ),
              )
            : null,
        padding: EdgeInsets.symmetric(
          vertical: ShowcaseTokens.spacingMedium,
          horizontal: ShowcaseTokens.spacingLarge,
        ),
        alignment: Alignment.center,
        child: Text(label, style: ShowcaseTokens.h2.copyWith(color: color)),
      ),
    );
  }
}
