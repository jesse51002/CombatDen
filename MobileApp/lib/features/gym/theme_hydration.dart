import 'dart:developer';

import 'package:theme_flutter/customization_runtime.dart';

import 'package:mobile_app/core/app_config.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/gym/data/repositories/gym_showcase_repository.dart';

/// Re-themes the app to a gym's saved branding.
///
/// The real engine mechanism is `ThemeRuntime.selectDesign(designId)`
/// (`../ThemeService/ThemeFlutter/lib/customization_runtime.dart`) — it fetches
/// the design by id, adopts it, disk-caches it, and fires `ThemeRuntime.changes`
/// so the app re-themes live; it returns whether the switch took effect and
/// **never throws**. Resetting to the bundled default is the same call with
/// [AppConfig.designId] (there is no separate reset method on the engine).
class GymThemeHydration {
  final GymShowcaseRepository _repository;

  GymThemeHydration({GymShowcaseRepository? repository})
      : _repository = repository ??
            GymShowcaseRepository(apiClient: ApiClient());

  /// Fetch the gym's showcase and, when it carries a theme design id, apply it
  /// via `ThemeRuntime.selectDesign`. A null/empty id, or any failure (offline,
  /// unresolvable design), leaves the current/bundled theme in place — logged,
  /// never thrown, so theme hydration can never block boot.
  Future<void> applyForGym(String gymId) async {
    try {
      final showcase = await _repository.fetchShowcase(gymId);
      final designId = showcase.themeDesignId;
      if (designId == null || designId.isEmpty) return;
      await ThemeRuntime.selectDesign(designId);
    } catch (e, st) {
      log('GymThemeHydration.applyForGym failed', error: e, stackTrace: st);
    }
  }

  /// Reset the live theme to the bundled default — the sign-out counterpart to
  /// [applyForGym], so a re-login never shows the previous member's brand.
  static Future<void> reset() async {
    try {
      await ThemeRuntime.selectDesign(AppConfig.designId);
    } catch (e, st) {
      log('GymThemeHydration.reset failed', error: e, stackTrace: st);
    }
  }
}
