import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Prompts for the plan's new price (dollars) and returns it in minor
/// units (cents), or `null` if cancelled. The new price becomes the
/// plan's active price; existing members keep their old price until they
/// are migrated.
class UpdatePlanPriceDialog {
  const UpdatePlanPriceDialog._();

  static Future<int?> show(BuildContext context) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return AppDialog.show<int>(
      context: context,
      title: 'Update price',
      primaryLabel: 'Update',
      body: Form(
        key: formKey,
        child: CustomTextField(
          controller: controller,
          label: 'New price (\$)',
          hintText: '165',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          validator: _validatePrice,
        ),
      ),
      primaryOnPressed: (dialogContext) {
        if (!(formKey.currentState?.validate() ?? false)) return;
        final dollars = double.tryParse(controller.text.trim());
        if (dollars == null) return;
        Navigator.of(dialogContext).pop((dollars * 100).round());
      },
    );
  }

  static String? _validatePrice(String? v) {
    final d = double.tryParse(v?.trim() ?? '');
    if (d == null) return 'Enter a price';
    if (d < 0) return 'Must be 0 or more';
    return null;
  }
}
