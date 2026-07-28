import 'package:flutter/foundation.dart';

/// Runtime, in-app overrides for the layout and motion format slots.
///
/// This is the DEV picker's backing store and it sits at the top of the
/// resolution order:
///
///   1. a widget's `formatOverride` argument   (tests, preview sheets)
///   2. this store                             (the in-app dev panel)
///   3. `--dart-define`                        (deterministic launches)
///   4. the tenant's customization slot        (production)
///   5. the value that ships today             (fallback)
///
/// It exists because reviewing a layout should not cost a rebuild.
/// Switching a format here notifies listeners and the affected widgets
/// re-resolve in place, so navigation state is preserved — you stay on
/// the screen you are judging instead of being thrown back to Home.
///
/// Deliberately in-memory only. Nothing here is persisted or ever read
/// in a release build (the panel that writes it is behind [kDebugMode]),
/// so it cannot leak into what a real tenant sees.
class FormatStore extends ChangeNotifier {
  FormatStore._();

  static final FormatStore instance = FormatStore._();

  final Map<String, String> _overrides = {};

  /// The override for [slot], or null when the picker has not set one.
  String? read(String slot) => _overrides[slot];

  /// Every slot the picker currently pins.
  Map<String, String> get active => Map.unmodifiable(_overrides);

  bool get isEmpty => _overrides.isEmpty;

  /// Pin [slot] to [value]; pass null to release it back to the normal
  /// resolution order.
  void set(String slot, String? value) {
    if (value == null) {
      if (_overrides.remove(slot) == null) return;
    } else {
      if (_overrides[slot] == value) return;
      _overrides[slot] = value;
    }
    notifyListeners();
  }

  /// Release every pinned slot.
  void reset() {
    if (_overrides.isEmpty) return;
    _overrides.clear();
    notifyListeners();
  }
}
