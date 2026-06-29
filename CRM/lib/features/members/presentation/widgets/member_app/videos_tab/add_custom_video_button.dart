import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// "Add custom video" action for the gym's own feed. Your videos is the one
/// addable feed section, so this appears under its row in "All" and at the top
/// of its View all grid. [onPressed] opens the paste-a-link dialog.
class AddCustomVideoButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AddCustomVideoButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppOutlineButton(
      text: 'Add custom video',
      icon: Icon(
        Symbols.add_sharp,
        color: DesignConstants.text,
        weight: DesignConstants.iconWeight,
        size: DesignConstants.iconSizeMedium,
      ),
      onPressed: onPressed,
    );
  }
}
