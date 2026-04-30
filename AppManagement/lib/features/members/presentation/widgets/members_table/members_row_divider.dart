import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Hairline horizontal rule used between table rows.
class MembersRowDivider extends StatelessWidget {
  const MembersRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DesignConstants.spacingTiny,
      color: DesignConstants.divider,
    );
  }
}
