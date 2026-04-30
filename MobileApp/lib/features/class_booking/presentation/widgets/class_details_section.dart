import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// "Details" header + long-form description body. Mirrors the Figma
/// `DesciptionWidget` group.
class ClassDetailsSection extends StatelessWidget {
  const ClassDetailsSection({super.key, required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Details',
      spacing: DesignConstants.spacingMedium,
      child: Text(
        description,
        style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}
