import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_title.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Shared popup shell used for every dialog in the app.
///
/// Owns the common chrome: popup background,
/// small-radius corners, max width, padding, title row,
/// body slot, and an optional actions row with a primary
/// + optional secondary button.
///
/// Two sizes share this one shell:
/// - the default: a compact confirmation surface that
///   hugs its content (max width
///   [DesignConstants.dialogMaxWidth], body scrolls);
/// - [expanded]: a workflow surface (multi-step wizards)
///   pinned to a generous fraction of the viewport
///   ([DesignConstants.dialogHeightFractionWide] tall,
///   [maxWidth] wide). The title stays fixed on top, the
///   actions sit on a fixed footer behind a hairline, and
///   the body fills the space between and **owns its own
///   scrolling**.
class AppDialog extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? actions;
  final bool showCloseButton;

  /// Replaces the default [AppDialogTitle] row.
  ///
  /// For the workflow surfaces whose top band carries more than a name — the
  /// start-memberships wizard states WHOSE record it was opened from and how
  /// far through the run it is, facts a title row has nowhere to put. It is a
  /// slot rather than three more parameters, so no other dialog grows a
  /// concept it does not have; [title] stays required either way, because a
  /// dialog with no name is unreadable to a screen reader.
  final Widget? titleBar;

  /// The dialog's width cap. Compact dialogs keep the
  /// default; workflow surfaces pass
  /// [DesignConstants.dialogMaxWidthWide].
  final double maxWidth;

  /// Workflow-surface mode: fixed viewport-fraction
  /// height, fixed footer, body owns its scrolling.
  final bool expanded;

  /// Padding around the whole dialog content (title, body,
  /// actions). Workflow surfaces pass a bigger inset.
  final EdgeInsetsGeometry contentPadding;

  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.showCloseButton = true,
    this.titleBar,
    this.maxWidth = DesignConstants.dialogMaxWidth,
    this.expanded = false,
    this.contentPadding = const EdgeInsets.all(
      DesignConstants.paddingSmall,
    ),
  });

  /// Convenience builder that wires up a standard
  /// primary (+ optional secondary) footer and returns
  /// the value popped by [primaryOnPressed].
  ///
  /// The button callbacks receive the **dialog's own**
  /// `BuildContext` and must pop with
  /// `Navigator.of(dialogContext).pop(value)` — never the
  /// caller's context. The dialog is pushed on the root
  /// navigator (`showDialog`'s default); popping via the
  /// caller's context would target whatever navigator is
  /// nearest the caller (e.g. the nested workspace
  /// navigator the nav rail lives in) and pop the wrong
  /// route instead of the dialog.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget body,
    required String primaryLabel,
    void Function(BuildContext dialogContext)? primaryOnPressed,
    Color? primaryColor,
    String? secondaryLabel = 'Cancel',
    void Function(BuildContext dialogContext)? secondaryOnPressed,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => AppDialog(
        title: title,
        body: body,
        actions: AppDialogActions(
          primaryLabel: primaryLabel,
          primaryOnPressed: primaryOnPressed == null
              ? null
              : () => primaryOnPressed(dialogContext),
          primaryColor: primaryColor,
          secondaryLabel: secondaryLabel,
          secondaryOnPressed: secondaryOnPressed == null
              ? null
              : () => secondaryOnPressed(dialogContext),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: contentPadding,
      child: Column(
        mainAxisSize: expanded
            ? MainAxisSize.max
            : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          titleBar ??
              AppDialogTitle(
                title: title,
                showCloseButton: showCloseButton,
              ),
          if (expanded)
            // Workflow surface: the body fills the fixed
            // height and owns its own scrolling.
            Expanded(child: body)
          else
            Flexible(
              child: SingleChildScrollView(
                child: body,
              ),
            ),
          if (expanded && actions != null)
            const Hairline(),
          ?actions,
        ],
      ),
    );
    return Dialog(
      backgroundColor: DesignConstants.popup,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: expanded
            ? DesignConstants.paddingBig
            : DesignConstants.paddingSmall,
        vertical: DesignConstants.paddingBig,
      ),
      child: expanded
          ? LayoutBuilder(
              builder: (context, constraints) {
                final height = _expandedHeight(context);
                final sized = SizedBox(
                  width: maxWidth,
                  height: height,
                  child: content,
                );
                // On a viewport too short for the fixed
                // workflow height, scroll the whole surface
                // rather than forcing the body to a negative
                // height (which renders blank).
                return height <= constraints.maxHeight
                    ? sized
                    : SingleChildScrollView(child: sized);
              },
            )
          : ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: maxWidth),
              child: content,
            ),
    );
  }

  /// The expanded dialog's height: a generous fraction of the
  /// viewport, never taller than what the inset padding leaves
  /// available — but floored at [DesignConstants
  /// .dialogMinExpandedHeight] so the fixed chrome always fits
  /// and the scrolling body never goes negative. When the floor
  /// exceeds the viewport the whole surface scrolls (see build).
  double _expandedHeight(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).height;
    final fraction = math.min(
      viewport * DesignConstants.dialogHeightFractionWide,
      viewport - DesignConstants.paddingBig * 2,
    );
    return math.max(
      fraction,
      DesignConstants.dialogMinExpandedHeight,
    );
  }
}
