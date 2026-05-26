import 'package:flutter/material.dart';

import 'package:app_management/shared/widgets/app_dialog/app_dialog.dart';
import 'package:app_management/shared/widgets/custom_text_field.dart';

/// Opens the "Edit gym name & logo" dialog and returns the new gym name
/// (or null if cancelled). The logo is the gym's in-memory asset; this
/// prototype edits the name. Mirrors the rest of the admin's dialogs via
/// [AppDialog].
Future<String?> showEditBrandingDialog(
  BuildContext context,
  String currentName,
) {
  final controller = TextEditingController(text: currentName);
  return AppDialog.show<String>(
    context: context,
    title: 'Gym name & logo',
    body: CustomTextField(
      controller: controller,
      label: 'Gym name',
      hintText: 'e.g. Apex MMA',
    ),
    primaryLabel: 'Save',
    primaryOnPressed: () => Navigator.of(context).pop(controller.text),
    secondaryOnPressed: () => Navigator.of(context).pop(),
  ).whenComplete(controller.dispose);
}
