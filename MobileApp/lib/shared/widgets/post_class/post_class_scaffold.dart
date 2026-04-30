import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Scaffold for the post-class celebration cards (Streak, Wins, Points,
/// Rewards, Rank). Provides a fixed body area, an optional close (X) button
/// in the upper-right, and a full-width primary CTA pinned to the bottom.
///
/// Each celebration card supplies its own [body] (centered illustration +
/// copy) and CTA wiring; this widget owns only the chrome.
class PostClassScaffold extends StatelessWidget {
  const PostClassScaffold({
    super.key,
    required this.body,
    required this.ctaLabel,
    required this.onCtaPressed,
    this.header,
    this.onClose,
  });

  final Widget body;
  final String ctaLabel;
  final VoidCallback onCtaPressed;
  final Widget? header;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: DesignConstants.spacingBig,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                ?header,
                Expanded(
                  child: Center(child: body),
                ),
                AppPrimaryButton(
                  text: ctaLabel,
                  onPressed: onCtaPressed,
                  fullWidth: true,
                  borderRadius: DesignConstants.radiusBig,
                  textStyle: DesignConstants.h2,
                ),
              ],
            ),
          ),
          if (onClose case final close?)
            Positioned(
              top: DesignConstants.spacingLarge,
              right: DesignConstants.spacingLarge,
              child: IconButton(
                onPressed: close,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Symbols.close_sharp,
                  color: DesignConstants.text,
                  weight: DesignConstants.iconWeight,
                  size: DesignConstants.iconSizeXl,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
