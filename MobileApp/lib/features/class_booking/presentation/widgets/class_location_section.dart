import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// "Location" header + the gym name. (The member board carries no per-class
/// address / map, so this is the gym the class runs at.)
class ClassLocationSection extends StatelessWidget {
  const ClassLocationSection({super.key, required this.gymName});

  final String gymName;

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Location',
      spacing: DesignConstants.spacingMedium,
      child: Text(
        gymName,
        style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}
