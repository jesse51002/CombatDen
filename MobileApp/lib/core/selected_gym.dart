import 'package:theme_flutter/customization_runtime.dart';

/// The gym this session is showing — chosen on the gym-select screen, then the
/// single source every content surface reads (videos, classes, rewards all
/// fetch by [gymId]). There is **no hardcoded default**: it starts null (the
/// app opens on the gym-select screen) and is set by picking a gym.
///
/// Picking also re-brands via [ThemeRuntime.selectDesign] (the gym carries its
/// theme), which re-keys the app and rebuilds every screen — so the fresh
/// screens fetch this gym's content. A plain singleton, not a notifier: the
/// re-key drives the rebuild, this just holds the id the rebuilt screens read.
class SelectedGym {
  SelectedGym._();

  static final SelectedGym instance = SelectedGym._();

  String? _gymId;
  String? _theme;
  String? _pickedName;

  /// The selected gym's id (the content key); null until a gym is picked.
  String? get gymId => _gymId;

  /// The selected gym's theme (the design id it brands with).
  String? get theme => _theme;

  /// The gym's display name to title every brand surface (topbars) with. The
  /// loaded design's own name (e.g. "Apex MMA") is the source of truth; the
  /// picker label is the fallback for the brief window before the theme
  /// finishes loading (or if the engine never loaded at all).
  String get displayName {
    // `activeDesignName` reads the engine's service out of DI and
    // THROWS while it is unregistered, which is exactly the "engine
    // never loaded at all" case this fallback is for (and the case
    // every widget test runs in). `ThemeRuntime.isReady` is the guard
    // the engine documents for consumers that can build first.
    final designName = ThemeRuntime.isReady
        ? ThemeRuntime.activeDesignName
        : null;
    if (designName != null && designName.isNotEmpty) return designName;
    return _pickedName ?? '';
  }

  /// Pick a gym: record its id + theme (+ the picker label) and re-brand to
  /// that theme.
  void select({
    required String? gymId,
    required String theme,
    String? name,
  }) {
    _gymId = (gymId != null && gymId.isNotEmpty) ? gymId : null;
    _theme = theme;
    _pickedName = (name != null && name.isNotEmpty) ? name : null;
    if (theme.isNotEmpty && ThemeRuntime.activeDesignId != theme) {
      ThemeRuntime.selectDesign(theme);
    }
  }
}

/// The one process-wide selected gym.
final SelectedGym selectedGym = SelectedGym.instance;
