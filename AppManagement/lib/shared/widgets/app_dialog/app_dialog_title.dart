import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Title row for an [AppDialog]. Renders the dialog
/// title and an optional close icon aligned to the end.
class AppDialogTitle extends StatelessWidget {
  final String title;
  final bool showCloseButton;
  final VoidCallback? onClose;

  const AppDialogTitle({
    super.key,
    required this.title,
    this.showCloseButton = true,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: DesignConstants.h1,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showCloseButton)
          IconButton(
            onPressed: onClose ??
                () => Navigator.of(context).pop(),
            icon: Icon(
              Symbols.close_sharp,
              color: DesignConstants.text2nd,
              weight: DesignConstants.iconWeight,
            ),
            tooltip: 'Close',
            splashRadius: 20,
          ),
      ],
    );
  }
}
