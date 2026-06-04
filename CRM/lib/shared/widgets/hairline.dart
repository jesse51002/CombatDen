import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A 1px rule in the divider color used to separate de-carded sections.
/// Horizontal by default; set [vertical] to separate side-by-side
/// columns (needs a bounded height, e.g. inside an `IntrinsicHeight` row).
class Hairline extends StatelessWidget {
  final bool vertical;

  const Hairline({super.key, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: vertical ? 1 : null,
      height: vertical ? null : 1,
      color: DesignConstants.divider,
    );
  }
}
