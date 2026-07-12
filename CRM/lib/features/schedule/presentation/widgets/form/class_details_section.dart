import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "Class details" form section: name, description, and class image.
class ClassDetailsSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController descriptionController;

  /// The class's current image URL (null on a new class with none yet — the
  /// platform default is previewed instead).
  final String? imageUrl;

  /// Called with the CDN URL after the owner uploads a class image. The
  /// URL is bubbled up into the form state so the create/update request
  /// carries the chosen image.
  final ValueChanged<String> onImageChanged;

  const ClassDetailsSection({
    super.key,
    required this.nameController,
    required this.descriptionController,
    required this.onImageChanged,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Class details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          ImageUploadPickerField(
            label: 'Class image',
            category: 'class',
            imageUrl: imageUrl,
            defaultImageUrl: AppConstants.defaultClassImageUrl,
            onImageChosen: onImageChanged,
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
