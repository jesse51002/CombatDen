import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';

/// Three equal-width outlined buttons under the profile header:
/// Check In, Deactivate, Edit.
class ProfileActionButtons extends StatelessWidget {
  const ProfileActionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        _Button(
          text: 'Check In',
          onPressed: () => debugPrint('TODO: check in member'),
        ),
        _Button(
          text: 'Deactivate',
          onPressed: () => debugPrint('TODO: deactivate member'),
        ),
        _Button(
          text: 'Edit',
          onPressed: () => debugPrint('TODO: edit member'),
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const _Button({required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: AppOutlineButton(
        text: text,
        fullWidth: true,
        onPressed: onPressed,
      ),
    );
  }
}
