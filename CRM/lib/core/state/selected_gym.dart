import 'package:flutter/foundation.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/gym_setup/data/models/employee_role.dart';
import 'package:crm/features/members/data/gym_api_client.dart';
import 'package:crm/features/members/data/gym_content_repository.dart';
import 'package:crm/features/members/data/gym_detail.dart';

/// The app-wide **selected gym** — and it carries **two distinct gym ids**,
/// because the CRM operates in two separate id spaces with no mapping:
///
/// - [gymId] — the **real gym UUID** (from `GET /api/v1/gyms/`). It scopes
///   every CRM member query (members list, member-detail roster, plans,
///   discounts). Set once at sign-in (or via the gym picker) through
///   [setActiveGym]. [role] is the caller's role at that gym.
/// - [videoGymId] — the **VideoService content key** (a string like `boxing`).
///   It drives the read-only member-app surfaces: the loyalty store, the videos
///   feed/content focus, the phone preview, and the dashboard's Upcoming
///   Classes card. (The Schedule screen now reads the real `classes` domain
///   scoped by [gymId], not this content key.) Picking a gym in the theme picker
///   records it here, applies its theme via [ThemeRuntime.selectDesign], and
///   fetches the whole [GymDetail] **once**.
///
/// The two ids never mix: passing the real [gymId] to the VideoService 404s,
/// and passing a [videoGymId] to a CRM member query is meaningless.
///
/// A plain global [ChangeNotifier] — the same shape as [ThemeRuntime]'s
/// listenable, not a state-management framework. Surfaces watch it with
/// `ListenableBuilder(listenable: selectedGym, ...)`.
class SelectedGym extends ChangeNotifier {
  SelectedGym({GymApiClient? client}) : _client = client ?? GymApiClient();

  final GymApiClient _client;

  // ── Real admin gym (FastApiBackend UUID) ──
  String? _gymId;
  EmployeeRole? _role;

  // ── VideoService content selection ──
  String? _videoGymId;
  String? _designId;
  String _displayName = '';

  GymDetail? _detail;
  bool _isLoading = false;
  Object? _error;

  /// The real gym UUID currently being administered; null until sign-in
  /// resolves the active gym. Scopes all CRM member queries.
  String? get gymId => _gymId;

  /// The caller's role at the active gym; null until [setActiveGym].
  EmployeeRole? get role => _role;

  /// The VideoService content gym id (the content key); null before first
  /// select. Drives the read-only member-app preview surfaces.
  String? get videoGymId => _videoGymId;
  String? get designId => _designId;
  String get displayName => _displayName;

  /// The fetched detail (rewards / classes / spec); null until it loads.
  GymDetail? get detail => _detail;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Record the active admin gym: the real gym UUID, its display name, and the
  /// caller's [role]. Set once at sign-in / via the gym picker. Independent of
  /// the VideoService content selection below — it does not touch [videoGymId]
  /// or the theme.
  void setActiveGym({
    required String gymId,
    required String displayName,
    required EmployeeRole role,
  }) {
    _gymId = gymId;
    _displayName = displayName;
    _role = role;
    notifyListeners();
  }

  /// Update the VideoService content gym id after a preset import. Optionally
  /// also applies a new [designId] theme when the import returns one.
  ///
  /// In the admin context ([gymId] is set), also re-fetches the real gym's
  /// showcase so the preview surfaces immediately reflect the imported content.
  /// In the public browser ([gymId] is null), the template catalog is already
  /// up-to-date — no re-fetch needed.
  ///
  /// This keeps the two id spaces ([gymId] / [videoGymId]) intact — only the
  /// video content key changes here; the real gym UUID is untouched.
  void setVideoGymId({
    required String videoGymId,
    String? designId,
  }) {
    _videoGymId = videoGymId;
    if (designId != null && designId.isNotEmpty) {
      _designId = designId;
      if (ThemeRuntime.activeDesignId != designId) {
        ThemeRuntime.selectDesign(designId);
      }
    }
    // Admin: re-fetch showcase so Loyalty/classes/schedule reflect the import.
    if (_gymId != null) {
      _fetchDetail(videoGymId);
    }
    notifyListeners();
  }

  /// Clear all selection on sign-out — both the admin gym ([gymId]/[role]) and
  /// the VideoService content selection — so the next authenticated session
  /// resolves gyms from scratch. Without this, [gymId] persists past logout and
  /// the auth gate skips the gym picker (it mounts the workspace whenever
  /// `gymId != null`), silently reusing the previous gym after a re-login. The
  /// counterpart to [setActiveGym]/[select]; called from the auth gate teardown.
  void reset() {
    _gymId = null;
    _role = null;
    _videoGymId = null;
    _designId = null;
    _displayName = '';
    _detail = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Select [style] from the picker: record its content gym, brand with its
  /// theme, and fetch its detail. No-op if it's already the selected content
  /// gym.
  void selectStyle(ThemeStyle style) => select(
    videoGymId: style.gymId,
    designId: style.id,
    displayName: style.displayName,
  );

  /// Select a VideoService content gym by its ids. [videoGymId] may be null when
  /// only the theme is known (a deep link); detail then waits for
  /// [reconcileFromCatalog] to supply it.
  void select({
    required String? videoGymId,
    required String designId,
    required String displayName,
  }) {
    final sameGym = _videoGymId == videoGymId && _designId == designId;
    if (sameGym && (_detail != null || _isLoading)) return;

    _videoGymId = videoGymId;
    _designId = designId;
    _displayName = displayName;

    // Drive branding; idempotent — skip when the engine is already on it.
    if (designId.isNotEmpty && ThemeRuntime.activeDesignId != designId) {
      ThemeRuntime.selectDesign(designId);
    }

    if (videoGymId == null || videoGymId.isEmpty) {
      _detail = null;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _fetchDetail(videoGymId);
  }

  Future<void> _fetchDetail(String videoGymId) async {
    _detail = null;
    _error = null;
    _isLoading = true;
    notifyListeners();
    if (_gymId != null) {
      // Admin path: fetch real gym showcase via authed ApiClient.
      // Guard staleness on the real gym UUID — if the admin switches gyms
      // (sign-out / gym picker) during the fetch, drop the stale result.
      final gymIdAtStart = _gymId!;
      try {
        final detail = await GymContentRepository(
          ApiClient(),
        ).fetchShowcase(gymIdAtStart);
        if (_gymId != gymIdAtStart) return;
        _detail = detail;
      } catch (e) {
        if (_gymId != gymIdAtStart) return;
        _error = e;
      } finally {
        if (_gymId == gymIdAtStart) {
          _isLoading = false;
          notifyListeners();
        }
      }
    } else {
      // Public browser path: fetch template by video_gym slug (unauthenticated).
      // Guard staleness on the slug — a newer picker selection supersedes this.
      try {
        final detail = await _client.fetchGym(videoGymId);
        if (_videoGymId != videoGymId) return;
        _detail = detail;
      } catch (e) {
        if (_videoGymId != videoGymId) return;
        _error = e;
      } finally {
        if (_videoGymId == videoGymId) {
          _isLoading = false;
          notifyListeners();
        }
      }
    }
  }

  /// Seed the content selection from a loaded gym catalog when only the theme is
  /// known (the initial or deep-linked case): find the catalog row for the
  /// intended design and select it. **Only fires when no content gym is selected
  /// yet** — once one is chosen (by the seed or an explicit pick) this never
  /// overrides it, so a pick can't be clobbered by a later page-load reconcile.
  /// Matches on the intended [_designId], not [ThemeRuntime.activeDesignId],
  /// which lags behind a pick (selectDesign is async).
  void reconcileFromCatalog(Iterable<ThemeStyle> items) {
    if (_videoGymId != null) return; // a content gym is locked in — don't override
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
