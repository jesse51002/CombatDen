import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/custom_text_field.dart';
import 'package:app_management/shared/widgets/form/image_upload_field.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Class details" form section: name, description, and class image.
class ClassDetailsSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final String? imageUrl;
  final String? imageAsset;

  const ClassDetailsSection({
    super.key,
    required this.nameController,
    required this.descriptionController,
    this.imageUrl,
    this.imageAsset,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Class details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          ImageUploadField(
            label: 'Class image',
            imageUrl: imageUrl,
            imageAsset: imageAsset,
            onTap: () => debugPrint('TODO: pick class image'),
          ),
          CustomTextField(
            controller: nameController,
            label: 'Class name',
            hintText: 'e.g. Muay Thai All Levels',
          ),
          CustomTextField(
            controller: descriptionController,
            label: 'Description',
            hintText: 'Short class description',
          ),
        ],
      ),
    );
  }
}
