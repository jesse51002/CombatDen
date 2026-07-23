import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// How an [EmptyState] reads: nothing-to-show, or something-went-wrong.
enum EmptyStateTone { neutral, error }

/// The app's shared empty / error placeholder — a centered icon, a title,
/// an optional explanatory body and an optional action.
///
/// Copy follows the house rule: acknowledge the state, then say what makes
/// it fill in. Never a bare "No data".
///
/// [minHeight] reserves the slot the real content would have taken, so a
/// chart's empty state occupies the chart's height and the page does not
/// reflow when data arrives. [EmptyState.inline] is the in-section variant:
/// a reserved height and no action.
class EmptyState extends StatelessWidget {
  /// A `Symbols.*_sharp` glyph naming the state.
  final IconData? icon;

  final String title;

  /// One or two sentences saying what fills this in.
  final String? body;

  /// Usually an `AppOutlineButton` — a retry or a next step.
  final Widget? action;

  final EmptyStateTone tone;

  /// Floor for the placeholder's height.
  final double? minHeight;

  const EmptyState({
    super.key,
    this.icon,
    required this.title,
    this.body,
    this.action,
    this.tone = EmptyStateTone.neutral,
    this.minHeight,
  });

  /// The in-section variant: reserves [minHeight] and carries no action.
  const EmptyState.inline({
    super.key,
    this.icon,
    required this.title,
    this.body,
    this.tone = EmptyStateTone.neutral,
    this.minHeight = DesignConstants.heroChartHeight,
  }) : action = null;

  @override
  Widget build(BuildContext context) {
    final iconColor = tone == EmptyStateTone.error
        ? DesignConstants.badRed
        : DesignConstants.text3rd;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (icon != null)
          Icon(
            icon,
            size: DesignConstants.iconSizeBig,
            weight: DesignConstants.iconWeight,
            color: iconColor,
          ),
        _TextBlock(title: title, body: body),
        ?action,
      ],
    );

    content = Center(child: content);

    if (minHeight == null) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight!),
      child: content,
    );
  }
}

class _TextBlock extends StatelessWidget {
  final String title;
  final String? body;

  const _TextBlock({required this.title, this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: DesignConstants.h2.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        if (body != null)
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignConstants.dialogMaxWidth,
            ),
            child: Text(
              body!,
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text3rd,
              ),
            ),
          ),
      ],
    );
  }
}
