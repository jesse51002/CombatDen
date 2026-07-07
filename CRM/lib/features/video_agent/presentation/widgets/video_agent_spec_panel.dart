import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// Visual mode for [VideoAgentSpecPanel].
enum VideoSpecPanelMode {
  /// The current saved spec — calm, no highlight.
  current,

  /// A pending proposal — accent border + glow.
  proposed,

  /// Just accepted — green border + glow, held until the next message.
  saved,
}

/// Read-only spec panel: discipline tags + a We surface / We avoid markdown
/// switcher. One widget renders the **current saved spec**, a **proposed
/// draft**, and the **just-saved** success state — they share the exact same UI.
///
/// In [VideoSpecPanelMode.proposed] the panel pops with an accent border + glow
/// and shows the [footer] actions (Accept / Tell us what to change); in
/// [VideoSpecPanelMode.saved] it glows green (a just-accepted success cue, held
/// until the next message); otherwise it is the calm current-spec card.
///
/// Queries are never shown to the gym owner — they are generated server-side
/// and belong to the backend's search layer only.
class VideoAgentSpecPanel extends StatefulWidget {
  final List<String> disciplines;
  final String videosDesc;
  final String avoidDesc;

  /// Visual mode (calm current / accent proposal / green just-saved).
  final VideoSpecPanelMode mode;

  /// Action row shown at the bottom in proposed mode.
  final Widget? footer;

  const VideoAgentSpecPanel({
    super.key,
    required this.disciplines,
    required this.videosDesc,
    required this.avoidDesc,
    this.mode = VideoSpecPanelMode.current,
    this.footer,
  });

  @override
  State<VideoAgentSpecPanel> createState() => _VideoAgentSpecPanelState();
}

class _VideoAgentSpecPanelState extends State<VideoAgentSpecPanel> {
  // 0 = We surface (videosDesc), 1 = We avoid (avoidDesc).
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final highlighted = mode != VideoSpecPanelMode.current;
    // Accent (blue) for a proposal, green for a just-saved spec.
    final accent = mode == VideoSpecPanelMode.saved
        ? DesignConstants.goodGreen
        : DesignConstants.primaryColor;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: highlighted
            ? accent.withValues(alpha: 0.1)
            : DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: highlighted
            ? Border.all(color: accent, width: 2)
            : null,
        // Glow so a proposal (accent) or a just-saved spec (green) reads as
        // highlighted; the calm current card stays flat.
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          _HeaderRow(mode: mode, disciplines: widget.disciplines),
          ViewSwitcher(
            labels: const ['We surface', 'We avoid'],
            selectedIndex: _index,
            onSelected: (i) => setState(() => _index = i),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _DescBody(
                markdown: _index == 0
                    ? widget.videosDesc
                    : widget.avoidDesc,
              ),
            ),
          ),
          if (mode == VideoSpecPanelMode.current ||
              mode == VideoSpecPanelMode.saved)
            const _PopulationNote(),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final VideoSpecPanelMode mode;
  final List<String> disciplines;

  const _HeaderRow({required this.mode, required this.disciplines});

  @override
  Widget build(BuildContext context) {
    final IconData? icon = switch (mode) {
      VideoSpecPanelMode.proposed => Symbols.auto_awesome_sharp,
      VideoSpecPanelMode.saved => Symbols.check_circle_sharp,
      VideoSpecPanelMode.current => null,
    };
    final String title = switch (mode) {
      VideoSpecPanelMode.proposed => 'Proposed spec',
      VideoSpecPanelMode.saved => 'Spec saved',
      VideoSpecPanelMode.current => 'Current spec',
    };
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
            color: mode == VideoSpecPanelMode.saved
                ? DesignConstants.goodGreen
                : DesignConstants.primaryColor,
          ),
          const SizedBox(width: DesignConstants.spacingSmall),
        ],
        Expanded(
          child: Text(title, style: DesignConstants.h3),
        ),
        if (disciplines.isNotEmpty)
          Flexible(
            child: Text(
              disciplines.join(', '),
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class _DescBody extends StatelessWidget {
  final String markdown;

  const _DescBody({required this.markdown});

  @override
  Widget build(BuildContext context) {
    if (markdown.isEmpty) {
      return Text(
        'No description yet.',
        style: DesignConstants.h3Regular.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    final body = DesignConstants.h3Regular.copyWith(
      color: DesignConstants.text2nd,
    );
    return MarkdownBody(
      data: markdown,
      selectable: false,
      styleSheet: MarkdownStyleSheet(
        p: body,
        h3: DesignConstants.h3,
        strong: DesignConstants.h3.copyWith(
          color: DesignConstants.text2nd,
        ),
        em: body.copyWith(fontStyle: FontStyle.italic),
        listBullet: body,
        blockSpacing: DesignConstants.spacingSmall,
        listIndent: DesignConstants.spacingLarge,
        a: body.copyWith(color: DesignConstants.hyperlink),
      ),
    );
  }
}

/// Pinned reminder under the saved / current spec that the feed refreshes
/// asynchronously — a save queues work the worker fulfils within 24 hours,
/// so the owner doesn't expect instant new videos.
class _PopulationNote extends StatelessWidget {
  const _PopulationNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.schedule_sharp,
          size: DesignConstants.iconSizeSmall,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text3rd,
        ),
        Expanded(
          child: Text(
            'New videos populate within 24 hours.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ],
    );
  }
}
