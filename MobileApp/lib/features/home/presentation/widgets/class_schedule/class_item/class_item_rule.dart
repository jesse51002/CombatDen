import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The separating line beneath a class row.
///
/// [hairline] is the lighter weight the dense and spine treatments use,
/// where a 2px rule would out-shout the row it separates.
class ClassItemRule extends StatelessWidget {
  const ClassItemRule({super.key, this.hairline = false});

  final bool hairline;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: hairline
          ? DesignConstants.dividerThickness
          : DesignConstants.buttonBorder,
      color: DesignConstants.divider,
    );
  }
}
