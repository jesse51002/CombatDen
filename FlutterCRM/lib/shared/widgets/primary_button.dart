import 'package:flutter/material.dart';
import 'package:crm/core/constants/design_constants.dart';

/// Primary action button with loading state
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool fullWidth;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: DesignConstants.primaryColor,
        foregroundColor: DesignConstants.text,
        disabledBackgroundColor: DesignConstants.primaryColor.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          side: BorderSide(
            color: DesignConstants.buttonStroke,
            width: DesignConstants.buttonBorderSize,
          ),
        ),
        elevation: 0,
      ),
      child: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(DesignConstants.text),
              ),
            )
          : Text(
              text,
              style: DesignConstants.pBig.copyWith(color: DesignConstants.text),
            ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }
}
