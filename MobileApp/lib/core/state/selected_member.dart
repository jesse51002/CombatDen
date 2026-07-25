import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app-wide **selected member** — the one `members` row the app is
/// currently acting as. Mirrors the shape of the CRM's `SelectedGym`: a plain
/// global [ChangeNotifier], not a state-management framework. Feature surfaces
/// watch it with `ListenableBuilder(listenable: selectedMember, ...)` and,
/// per the live-session rules, reset+reload whenever it changes.
///
/// One verified email legitimately resolves to SEVERAL member rows (a family
/// shares an inbox), so the member is chosen explicitly — never derived from
/// the JWT. The chosen [memberId] + [gymId] scope every `/api/v1/member/...`
/// call.
///
/// **The revalidation ladder lives in the auth gate, not here.** This class
/// only holds the current selection and persists enough to (a) remember which
/// member to re-select on the next boot ([memberId], the ladder key) and (b)
/// restore a full identity offline when the identity fetch can't run
/// ([restoreFromCache]).
class SelectedMember extends ChangeNotifier {
  /// The persisted ladder key — which member to re-select on the next boot.
  static const String _memberIdKey = 'selected_member_id';

  /// A cached copy of the last-selected identity, for offline boot.
  static const String _identityKey = 'selected_member_identity';

  String? _memberId;
  String? _gymId;
  String? _gymName;
  String? _gymAddress;
  String? _gymLogoUrl;
  String? _firstName;
  String? _lastName;
  String? _photoUrl;

  /// The chosen member row's id; null until a member is selected.
  String? get memberId => _memberId;

  /// The chosen member's gym id; scopes every gym-scoped member-portal call.
  String? get gymId => _gymId;

  String? get gymName => _gymName;

  /// The gym's street address, when the gym has one set.
  String? get gymAddress => _gymAddress;
  String? get gymLogoUrl => _gymLogoUrl;
  String? get firstName => _firstName;
  String? get lastName => _lastName;
  String? get photoUrl => _photoUrl;

  /// The member's display name, or empty when no member is selected.
  String get fullName =>
      '${_firstName ?? ''} ${_lastName ?? ''}'.trim();

  /// Whether a member is currently selected.
  bool get hasSelection => _memberId != null && _gymId != null;

  /// Record the active member: set the fields, notify, and persist both the
  /// ladder key ([memberId]) and a cached identity blob (for offline boot).
  Future<void> select({
    required String memberId,
    required String gymId,
    required String gymName,
    required String firstName,
    required String lastName,
    String? gymAddress,
    String? gymLogoUrl,
    String? photoUrl,
  }) async {
    _memberId = memberId;
    _gymId = gymId;
    _gymName = gymName;
    _firstName = firstName;
    _lastName = lastName;
    _gymAddress = gymAddress;
    _gymLogoUrl = gymLogoUrl;
    _photoUrl = photoUrl;
    notifyListeners();
    await _persist();
  }

  /// The persisted ladder key from a previous session — which member to try to
  /// re-select. Read by the gate's revalidation ladder against the fresh list.
  Future<String?> restoreCandidate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_memberIdKey);
  }

  /// Restore the full last-selected identity from the on-disk cache, for the
  /// OFFLINE boot path (the identity fetch threw, so the fresh list is
  /// unavailable). Returns true and populates the fields when a cached identity
  /// exists and parses; false otherwise. Never throws.
  Future<bool> restoreFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_identityKey);
      if (raw == null) return false;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final memberId = map['member_id'] as String?;
      final gymId = map['gym_id'] as String?;
      if (memberId == null || gymId == null) return false;
      _memberId = memberId;
      _gymId = gymId;
      _gymName = map['gym_name'] as String?;
      _gymAddress = map['gym_address'] as String?;
      _gymLogoUrl = map['gym_logo_url'] as String?;
      _firstName = map['first_name'] as String?;
      _lastName = map['last_name'] as String?;
      _photoUrl = map['photo_url'] as String?;
      notifyListeners();
      return true;
    } catch (e, st) {
      log('SelectedMember.restoreFromCache failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Clear the selection and the persisted keys — the sign-out counterpart to
  /// [select]. Without this, the next session would silently reuse the prior
  /// member.
  Future<void> reset() async {
    _memberId = null;
    _gymId = null;
    _gymName = null;
    _gymAddress = null;
    _gymLogoUrl = null;
    _firstName = null;
    _lastName = null;
    _photoUrl = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_memberIdKey);
    await prefs.remove(_identityKey);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memberIdKey, _memberId!);
    await prefs.setString(
      _identityKey,
      jsonEncode({
        'member_id': _memberId,
        'gym_id': _gymId,
        'gym_name': _gymName,
        'gym_address': _gymAddress,
        'gym_logo_url': _gymLogoUrl,
        'first_name': _firstName,
        'last_name': _lastName,
        'photo_url': _photoUrl,
      }),
    );
  }
}

/// The one process-wide selected member, watched by the member-app surfaces.
final SelectedMember selectedMember = SelectedMember();
