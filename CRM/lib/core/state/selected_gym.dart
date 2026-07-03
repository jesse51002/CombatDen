import 'package:flutter/foundation.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/gym_setup/data/models/employee_role.dart';
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
///   It drives the read-only member-app content surfaces: the loyalty store,
///   the videos feed/content focus, the phone preview. Seeded to a default at
///   sign-in and overridden only by a preset import ([setVideoGymId]).
///
/// **Theme selection is decoupled from both ids.** Picking a theme in the
/// picker records only the design id ([designId]) and its [themeCategory] and
/// re-brands the live preview via [ThemeRuntime.selectDesign] — it does NOT
/// touch [videoGymId], [detail], or [displayName]. The theme catalog is now the
/// ThemeService styles list, which is gym-agnostic.
///
/// The two ids never mix: passing the real [gymId] to the VideoService 404s,
/// and passing a [videoGymId] to a CRM member query is meaningless.
///
/// A plain global [ChangeNotifier] — the same shape as [ThemeRuntime]'s
/// listenable, not a state-management framework. Surfaces watch it with
/// `ListenableBuilder(listenable: selectedGym, ...)`.
class SelectedGym extends ChangeNotifier {
  // ── Real admin gym (FastApiBackend UUID) ──
  String? _gymId;
  EmployeeRole? _role;
  String? _timezone;

  /// The gym's persisted ThemeService design id (`gyms.theme_design_id`),
  /// hydrated at login. The "Set as app theme" action compares the previewed
  /// design against this to know whether the pick is already saved.
  String? _savedThemeDesignId;

  // ── VideoService content selection ──
  String? _videoGymId;

  // ── Live theme selection (decoupled from the gym) ──
  String? _designId;
  String? _themeCategory;
  String _displayName = '';

  GymDetail? _detail;
  bool _isLoading = false;
  Object? _error;

  /// The real gym UUID currently being administered; null until sign-in
  /// resolves the active gym. Scopes all CRM member queries.
  String? get gymId => _gymId;

  /// The caller's role at the active gym; null until [setActiveGym].
  EmployeeRole? get role => _role;

  /// The active gym's IANA timezone (e.g. `America/Chicago`); null until
  /// [setActiveGym]. Class times, the schedule board, and check-in windows
  /// follow this zone. Updated in place by [updateTimezone] when the Settings
  /// timezone save commits.
  String? get timezone => _timezone;

  /// The gym's persisted ThemeService design id; null until it loads (or until
  /// a theme has ever been saved). Updated in place by [updateSavedThemeDesignId]
  /// when the "Set as app theme" save commits.
  String? get savedThemeDesignId => _savedThemeDesignId;

  /// The VideoService content gym id (the content key); null before first
  /// select. Drives the read-only member-app content surfaces.
  String? get videoGymId => _videoGymId;

  /// The currently-previewed ThemeService design id; null before first pick.
  String? get designId => _designId;

  /// The picked theme's showcase category (Fighting/Yoga/…); null until a theme
  /// is picked or [reconcileFromCatalog] resolves it for a seeded/deep-linked
  /// design. Keys the phone-preview's demo class/reward defaults.
  String? get themeCategory => _themeCategory;

  String get displayName => _displayName;

  /// The fetched detail (rewards / classes / spec); null until it loads.
  GymDetail? get detail => _detail;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Record the active admin gym: the real gym UUID, its display name, the
  /// caller's [role], the gym's IANA [timezone], and the gym's persisted
  /// ThemeService design id ([savedThemeDesignId]). Set once at sign-in / via
  /// the gym picker. Independent of the VideoService content selection and the
  /// live theme — it does not touch [videoGymId] or apply a theme (the theme
  /// runtime isn't initialized yet at login).
  void setActiveGym({
    required String gymId,
    required String displayName,
    required EmployeeRole role,
    required String timezone,
    String? savedThemeDesignId,
  }) {
    _gymId = gymId;
    _displayName = displayName;
    _role = role;
    _timezone = timezone;
    _savedThemeDesignId = savedThemeDesignId;
    notifyListeners();
  }

  /// Update the active gym's timezone after the backend save commits (the
  /// Settings save is NOT optimistic — this is only called on success).
  void updateTimezone(String timezone) {
    _timezone = timezone;
    notifyListeners();
  }

  /// Record the gym's persisted ThemeService design id after the "Set as app
  /// theme" save commits (NOT optimistic — only called on success).
  void updateSavedThemeDesignId(String themeDesignId) {
    _savedThemeDesignId = themeDesignId;
    notifyListeners();
  }

  /// Set (or re-seed) the VideoService content gym id and, in the admin context
  /// (`gymId != null`), re-fetch the real gym's showcase so the preview surfaces
  /// immediately reflect it. Called once at sign-in (seed with the default
  /// content gym) and again after a preset import.
  ///
  /// **Does NOT touch the theme.** Theme selection/application is the Theme
  /// tab's job — a preset import from Settings only changes content, never the
  /// live design. (The imported theme id is persisted server-side on the gym;
  /// the Theme tab reads/applies it.) This avoids the engine-not-ready throw
  /// that would otherwise surface when importing before the Theme tab has booted
  /// the theme runtime.
  ///
  /// Keeps the two id spaces ([gymId] / [videoGymId]) intact — only the video
  /// content key changes here; the real gym UUID is untouched.
  void setVideoGymId({required String videoGymId}) {
    _videoGymId = videoGymId;
    // Admin: re-fetch showcase so Loyalty/classes/schedule reflect the content.
    if (_gymId != null) {
      _fetchDetail();
    }
    notifyListeners();
  }

  /// Clear all selection on sign-out — the admin gym ([gymId]/[role]/…), the
  /// VideoService content selection, and the live theme selection — so the next
  /// authenticated session resolves gyms from scratch. Without this, [gymId]
  /// persists past logout and the auth gate skips the gym picker (it mounts the
  /// workspace whenever `gymId != null`), silently reusing the previous gym
  /// after a re-login. The counterpart to [setActiveGym]; called from the auth
  /// gate teardown.
  void reset() {
    _gymId = null;
    _role = null;
    _timezone = null;
    _savedThemeDesignId = null;
    _videoGymId = null;
    _designId = null;
    _themeCategory = null;
    _displayName = '';
    _detail = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Select [style] from the picker: record the previewed design id + its
  /// [themeCategory] and re-brand the live preview. **Theme-only** — it does
  /// NOT touch [videoGymId], [detail], or [displayName]; the theme catalog is
  /// gym-agnostic and the real gym's content is fetched independently. No-op if
  /// it's already the previewed design.
  void selectStyle(ThemeStyle style) {
    if (_designId == style.id && _themeCategory == style.category) return;
    _designId = style.id;
    _themeCategory = style.category;
    // Drive branding; idempotent — skip when the engine is already on it.
    if (style.id.isNotEmpty && ThemeRuntime.activeDesignId != style.id) {
      ThemeRuntime.selectDesign(style.id);
    }
    notifyListeners();
  }

  Future<void> _fetchDetail() async {
    final gymId = _gymId;
    if (gymId == null) return; // admin-only; the public browser has no detail.
    _detail = null;
    _error = null;
    _isLoading = true;
    notifyListeners();
    // Guard staleness on the real gym UUID — if the admin switches gyms
    // (sign-out / gym picker) during the fetch, drop the stale result.
    try {
      final detail = await GymContentRepository(ApiClient()).fetchShowcase(gymId);
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

  /// Resolve [themeCategory] from a loaded style catalog for the currently
  /// previewed [designId] when the category isn't known yet — a seeded or
  /// deep-linked theme carries only its id (via the URL / the gym's saved
  /// design), not its category, until its catalog row streams in. **Only fires
  /// when no category is locked in yet**, so an explicit pick is never
  /// overridden. Matches on the intended [designId], falling back to
  /// [ThemeRuntime.activeDesignId] (which the seed applied).
  void reconcileFromCatalog(Iterable<ThemeStyle> items) {
    if (_themeCategory != null) return; // category known — don't override a pick
    final target = _designId ?? ThemeRuntime.activeDesignId;
    if (target == null || target.isEmpty) return;
    for (final s in items) {
      if (s.id == target) {
        _designId = target;
        _themeCategory = s.category;
        notifyListeners();
        return;
      }
    }
  }
}

/// The one process-wide selected gym, watched by the member-app surfaces.
final SelectedGym selectedGym = SelectedGym();
