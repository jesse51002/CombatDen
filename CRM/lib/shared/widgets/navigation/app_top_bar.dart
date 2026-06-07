import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/navigation/gym_logo.dart';
import 'package:crm/shared/widgets/navigation/nav_actions.dart';
import 'package:crm/shared/widgets/navigation/nav_sections.dart';
import 'package:crm/shared/widgets/navigation/sections_mobile_menu.dart';

/// Mobile nav chrome, shown below [DesignConstants.navMobileBreakpoint] in
/// place of the desktop [SectionsBar]. A frosted top bar carrying the managed
/// gym's logo + the current section title on the left and a hamburger on the
/// right; tapping the hamburger drops the full-width [SectionsMobileMenu] via
/// the app [Overlay] (tap-outside to dismiss).
///
/// `AppShell` only renders this below the breakpoint, so resizing back up to
/// desktop unmounts it — [dispose] tears down any open menu, no resize
/// handling needed here.
class AppTopBar extends StatefulWidget {
  final String? activeRoute;

  const AppTopBar({super.key, this.activeRoute});

  @override
  State<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends State<AppTopBar> {
  OverlayEntry? _menu;

  bool get _isOpen => _menu != null;

  /// Label of the section the current route belongs to, shown beside the logo.
  /// `null` when the route isn't a primary section (the title is then omitted).
  String? get _activeLabel {
    for (final section in kNavSections) {
      if (section.route != null && section.route == widget.activeRoute) {
        return section.label;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _menu?.remove();
    _menu = null;
    super.dispose();
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
            child: SectionsMobileMenu(
              activeRoute: widget.activeRoute,
              onSelect: (section) {
                _closeMenu();
                onNavSectionTap(context, section);
              },
              onLogout: () {
                _closeMenu();
                confirmAndLogout(context);
              },
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

  @override
  Widget build(BuildContext context) {
    final label = _activeLabel;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DesignConstants.card.withValues(alpha: 0.85),
            border: Border(
              bottom: BorderSide(color: DesignConstants.line),
            ),
          ),
          child: SizedBox(
            height: DesignConstants.navHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingSmall,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DesignConstants.spacingMedium,
                    children: [
                      const GymLogo(size: DesignConstants.iconSizeBig),
                      if (label != null)
                        Text(label, style: DesignConstants.h1),
                    ],
                  ),
                  _MenuButton(open: _isOpen, onTap: _toggleMenu),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hamburger toggle for the mobile top bar.
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
