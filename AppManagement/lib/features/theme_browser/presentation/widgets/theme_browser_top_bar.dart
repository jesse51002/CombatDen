import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';

/// Top bar for the standalone theme-browser deployment.
///
/// **Placeholder.** The real bar will match the (not-yet-built) new landing
/// page; for now it's a minimal CombatDen wordmark plus a link back to the
/// marketing site, styled with the app's own [DesignConstants] (no new colors).
/// Swap this out once the new landing page exists. The back-link target is the
/// `LANDING_URL` dart-define.
class ThemeBrowserTopBar extends StatelessWidget {
  const ThemeBrowserTopBar({super.key});

  // Where "Back to CombatDen" goes. Overridden at build time, e.g.
  // `--dart-define=LANDING_URL=https://www.combatden.net` (the prod default).
  static const String _landingUrl = String.fromEnvironment(
    'LANDING_URL',
    defaultValue: 'https://www.combatden.net',
  );

  void _openLanding() {
    // Same-tab navigation — this is a "back to the site" link, not a new window.
    unawaited(
      launchUrl(Uri.parse(_landingUrl), webOnlyWindowName: '_self'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        border: Border(
          bottom: BorderSide(color: DesignConstants.divider),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingBig,
          vertical: DesignConstants.spacingLarge,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('CombatDen', style: DesignConstants.h1),
            AppOutlineButton(
              text: 'Back to CombatDen',
              icon: Icon(
                Symbols.arrow_back_sharp,
                size: DesignConstants.iconSizeMedium,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.text,
              ),
              onPressed: _openLanding,
            ),
          ],
        ),
      ),
    );
  }
}
