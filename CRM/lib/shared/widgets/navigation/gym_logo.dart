import 'package:flutter/material.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/theme/theme_image.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/showcase/showcase_slots.dart';

/// The managed gym's logo, sized to [size]. Resolves the **selected style's**
/// `logo_primary` slot — the same brand logo the member app shows — so the nav
/// chrome reflects the gym the admin is managing instead of a fixed brand.
/// Falls back to the bundled default until a gym is selected.
///
/// Rebrands on two signals: [selectedGym] (the pick) and, once the theme
/// engine is up, [ThemeRuntime.changes] (the new design's config finishing
/// loading). The second matters because the config load lands *after* the pick
/// notifies — listening to the pick alone leaves the logo one selection behind
/// until the engine catches up.
class GymLogo extends StatefulWidget {
  final double size;

  const GymLogo({super.key, required this.size});

  @override
  State<GymLogo> createState() => _GymLogoState();
}

class _GymLogoState extends State<GymLogo> {
  // The engine's change-listenable, held once attached so dispose can detach
  // without re-resolving it (it throws until the engine is registered).
  Listenable? _themeChanges;

  @override
  void initState() {
    super.initState();
    selectedGym.addListener(_onChanged);
    _attachThemeListener();
  }

  @override
  void dispose() {
    selectedGym.removeListener(_onChanged);
    _themeChanges?.removeListener(_onChanged);
    super.dispose();
  }

  // The theme engine initializes lazily (first time the Theme tab mounts), so
  // its listenable isn't there at app start. Attach as soon as it's ready —
  // re-tried on every [selectedGym] notify, since a pick guarantees the engine
  // is up by then.
  void _attachThemeListener() {
    if (_themeChanges != null || !ThemeRuntime.isReady) return;
    _themeChanges = ThemeRuntime.changes..addListener(_onChanged);
  }

  void _onChanged() {
    _attachThemeListener();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Image(
        image: ThemeImage.image(
          ShowcaseSlots.logoPrimary,
          fallback: const AssetImage('assets/images/apexmma-logo-simple.png'),
        ),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
      ),
    );
  }
}
