import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/state/selected_gym.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/phone_frame.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/showcase/showcase_content.dart';
import 'package:theme_flutter/showcase/showcase_screen.dart';

// Phone-like page push between showcase screens. Same spirit (and curve) as
// theme_grid.dart's scroll animation — a local const, not a design token.
const Duration _kSlideDuration = Duration(milliseconds: 300);

/// The left pane: a large phone mockup that fills the available space,
/// showing the active showcase screen (re-themed live, animation looping),
/// with prev/next arrows, a tappable view list, and an "edit gym name / logo"
/// button beneath it.
class ThemePreviewPane extends StatelessWidget {
  const ThemePreviewPane({
    super.key,
    required this.engineReady,
    required this.slide,
    required this.forward,
    required this.gymName,
    required this.gymLogo,
    required this.onPrev,
    required this.onNext,
    required this.onSelect,
    required this.onEditBranding,
  });

  final Future<void> engineReady;
  final int slide;
  final bool forward;
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
                forward: forward,
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
    required this.forward,
    required this.gymName,
    required this.gymLogo,
  });

  final Future<void> engineReady;
  final ShowcaseScreen screen;
  final bool forward;
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
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return ListenableBuilder(
          // Re-render on a theme switch (branding) AND on a gym switch / its
          // detail loading (so the Store + Home surfaces get the real content).
          listenable: Listenable.merge([ThemeRuntime.changes, selectedGym]),
          builder: (context, _) {
            final detail = selectedGym.detail;
            final rewards = detail?.rewards
                .map(
                  (r) => ShowcaseReward(
                    title: r.title,
                    imageUrl: r.imageUrl,
                    priceLabel: r.priceLabel,
                    pointsCost: r.pointsCost,
                  ),
                )
                .toList();
            final classes = detail?.classes
                .map(
                  (c) => ShowcaseClassInfo(
                    name: c.name,
                    imageUrl: c.imageUrl,
                    instructorName: c.instructorName,
                  ),
                )
                .toList();
            return AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : _kSlideDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => DualTransitionBuilder(
                animation: animation,
                // Entering screen.
                forwardBuilder: (context, anim, child) => SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(forward ? 1.0 : -1.0, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
                // Exiting screen (slides the opposite way).
                reverseBuilder: (context, anim, child) => SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset.zero,
                    end: Offset(forward ? -1.0 : 1.0, 0),
                  ).animate(anim),
                  child: child,
                ),
                child: child,
              ),
              child: KeyedSubtree(
                // Slide change drives the switch; a theme change keeps this
                // key, so it re-themes in place (no slide).
                key: ValueKey(screen),
                child: KeyedSubtree(
                  // Restart the showcase's own animation on theme change.
                  key: ValueKey('${ThemeRuntime.activeDesignId}-$screen'),
                  child: screen.build(
                    gymName: gymName,
                    gymLogo: gymLogo,
                    rewards: rewards,
                    classes: classes,
                  ),
                ),
              ),
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
