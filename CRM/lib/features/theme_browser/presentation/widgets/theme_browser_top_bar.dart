import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/theme_browser/presentation/widgets/theme_browser_mobile_menu.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Top bar for the standalone theme-browser deployment — a Flutter port of the
/// landing page's sticky nav (`LandingPage/hifi/chrome.jsx` `GWNav`): a frosted
/// translucent bar with the CombatDen wordmark on the left and the Home /
/// Pricing links + a gradient "Book a demo" CTA on the right, so the browser
/// reads as one continuous site with the marketing page.
///
/// Responsive (mirrors the landing nav): below [DesignConstants.navMobileBreakpoint]
/// the links + CTA collapse into a hamburger that toggles a full-width dropdown
/// ([ThemeBrowserMobileMenu]) via the app [Overlay].
///
/// Link targets are overridable at build time via dart-defines (defaults are
/// the prod marketing URLs):
///   `--dart-define=LANDING_URL=…`  (Home + wordmark)
///   `--dart-define=PRICING_URL=…`  (Pricing)
///   `--dart-define=BOOK_URL=…`     (Book a demo)
class ThemeBrowserTopBar extends StatefulWidget {
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

  @override
  State<ThemeBrowserTopBar> createState() => _ThemeBrowserTopBarState();
}

class _ThemeBrowserTopBarState extends State<ThemeBrowserTopBar> {
  OverlayEntry? _menu;

  bool get _isOpen => _menu != null;

  @override
  void dispose() {
    _menu?.remove();
    _menu = null;
    super.dispose();
  }

  void _openUrl(String url) {
    // Same-tab navigation — these are "back to the marketing site" links.
    unawaited(launchUrl(Uri.parse(url), webOnlyWindowName: '_self'));
  }

  void _toggleMenu() => _isOpen ? _closeMenu() : _openMenu();

  void _openMenu() {
    final overlay = Overlay.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    _menu = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Tap-outside barrier.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
            ),
          ),
          Positioned(
            top: topInset + DesignConstants.navHeight,
            left: 0,
            right: 0,
            child: ThemeBrowserMobileMenu(
              links: [
                ('Home', () => _navigate(ThemeBrowserTopBar._landingUrl)),
                ('Pricing', () => _navigate(ThemeBrowserTopBar._pricingUrl)),
              ],
              onBook: () => _navigate(ThemeBrowserTopBar._bookUrl),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_menu!);
    setState(() {});
  }

  void _closeMenu() {
    _menu?.remove();
    _menu = null;
    if (mounted) setState(() {});
  }

  void _navigate(String url) {
    _closeMenu();
    _openUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < DesignConstants.navMobileBreakpoint;
        // Resizing back up out of mobile dismisses an open menu.
        if (!isMobile && _isOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _closeMenu();
          });
        }
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
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile
                            ? DesignConstants.paddingSmall
                            : DesignConstants.paddingBig,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _Wordmark(
                            onTap: () =>
                                _openUrl(ThemeBrowserTopBar._landingUrl),
                          ),
                          if (isMobile)
                            _MenuButton(open: _isOpen, onTap: _toggleMenu)
                          else
                            _NavActions(
                              onHome: () =>
                                  _openUrl(ThemeBrowserTopBar._landingUrl),
                              onPricing: () =>
                                  _openUrl(ThemeBrowserTopBar._pricingUrl),
                              onBook: () =>
                                  _openUrl(ThemeBrowserTopBar._bookUrl),
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
      },
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

/// Hamburger toggle shown below the mobile breakpoint.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        width: DesignConstants.navMenuButtonSize,
        height: DesignConstants.navMenuButtonSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DesignConstants.surface,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(color: DesignConstants.line),
          boxShadow: DesignConstants.controlShadow,
        ),
        child: Icon(
          open ? Symbols.close_sharp : Symbols.menu_sharp,
          color: DesignConstants.text,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeLarge,
        ),
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
