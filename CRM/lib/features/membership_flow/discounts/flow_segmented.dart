import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// A row of mutually-exclusive options, all visible at once.
///
/// **Staff-only** — see `discount_labels.dart` for why nothing under
/// `discounts/` may reach the kiosk.
///
/// A segmented control rather than a dropdown because every option here is one
/// word and there are never many: "% off or $ off" and "how long does it last"
/// are decisions staff make while looking at the answer, and a dropdown hides
/// five of six answers behind a tap. It also cannot be left un-chosen — there
/// is always exactly one pressed segment — which is what removes a whole class
/// of "you didn't pick a lifetime" validation.
class FlowSegmented<T> extends StatelessWidget {
  final List<T> options;
  final T value;

  /// One word per option, from the option itself.
  final String Function(T option) labelOf;

  final ValueChanged<T> onChanged;

  /// Let the segments run onto a second line. The lifetime control has six and
  /// sits inside a card, so wrapping beats horizontal scrolling.
  final bool wrap;

  /// Divide the full width between the segments instead of hugging their
  /// words. For a control answering ONE question with two equal answers — how
  /// the first period is charged — packing them left leaves the chosen one
  /// looking like a tag rather than half of a decision.
  final bool fill;

  /// Switch WHAT IS SHOWN rather than set a value.
  ///
  /// The two are the same control and must not look the same: a value picker
  /// stays quiet beside the answer it is setting (the chosen segment merely
  /// lifts), while a control that swaps the panel underneath it has to read as
  /// navigation, so its chosen segment takes the brand fill.
  final bool loud;

  const FlowSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.wrap = false,
    this.fill = false,
    this.loud = false,
  });

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[
      for (final option in options)
        if (fill)
          Expanded(
            child: _Segment(
              label: labelOf(option),
              on: option == value,
              loud: loud,
              onTap: () => onChanged(option),
            ),
          )
        else
          _Segment(
            label: labelOf(option),
            on: option == value,
            loud: loud,
            onTap: () => onChanged(option),
          ),
    ];
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingSmall),
      decoration: BoxDecoration(
        color: loud
            ? DesignConstants.surface
            : DesignConstants.backgroundAlt,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line),
      ),
      child: wrap
          ? Wrap(
              spacing: DesignConstants.spacingSmall,
              runSpacing: DesignConstants.spacingSmall,
              children: segments,
            )
          : Row(
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              spacing: DesignConstants.spacingSmall,
              children: segments,
            ),
    );
  }
}

/// One option. In the quiet form the chosen one LIFTS (surface + its control
/// shadow) rather than filling with the brand colour: several of these sit
/// inside one card, and a row of sapphire pills would out-shout the membership
/// they are describing.
class _Segment extends StatelessWidget {
  final String label;
  final bool on;
  final bool loud;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.on,
    required this.loud,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final Color? fill = !on
        ? null
        : loud
            ? DesignConstants.primaryColor
            : DesignConstants.surface;
    final Color ink = !on
        ? DesignConstants.text2nd
        : loud
            ? DesignConstants.onAccent
            : DesignConstants.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingLarge,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          boxShadow:
              on && !loud ? DesignConstants.controlShadow : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: scale.micro.copyWith(color: ink),
        ),
      ),
    );
  }
}
