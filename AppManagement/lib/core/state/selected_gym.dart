import 'package:flutter/foundation.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

import 'package:app_management/features/members/data/gym_api_client.dart';
import 'package:app_management/features/members/data/gym_detail.dart';

/// The app-wide **selected gym** — the one global the member-app surfaces read.
///
/// The gym is the unit: it carries its theme (for branding) AND its content
/// (rewards / classes / feed spec). Picking a gym in the theme picker records
/// it here, applies its theme via [ThemeRuntime.selectDesign], and fetches the
/// whole [GymDetail] **once**; the loyalty store, the videos content focus, and
/// the phone preview then read it from memory. The video feed is fetched
/// separately by `gymId` (it pages).
///
/// A plain global [ChangeNotifier] — the same shape as [ThemeRuntime]'s
/// listenable, not a state-management framework. Surfaces watch it with
/// `ListenableBuilder(listenable: selectedGym, ...)`.
class SelectedGym extends ChangeNotifier {
  SelectedGym({GymApiClient? client}) : _client = client ?? GymApiClient();

  final GymApiClient _client;

  String? _gymId;
  String? _designId;
  String _displayName = '';

  GymDetail? _detail;
  bool _isLoading = false;
  Object? _error;

  /// The gym id currently selected (the content key); null before first select.
  String? get gymId => _gymId;
  String? get designId => _designId;
  String get displayName => _displayName;

  /// The fetched detail (rewards / classes / spec); null until it loads.
  GymDetail? get detail => _detail;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Select [style] from the picker: record it, brand with its theme, and fetch
  /// its detail. No-op if it's already the selected gym.
  void selectStyle(ThemeStyle style) => select(
    gymId: style.gymId,
    designId: style.id,
    displayName: style.displayName,
  );

  /// Select a gym by its ids. [gymId] may be null when only the theme is known
  /// (a deep link); detail then waits for [reconcileFromCatalog] to supply it.
  void select({
    required String? gymId,
    required String designId,
    required String displayName,
  }) {
    final sameGym = _gymId == gymId && _designId == designId;
    if (sameGym && (_detail != null || _isLoading)) return;

    _gymId = gymId;
    _designId = designId;
    _displayName = displayName;

    // Drive branding; idempotent — skip when the engine is already on it.
    if (designId.isNotEmpty && ThemeRuntime.activeDesignId != designId) {
      ThemeRuntime.selectDesign(designId);
    }

    if (gymId == null || gymId.isEmpty) {
      _detail = null;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _fetchDetail(gymId);
  }

  Future<void> _fetchDetail(String gymId) async {
    _detail = null;
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      final detail = await _client.fetchGym(gymId);
      // A newer selection may have superseded this fetch — drop the stale one.
      if (_gymId != gymId) return;
      _detail = detail;
    } catch (e) {
      if (_gymId != gymId) return;
      _error = e;
    } finally {
      if (_gymId == gymId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Seed the selection from a loaded gym catalog when only the theme is known
  /// (the initial or deep-linked case): find the catalog row for the intended
  /// design and select it. **Only fires when no gym is selected yet** — once a
  /// gym is chosen (by the seed or an explicit pick) this never overrides it,
  /// so a pick can't be clobbered by a later page-load reconcile. Matches on the
  /// intended [_designId], not [ThemeRuntime.activeDesignId], which lags behind
  /// a pick (selectDesign is async).
  void reconcileFromCatalog(Iterable<ThemeStyle> items) {
    if (_gymId != null) return; // a gym is already locked in — don't override
    final target = _designId ?? ThemeRuntime.activeDesignId;
    if (target == null || target.isEmpty) return;
    for (final s in items) {
      if (s.id == target && (s.gymId?.isNotEmpty ?? false)) {
        selectStyle(s);
        return;
      }
    }
  }
}

/// The one process-wide selected gym, watched by the member-app surfaces.
final SelectedGym selectedGym = SelectedGym();
