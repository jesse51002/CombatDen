/// The one place that answers "what is the phone frame currently previewing,
/// and is it the theme members actually see?" — shared by the theme list, the
/// preview pane's status line, and the leave-the-tab confirm, so all three can
/// never disagree about the preview-vs-saved split.
///
/// **Previewing ≠ saved.** Tapping a theme card only re-brands the preview;
/// the gym's real app theme is `SelectedGym.savedThemeDesignId` and changes
/// only when "Set as app theme" commits.
library;

import 'package:flutter/material.dart';

import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:theme_flutter/customization_runtime.dart';

/// The design the preview is currently showing, or null when nothing is.
///
/// The admin's **pick** is authoritative, with the engine as the fallback —
/// the same order `SetAppThemeButton` uses and for the same reason:
/// [SelectedGym.designId] updates the instant a card is tapped, while
/// [ThemeRuntime.activeDesignId] only advances once `selectDesign`'s fetch
/// resolves (and never on a failed fetch). The engine fallback covers the boot
/// / deep-link case, before any pick has happened this session; it is guarded
/// on [ThemeRuntime.isReady] because every runtime member throws until the
/// engine is registered.
String? previewedDesignId() {
  final picked = selectedGym.designId;
  if (picked != null && picked.isNotEmpty) return picked;
  if (!ThemeRuntime.isReady) return null;
  final active = ThemeRuntime.activeDesignId;
  return (active != null && active.isEmpty) ? null : active;
}

/// True when an admin is previewing a design that is **not** the gym's saved
/// app theme — i.e. leaving now would change nothing for members.
///
/// Always false in the public theme browser (`gymId == null`): there is no gym
/// to save to, so there is nothing to warn about.
bool hasUnsavedThemePreview() {
  if (selectedGym.gymId == null) return false;
  final previewed = previewedDesignId();
  if (previewed == null) return false;
  return previewed != selectedGym.savedThemeDesignId;
}

/// The saved theme's human name for prose — its display name once the catalog
/// has resolved it, else the raw design id, else null when nothing is saved.
String? savedThemeLabel() =>
    selectedGym.savedThemeName ?? selectedGym.savedThemeDesignId;

/// Ask before abandoning an unsaved preview, and return whether to proceed.
///
/// Returns `true` immediately when there is nothing to lose (no unsaved
/// preview, or the public browser), so callers can gate on it unconditionally.
/// On confirm, the preview is reverted to the saved design so the tab is left
/// showing what members actually see — the revert needs the saved design's
/// catalog row, and is simply skipped when nothing is saved (or it hasn't
/// resolved), which leaves the preview as-is and still changes nothing live.
Future<bool> confirmLeaveThemePreview(BuildContext context) async {
  if (!hasUnsavedThemePreview()) return true;
  final saved = savedThemeLabel();
  final leaving = await ConfirmationModal.show(
    context: context,
    title: 'Leave without setting the theme?',
    message: 'Members still see ${saved ?? 'no app theme yet'}. '
        'Previewing here never changes your app — only '
        '"Set as app theme" does.',
    confirmLabel: 'Leave preview',
    cancelLabel: 'Keep previewing',
  );
  if (!leaving) return false;
  final savedStyle = selectedGym.savedThemeStyle;
  if (savedStyle != null) selectedGym.selectStyle(savedStyle);
  return true;
}
