import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Section header with a title on the left and an inline "view all" link
/// on the right.
class LevelUpVideosHeader extends StatelessWidget {
  const LevelUpVideosHeader({
    super.key,
    required this.title,
    required this.onViewAll,
  });

  final String title;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(child: Text(title, style: DesignConstants.h2)),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onViewAll,
          child: Text(
            'view all',
            style: DesignConstants.p.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: DesignConstants.text,
            ),
          ),
        ),
      ],
    );
  }
}
