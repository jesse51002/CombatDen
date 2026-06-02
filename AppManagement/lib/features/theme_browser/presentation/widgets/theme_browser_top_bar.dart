import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';

/// Top bar for the standalone theme-browser deployment — a Flutter port of the
/// landing page's sticky nav (`LandingPage/hifi/chrome.jsx` `GWNav`): a frosted
/// translucent bar with the CombatDen wordmark on the left and the Home /
/// Pricing links + a gradient "Book a demo" CTA on the right, so the browser
/// reads as one continuous site with the marketing page.
///
/// Link targets are overridable at build time via dart-defines (defaults are
/// the prod marketing URLs):
///   `--dart-define=LANDING_URL=…`  (Home + wordmark)
///   `--dart-define=PRICING_URL=…`  (Pricing)
///   `--dart-define=BOOK_URL=…`     (Book a demo)
class ThemeBrowserTopBar extends StatelessWidget {
  const ThemeBrowserTopBar({super.key});

  static const String _landingUrl = String.fromEnvironment(
    'LANDING_URL',
    defaultValue: 'https://www.combatden.net',
  );
  static const String _pricingUrl = String.fromEnvironment(
    'PRICING_URL',
    defaultValue: 'https://www.combatden.net/pricing.html',
  );
  static const String _bookUrl = String.fromEnvironment(
    'BOOK_URL',
    defaultValue: 'https://www.combatden.net/#book',
  );

  void _open(String url) {
    // Same-tab navigation — these are "back to the marketing site" links.
    unawaited(launchUrl(Uri.parse(url), webOnlyWindowName: '_self'));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DesignConstants.backgroundColor.withValues(alpha: 0.78),
            border: const Border(
              bottom: BorderSide(color: DesignConstants.line),
            ),
          ),
          child: SizedBox(
            height: DesignConstants.navHeight,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignConstants.navMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignConstants.paddingBig,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Wordmark(onTap: () => _open(_landingUrl)),
                      _NavActions(
                        onHome: () => _open(_landingUrl),
                        onPricing: () => _open(_pricingUrl),
                        onBook: () => _open(_bookUrl),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          Image.asset(
            'assets/images/combatden_logo.png',
            height: DesignConstants.iconSizeBig,
          ),
          Text('CombatDen', style: DesignConstants.navWordmark),
        ],
      ),
    );
  }
}

class _NavActions extends StatelessWidget {
  const _NavActions({
    required this.onHome,
    required this.onPricing,
    required this.onBook,
  });

  final VoidCallback onHome;
  final VoidCallback onPricing;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: [
        _NavLink(label: 'Home', onTap: onHome),
        _NavLink(label: 'Pricing', onTap: onPricing),
        AppPrimaryButton(text: 'Book a demo', onPressed: onBook),
      ],
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.spacingSmall),
        child: Text(label, style: DesignConstants.navLink),
      ),
    );
  }
}
