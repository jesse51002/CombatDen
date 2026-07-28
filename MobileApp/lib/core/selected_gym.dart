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
  ///
  /// Guarded on [ThemeRuntime.isReady]: the engine throws from
  /// `activeDesignName` until it has been initialized, and the package
  /// documents that every consumer that can build before the first
  /// `initialize` must check first. A topbar is exactly that consumer — it
  /// paints on screens the engine did not boot, and in a widget test the
  /// engine is never registered at all.
  String get displayName {
    final designName =
        ThemeRuntime.isReady ? ThemeRuntime.activeDesignName : null;
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
