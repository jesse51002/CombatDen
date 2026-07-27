import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';

/// The waiver's own text, in a reading box that FILLS the height it is given,
/// with a fade off its bottom edge.
///
/// The body renders through the SHIPPED [WaiverMarkdownEditor] — the same
/// read-only Markdown surface `SignWaiverPanel` uses at the desk — so the
/// member and the staff member read BYTE-IDENTICAL text. The kiosk adds only
/// the chrome: the object-card panel, the head (waiver name + version), and the
/// fade that signals there is more below the fold.
///
/// It REQUIRES a bounded height and takes all of it: a legal document a member
/// is being asked to sign gets the whole fold rather than a letterbox, and a
/// long body scrolls INSIDE the editor. The waiver steps give it that bound by
/// asking `FlowStepScaffold` for a filled body.
class FlowWaiverDocPanel extends StatelessWidget {
  /// The waiver's name — the panel's title.
  final String title;

  /// "Version 3", or null while the version isn't known.
  final String? versionLabel;

  /// The already-rendered, read-only body.
  final QuillController controller;

  const FlowWaiverDocPanel({
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
        spacing: DesignConstants.spacingLarge,
        children: [
          _Head(title: title, versionLabel: versionLabel),
          Expanded(
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
    final scale = MembershipFlowTheme.of(context);
    final version = versionLabel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            title,
            style: scale.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (version != null)
          Text(version, style: scale.eyebrow),
      ],
    );
  }
}

/// A short wash from the panel's own fill up to nothing, so a body that
/// continues past the fold LOOKS like it does. No words and no gesture, so it
/// is `IgnorePointer`.
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
