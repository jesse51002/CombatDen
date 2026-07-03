import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/members/data/showcase_defaults.dart';
import 'package:crm/features/members/presentation/widgets/member_app/theme_tab/set_app_theme_button.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/phone_frame.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:crm/showcase/showcase_content.dart';
import 'package:crm/showcase/showcase_group_defaults.dart';
import 'package:crm/showcase/showcase_screen.dart';

// Phone-like page push between showcase screens. Same spirit (and curve) as
// theme_grid.dart's scroll animation — a local const, not a design token.
const Duration _kSlideDuration = Duration(milliseconds: 300);

/// Returns [defaults] when [real] is null or empty; when [real] has exactly
/// one item, repeats it across all [defaults.length] slots so the single
/// item fills every schedule/store card instead of appearing only once.
List<T> _fillSlots<T>(List<T>? real, List<T> defaults) {
  if (real == null || real.isEmpty) return defaults;
  if (real.length == 1) return List.filled(defaults.length, real[0]);
  return real;
}

/// The left pane: a large phone mockup that fills the available space,
/// showing the active showcase screen (re-themed live, animation looping),
/// with prev/next arrows and a tappable view list beneath it. The gym name +
/// logo shown in the mock are edited via the "Edit gym name / logo" button
/// under the controls ([onEditBranding], admin context only — the public
/// theme browser passes null and gets no button).
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
    this.onEditBranding,
  });

  final Future<void> engineReady;
  final int slide;
  final bool forward;
  final String gymName;
  final ImageProvider? gymLogo;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onSelect;
  final VoidCallback? onEditBranding;

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
        // Admin-only primary action: persist the previewed theme as the gym's
        // app branding. Self-hides in the public browser (guarded here too so
        // no spurious column gap is left where it would sit).
        if (selectedGym.gymId != null) const SetAppThemeButton(),
        if (onEditBranding != null)
          AppOutlineButton(
            text: 'Edit gym name / logo',
            icon: Icon(
              Symbols.edit_sharp,
              size: DesignConstants.iconSizeMedium,
              weight: DesignConstants.iconWeight,
            ),
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
  final ImageProvider? gymLogo;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: engineReady,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ColoredBox(
            color: DesignConstants.card,
            child: const Center(child: AppSpinner()),
          );
        }
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return FutureBuilder<ShowcaseDefaults>(
          // Cached app-side; the same future instance is returned every build so
          // this never re-fetches. Renders bundled fallbacks until it resolves.
          future: loadShowcaseDefaults(),
          builder: (context, defaultsSnapshot) {
            final showcaseDefaults = defaultsSnapshot.data;
            return ListenableBuilder(
              // Re-render on a theme switch (branding) AND on a gym switch / its
              // detail loading (so Store + Home surfaces get the real content).
              listenable: Listenable.merge([ThemeRuntime.changes, selectedGym]),
              builder: (context, _) => _buildPreview(
                context,
                reduceMotion: reduceMotion,
                showcaseDefaults: showcaseDefaults,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPreview(
    BuildContext context, {
    required bool reduceMotion,
    required ShowcaseDefaults? showcaseDefaults,
  }) {
    final detail = selectedGym.detail;
    final rawRewards = detail?.rewards
        .map(
          (r) => ShowcaseReward(
            title: r.title,
            imageUrl: r.imageUrl,
            priceLabel: r.priceLabel,
            pointsCost: r.pointsCost,
          ),
        )
        .toList();
    final rawClasses = detail?.classes
        .map(
          (c) => ShowcaseClassInfo(
            name: c.name,
            imageUrl: c.imageUrl,
            instructorName: c.instructorName,
          ),
        )
        .toList();

    // Category-keyed demo defaults for when real data is absent (always so in
    // the public browser). Prefer the picked theme's category; fall back to the
    // legacy videoGymId group when no theme category is known yet. The fetched
    // showcase-defaults win; the bundled `kShowcase*ByGroup` constants are the
    // last-resort offline fallback (fetch failure / category absent). A single
    // real item is repeated across all 4 slots so it fills every card.
    final category =
        selectedGym.themeCategory ?? showcaseGroupFor(selectedGym.videoGymId);
    final fetched = showcaseDefaults?.forCategory(category);
    final defaultClasses = fetched?.classes ??
        (kShowcaseClassesByGroup[category] ??
            kShowcaseClassesByGroup[kDefaultShowcaseGroup]!);
    final defaultRewards = fetched?.rewards ??
        (kShowcaseRewardsByGroup[category] ??
            kShowcaseRewardsByGroup[kDefaultShowcaseGroup]!);
    final classes = _fillSlots(rawClasses, defaultClasses);
    final rewards = _fillSlots(rawRewards, defaultRewards);

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
            themeTabPreview: true,
          ),
        ),
      ),
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
                ? DesignConstants.onAccent
                : DesignConstants.text,
          ),
        ),
      ),
    );
  }
}
