import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// The run of full-width sections, in whatever order a layout hands
/// them over, with the shipped gap and a rule between each pair.
///
/// Owns the interleaving so three layouts share one definition instead
/// of each re-threading dividers through its own list.
class ClassSectionStack extends StatelessWidget {
  const ClassSectionStack({
    super.key,
    required this.sections,
    this.padded = true,
  });

  final List<Widget> sections;

  /// Whether to apply the screen's body inset. False when the caller
  /// already sits inside one.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) children.add(const SectionDivider());
      children.add(sections[i]);
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: children,
    );

    if (!padded) return column;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingBig,
        DesignConstants.screenHorizontalPadding,
        DesignConstants.spacingBig,
      ),
      child: column,
    );
  }
}
