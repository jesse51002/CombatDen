import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// "Details" header + long-form class description. Renders nothing when the
/// class has no description (`gym_classes.class_description` is nullable).
class ClassDetailsSection extends StatelessWidget {
  const ClassDetailsSection({super.key, required this.description});

  final String? description;

  @override
  Widget build(BuildContext context) {
    final text = description?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return SubtitleSection(
      title: 'Details',
      spacing: DesignConstants.spacingMedium,
      child: Text(
        text,
        style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}
