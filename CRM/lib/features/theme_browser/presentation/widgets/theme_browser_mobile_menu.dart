import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The mobile nav dropdown — a frosted, full-width panel that drops below the
/// theme browser's top bar. A Flutter port of the landing nav's mobile menu
/// (`LandingPage/hifi/chrome.jsx`): the same links as rows with soft separators,
/// then a full-width gradient "Book a demo" CTA. The bar owns open/close; each
/// callback here is already wired to close-then-navigate.
class ThemeBrowserMobileMenu extends StatelessWidget {
  const ThemeBrowserMobileMenu({
    super.key,
    required this.links,
    required this.onBook,
  });

  /// (label, onTap) for each nav link row.
  final List<(String, VoidCallback)> links;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(color: DesignConstants.line),
            ),
            boxShadow: DesignConstants.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignConstants.paddingSmall,
              DesignConstants.spacingMedium,
              DesignConstants.paddingSmall,
              DesignConstants.spacingLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingLarge,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    for (final (label, onTap) in links)
                      _MobileNavLink(label: label, onTap: onTap),
                  ],
                ),
                AppPrimaryButton(
                  text: 'Book a demo',
                  fullWidth: true,
                  textStyle: DesignConstants.h2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignConstants.paddingSmall,
                    vertical: DesignConstants.spacingLarge,
                  ),
                  onPressed: onBook,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileNavLink extends StatelessWidget {
  const _MobileNavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: DesignConstants.lineSoft),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
        ),
        child: Text(label, style: DesignConstants.navLinkMobile),
      ),
    );
  }
}
