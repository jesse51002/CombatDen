import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';

/// The waiver's own text, in a fixed-height reading box with a fade off its
/// bottom edge.
///
/// The body renders through the SHIPPED [WaiverMarkdownEditor] — the same
/// read-only Markdown surface `SignWaiverPanel` uses at the desk — so the
/// member and the staff member read byte-identical text. The kiosk adds only
/// the chrome: the object-card panel, the head (waiver name + version), and
/// the fade, which is the one honest signal that there is more below the fold
/// on a screen nobody scrolls by instinct.
///
/// The height is [DesignConstants.dialogWaiverEditorHeight] — the shipped
/// waiver-reading height, reused rather than re-tuned so the box a member
/// reads and the box staff read are the same size.
class KioskWaiverDocPanel extends StatelessWidget {
  /// The waiver's name — the panel's title.
  final String title;

  /// "Version 3", or null while the version isn't known.
  final String? versionLabel;

  /// The already-rendered, read-only body.
  final QuillController controller;

  const KioskWaiverDocPanel({
    super.key,
    required this.title,
    required this.controller,
    this.versionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          _Head(title: title, versionLabel: versionLabel),
          SizedBox(
            height: DesignConstants.dialogWaiverEditorHeight,
            child: Stack(
              children: [
                WaiverMarkdownEditor(controller: controller),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BottomFade(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final String title;
  final String? versionLabel;

  const _Head({required this.title, this.versionLabel});

  @override
  Widget build(BuildContext context) {
    final version = versionLabel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            title,
            style: DesignConstants.kioskTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (version != null)
          Text(version, style: DesignConstants.kioskEyebrow),
      ],
    );
  }
}

/// A short wash from the panel's own fill up to nothing, so a body that
/// continues past the fold LOOKS like it continues. It carries no words and
/// no gesture, so it is `IgnorePointer` and stays on the surface token.
class _BottomFade extends StatelessWidget {
  const _BottomFade();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: DesignConstants.spacingBig,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              DesignConstants.surface,
              DesignConstants.surface.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
