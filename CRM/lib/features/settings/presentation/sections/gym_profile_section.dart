import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/settings/bloc/settings_bloc.dart';
import 'package:crm/features/settings/bloc/settings_event.dart';
import 'package:crm/features/settings/bloc/settings_state.dart';
import 'package:crm/features/settings/presentation/sections/gym_profile_save_status.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/image_upload_picker_field.dart';

/// Max length the backend caps the gym name at.
const int _kNameMaxLength = 255;

/// Max length for the free-text street address.
const int _kAddressMaxLength = 255;

/// Cap the text fields so a single control doesn't stretch the whole page
/// (matches the timezone selector's cap).
const double _kFieldMaxWidth = 480;

/// How long the "Saved." confirmation holds before fading back to the idle
/// contract line — long enough to read after a blur, short enough that two
/// quick edits don't stack.
const Duration _kSavedHold = Duration(milliseconds: 2500);

/// Helper under the gym name field. Always non-null so the helper row never
/// collapses and shifts the fields below.
const String _kNameHelper = 'Required.';
const String _kNameBlankNotice =
    'Gym name can\'t be empty, so we kept the last saved name.';

/// The shared **Gym profile** editor — the gym's real name, its street address
/// and its uploaded brand logo. The address is optional: an empty field saves
/// as null (`gyms.address` is nullable), which is how an owner removes one.
/// Saved through [SettingsBloc] via `PUT /api/v1/gyms/{gymId}`
/// (NOT optimistic): the field values come from [selectedGym] until the
/// backend commits, then [selectedGym] updates.
///
/// **This section AUTO-SAVES — there is no Save button.** Three distinct
/// commit points, deliberately not flattened into one:
///   * the **logo** persists the moment a new one is picked (the picker has
///     already uploaded it by then, so the pick is a deliberate commit);
///   * the **text fields** commit on BLUR, never per keystroke — `gym_name`
///     is NOT NULL, non-empty, and shows in every member's app, so a
///     per-keystroke save would push "Tit" to them mid-word;
///   * a commit only fires when the value actually **changed** since the last
///     dispatched save, so no blur ever sends a no-op request.
///
/// A blank gym name on blur is REJECTED, not saved: the field reverts to the
/// last value we tried to persist and says why under the field. A blank
/// address is a legitimate CLEAR and sends an explicit `null` (never `''`).
///
/// Because the button is gone, the confirmation is [GymProfileSaveStatusView]
/// — a permanently-present inline status line (idle contract → saving →
/// "Saved." → error + retry). A SnackBar per commit would be a toast storm
/// across three fields.
///
/// One implementation, two hosts: the Settings screen and — admin context
/// only — the [GymProfileDialog] opened from the Theme tab's phone preview.
/// Both provide a [SettingsBloc] above this widget; the dialog host also owns
/// the error listener (the Settings screen already has one).
///
/// [showHeader] hides the section's own title/subtitle when the host (the
/// dialog) already provides one. [onSaved] fires after every committed save;
/// under auto-save it is a notification hook only — the dialog host does NOT
/// close on it (a first field commit would slam the dialog shut mid-edit).
class GymProfileSection extends StatefulWidget {
  final bool showHeader;
  final VoidCallback? onSaved;

  const GymProfileSection({
    super.key,
    this.showHeader = true,
    this.onSaved,
  });

  @override
  State<GymProfileSection> createState() => _GymProfileSectionState();
}

class _GymProfileSectionState extends State<GymProfileSection> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  final _nameFocus = FocusNode();
  final _addressFocus = FocusNode();

  // The logo URL the section will persist. Seeded from the active gym; the
  // upload widget uploads on pick and hands back the CDN URL via
  // [onImageChosen].
  String? _logoUrl;

  // The values of the last save we DISPATCHED. A blur only commits when the
  // current values differ from these, so re-focusing and leaving a field
  // untouched never fires a second request — including while the first is
  // still in flight.
  late String _sentName;
  String? _sentAddress;
  String? _sentLogoUrl;

  // The values the backend has actually COMMITTED. A failed save rolls
  // `_sent*` back to these so the next blur (or the retry button) re-fires.
  late String _committedName;
  String? _committedAddress;
  String? _committedLogoUrl;

  /// Saved-count high-water mark: a bump means a save committed.
  int _seenSavedCount = 0;

  GymProfileSaveStatus _status = GymProfileSaveStatus.idle;
  Timer? _savedTimer;
  String? _nameNotice;

  @override
  void initState() {
    super.initState();
    _committedName = selectedGym.gymName ?? '';
    _committedAddress = selectedGym.address;
    _committedLogoUrl = selectedGym.logoUrl;
    _sentName = _committedName;
    _sentAddress = _committedAddress;
    _sentLogoUrl = _committedLogoUrl;

    _nameCtrl = TextEditingController(text: _committedName);
    // A null address (never set / cleared) seeds an empty field, which the
    // hint then explains — never the string "null".
    _addressCtrl = TextEditingController(text: _committedAddress ?? '');
    _logoUrl = _committedLogoUrl;

    _nameCtrl.addListener(_clearNameNotice);
    _nameFocus.addListener(_onNameFocusChange);
    _addressFocus.addListener(_onAddressFocusChange);
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _nameCtrl.removeListener(_clearNameNotice);
    _nameFocus.removeListener(_onNameFocusChange);
    _addressFocus.removeListener(_onAddressFocusChange);
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _clearNameNotice() {
    if (_nameNotice == null) return;
    setState(() => _nameNotice = null);
  }

  /// Blur on the gym name. A blank name is never sent (`gyms.gym_name` is
  /// NOT NULL with a non-empty CHECK, and it renders in every member's app):
  /// the field snaps back to the last value we tried to persist and says why.
  void _onNameFocusChange() {
    if (_nameFocus.hasFocus) return;
    if (_nameCtrl.text.trim().isEmpty) {
      // Assigning the text fires `_clearNameNotice` first, so the notice is
      // set afterwards or it would be wiped immediately.
      _nameCtrl.text = _sentName;
      setState(() => _nameNotice = _kNameBlankNotice);
      return;
    }
    _commit();
  }

  void _onAddressFocusChange() {
    if (_addressFocus.hasFocus) return;
    _commit();
  }

  /// Dispatch the current values, but only when something actually changed
  /// since the last dispatched save. Always sends the full triple so the one
  /// PUT keeps patch semantics no matter which field moved.
  void _commit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    // Optional field: an emptied box saves as an explicit null, which the
    // backend accepts as a genuine "clear the address".
    final typedAddress = _addressCtrl.text.trim();
    final address = typedAddress.isEmpty ? null : typedAddress;

    if (name == _sentName &&
        address == _sentAddress &&
        _logoUrl == _sentLogoUrl) {
      return;
    }
    _sentName = name;
    _sentAddress = address;
    _sentLogoUrl = _logoUrl;

    context.read<SettingsBloc>().add(
          GymProfileSaveRequested(
            gymName: name,
            address: address,
            logoUrl: _logoUrl,
          ),
        );
  }

  /// A new logo is a discrete, deliberate commit point — the picker has
  /// already uploaded it and handed back the CDN URL, so persist it now.
  void _onLogoChosen(String url) {
    setState(() => _logoUrl = url);
    _commit();
  }

  void _setStatus(GymProfileSaveStatus status) {
    _savedTimer?.cancel();
    if (status == GymProfileSaveStatus.saved) {
      _savedTimer = Timer(_kSavedHold, () {
        if (mounted) setState(() => _status = GymProfileSaveStatus.idle);
      });
    }
    setState(() => _status = status);
  }

  /// The section's own save channel. A saved-count bump is a commit; a
  /// `savingGymProfile` true → false edge with no bump is a failure. Reading
  /// the outcome off this one channel keeps the status independent of the
  /// hosts' shared error listener (which clears `error` as it surfaces it).
  void _onSettingsState(BuildContext context, SettingsState state) {
    if (state.gymProfileSavedCount > _seenSavedCount) {
      _seenSavedCount = state.gymProfileSavedCount;
      _committedName = _sentName;
      _committedAddress = _sentAddress;
      _committedLogoUrl = _sentLogoUrl;
      _nameNotice = null;
      _setStatus(GymProfileSaveStatus.saved);
      widget.onSaved?.call();
      return;
    }
    if (state.savingGymProfile) {
      _setStatus(GymProfileSaveStatus.saving);
      return;
    }
    if (_status == GymProfileSaveStatus.saving) {
      // Failed: keep what the user typed, roll the dispatched values back so
      // the retry (or the next blur) fires again.
      _sentName = _committedName;
      _sentAddress = _committedAddress;
      _sentLogoUrl = _committedLogoUrl;
      _setStatus(GymProfileSaveStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (prev, curr) =>
          prev.savingGymProfile != curr.savingGymProfile ||
          prev.gymProfileSavedCount != curr.gymProfileSavedCount,
      listener: _onSettingsState,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          if (widget.showHeader) ...[
            Text('Gym profile', style: DesignConstants.h1),
            Text(
              'Your gym\'s name, address and logo. The logo shows in the '
              'CRM nav and on your members\' app.',
              style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
            ),
          ],
          // Name above logo, always vertical. The plain Column keeps the
          // width constraint LOOSE, so the 480px cap genuinely applies —
          // the old side-by-side branch wrapped the field in Expanded,
          // whose TIGHT constraint overrode the cap and stretched the
          // field across the page.
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kFieldMaxWidth,
            ),
            child: CustomTextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              label: 'Gym name',
              hintText: 'e.g. Apex MMA',
              // Always non-null so the helper row never collapses.
              helperText: _nameNotice ?? _kNameHelper,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_kNameMaxLength),
              ],
            ),
          ),
          // Optional — an empty box is a valid save that clears the address.
          // Two lines: a full street address usually wraps (street +
          // city/state/zip) but is never a paragraph.
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kFieldMaxWidth,
            ),
            child: CustomTextField(
              controller: _addressCtrl,
              focusNode: _addressFocus,
              label: 'Address',
              hintText: 'e.g. 1200 W 6th St, Austin, TX 78703',
              helperText: 'Optional. Leave blank to remove it.',
              keyboardType: TextInputType.streetAddress,
              maxLines: 2,
              minLines: 1,
              inputFormatters: [
                LengthLimitingTextInputFormatter(_kAddressMaxLength),
              ],
            ),
          ),
          ImageUploadPickerField(
            label: 'Gym logo',
            category: 'gym',
            // A logo is a mark, not a photo: preview it 1:1 and CONTAINED so
            // it never crops or stretches — the same shape `GymLogo` paints
            // it in the nav (a square box, `BoxFit.contain`), so the preview
            // is what the gym actually gets.
            aspectRatio: 1,
            previewFit: BoxFit.contain,
            imageUrl: _logoUrl,
            onImageChosen: _onLogoChosen,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kFieldMaxWidth,
            ),
            child: GymProfileSaveStatusView(
              status: _status,
              onRetry: _commit,
            ),
          ),
        ],
      ),
    );
  }
}
