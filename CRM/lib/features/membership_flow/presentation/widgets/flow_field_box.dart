import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The kiosk's labeled text input: a label above, an optional leading glyph
/// inside the box, and an optional hint (or error line) below. The box is
/// `KioskNameSearch`'s geometry verbatim, so the signup's fields and the
/// home's search read as one control, plus the focus / error border pair the
/// search box has no need of.
///
/// No `autofillHints`, and never add any: this is a SHARED front-desk iPad, so
/// autofill would offer the PREVIOUS member's address (or card) to the next
/// person standing at it. The absence is load-bearing — see the kiosk-guide
/// skill.
class FlowFieldBox extends StatefulWidget {
  final TextEditingController controller;

  /// The label above the box.
  final String label;

  /// The muted word beside the label ("optional"). Only where optional is the
  /// EXCEPTION; a panel where optional is the rule says so once at the top.
  final String? labelNote;

  final String hintText;

  /// Guidance under the box. Replaced by [errorText] while the field is in
  /// error, so the two never stack.
  final String? helperText;

  /// The failed-validation line. Non-null puts the box in its error state.
  final String? errorText;

  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  /// What the field will ACCEPT, rejected at the keystroke — a numeric count
  /// that cannot hold a letter never has to say "digits only" afterwards.
  final List<TextInputFormatter>? inputFormatters;

  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const FlowFieldBox({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    this.labelNote,
    this.helperText,
    this.errorText,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<FlowFieldBox> createState() => _FlowFieldBoxState();
}

class _FlowFieldBoxState extends State<FlowFieldBox> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final error = widget.errorText;
    final note = widget.helperText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        _FieldLabel(label: widget.label, note: widget.labelNote),
        _Box(
          controller: widget.controller,
          focusNode: _focus,
          hintText: widget.hintText,
          icon: widget.icon,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          focused: _focus.hasFocus,
          bad: error != null,
        ),
        if (error != null)
          Text(
            error,
            style: scale.caption.copyWith(
              color: DesignConstants.badRed,
              fontWeight: FontWeight.w500,
            ),
          )
        else if (note != null)
          Text(
            note,
            style: scale.caption.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}

/// The label, and the one place an "optional" note may sit beside it.
class _FieldLabel extends StatelessWidget {
  final String label;
  final String? note;

  const _FieldLabel({required this.label, this.note});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final word = note;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(child: Text(label, style: scale.label)),
        if (word != null)
          Text(
            word,
            style: scale.caption.copyWith(
              color: DesignConstants.text2nd,
              fontWeight: FontWeight.w400,
            ),
          ),
      ],
    );
  }
}

/// The input box itself, at the surface's own field geometry.
class _Box extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final bool focused;
  final bool bad;

  const _Box({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.focused,
    required this.bad,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final glyph = icon;
    final border = bad
        ? DesignConstants.badRed
        : focused
            ? DesignConstants.primaryColor
            : DesignConstants.text;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: border),
        boxShadow: DesignConstants.controlShadow,
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          if (glyph != null)
            Icon(
              glyph,
              size: DesignConstants.iconSizeLarge,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
            ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              inputFormatters: inputFormatters,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted?.call(),
              style: scale.fieldText,
              cursorColor: DesignConstants.primaryColor,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: scale.fieldText.copyWith(
                  fontWeight: FontWeight.w400,
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
