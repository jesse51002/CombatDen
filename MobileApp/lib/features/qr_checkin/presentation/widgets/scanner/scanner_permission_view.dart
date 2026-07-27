import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// Shown in place of the camera preview when the scanner can't start — most
/// often because camera permission was denied. Explains what's wrong and
/// offers a retry (which re-requests access / restarts the camera).
class ScannerPermissionView extends StatelessWidget {
  const ScannerPermissionView({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingBig,
          children: [
            Icon(
              Symbols.no_photography_sharp,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
              size: DesignConstants.iconSize2xl,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: DesignConstants.h1,
                ),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
            AppPrimaryButton(
              text: 'Try again',
              onPressed: onRetry,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}
