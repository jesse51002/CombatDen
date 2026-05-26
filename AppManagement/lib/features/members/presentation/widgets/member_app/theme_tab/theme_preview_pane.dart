import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/phone_frame.dart';
import 'package:customization_engine/customization_runtime.dart';
import 'package:customization_engine/showcase/showcase_screen.dart';

/// The left pane: a large phone mockup that fills the available space,
/// showing the active showcase screen (re-themed live, animation looping),
/// with prev/next arrows, a tappable view list, and an "edit gym name / logo"
/// button beneath it.
class ThemePreviewPane extends StatelessWidget {
  const ThemePreviewPane({
    super.key,
    required this.engineReady,
    required this.slide,
    required this.gymName,
    required this.gymLogo,
    required this.onPrev,
    required this.onNext,
    required this.onSelect,
    required this.onEditBranding,
  });

  final Future<void> engineReady;
  final int slide;
  final String gymName;
  final ImageProvider gymLogo;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onSelect;
  final VoidCallback onEditBranding;

  @override
  Widget build(BuildContext context) {
    final screen = ShowcaseScreen.values[slide];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          child: Center(
            child: PhoneFrame(
              child: _PreviewContent(
                engineReady: engineReady,
                screen: screen,
                gymName: gymName,
                gymLogo: gymLogo,
              ),
            ),
          ),
        ),
        _SlideControls(
          slide: slide,
          onPrev: onPrev,
          onNext: onNext,
          onSelect: onSelect,
        ),
        AppOutlineButton(
          text: 'Edit gym name / logo',
          onPressed: onEditBranding,
        ),
      ],
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({
    required this.engineReady,
    required this.screen,
    required this.gymName,
    required this.gymLogo,
  });

  final Future<void> engineReady;
  final ShowcaseScreen screen;
  final String gymName;
  final ImageProvider gymLogo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: engineReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ColoredBox(
            color: DesignConstants.card,
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              ),
            ),
          );
        }
        return ListenableBuilder(
          listenable: CustomizationRuntime.changes,
          builder: (context, _) {
            // Re-key on theme + slide so the showcase restarts its
            // animation fresh whenever either changes.
            return KeyedSubtree(
              key: ValueKey('${CustomizationRuntime.activeDesignId}-$screen'),
              child: screen.build(gymName: gymName, gymLogo: gymLogo),
            );
          },
        );
      },
    );
  }
}

class _SlideControls extends StatelessWidget {
  const _SlideControls({
    required this.slide,
    required this.onPrev,
    required this.onNext,
    required this.onSelect,
  });

  final int slide;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        _ArrowButton(icon: Symbols.chevron_left_sharp, onTap: onPrev),
        Flexible(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: DesignConstants.spacingSmall,
            runSpacing: DesignConstants.spacingSmall,
            children: [
              for (final s in ShowcaseScreen.values)
                _ViewChip(
                  label: s.label,
                  isActive: s.index == slide,
                  onTap: () => onSelect(s.index),
                ),
            ],
          ),
        ),
        _ArrowButton(icon: Symbols.chevron_right_sharp, onTap: onNext),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Icon(
          icon,
          color: DesignConstants.text,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeLarge,
        ),
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: isActive ? DesignConstants.primaryColor : DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Text(
          label,
          style: DesignConstants.h3.copyWith(
            color: isActive
                ? DesignConstants.backgroundColor
                : DesignConstants.text,
          ),
        ),
      ),
    );
  }
}
