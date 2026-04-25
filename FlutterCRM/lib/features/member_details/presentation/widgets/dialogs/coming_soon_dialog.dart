import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// Tiny [AppDialog] wrapper used to stub buttons whose
/// backend is not yet available. Shows the feature name
/// and a short explanation, with a single OK button.
class ComingSoonDialog {
  ComingSoonDialog._();

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    return AppDialog.show<void>(
      context: context,
      title: title,
      body: Text(
        message,
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
      primaryLabel: 'OK',
      primaryOnPressed: () =>
          Navigator.of(context).pop(),
      secondaryLabel: null,
    );
  }
}
