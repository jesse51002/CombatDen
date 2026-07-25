import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:crm/core/constants/design_constants.dart';

/// Custom text field for forms
class CustomTextField extends StatefulWidget {
  final TextEditingController controller;

  /// [label] is optional — omit it when the surrounding layout already
  /// labels the field (e.g. a group that puts quick-pick chips between the
  /// label and the field), mirroring [AppDropdownField] and [TappableField].
  final String? label;
  final String? hintText;

  /// Guidance rendered under the field. Material swaps it for the
  /// validator's message while the field is in error, so the two never
  /// stack.
  final String? helperText;
  final bool isPassword;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// Focus node for this field — pass one to drive focus
  /// transitions (e.g. Enter on a previous field focuses this).
  final FocusNode? focusNode;

  /// Keyboard action button; on web also drives Enter handling
  /// alongside [onSubmitted].
  final TextInputAction? textInputAction;

  /// Called when the field is submitted (Enter pressed).
  final VoidCallback? onSubmitted;

  /// Max lines for the field. Defaults to 1; pass a larger
  /// value (with [minLines]) for a multi-line text area.
  /// Ignored when [isPassword] is true.
  final int maxLines;
  final int? minLines;

  const CustomTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.isPassword = false,
    this.enabled = true,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (widget.label != null)
          Text(
            widget.label!,
            style: DesignConstants.h2.copyWith(color: DesignConstants.text),
          ),
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: widget.isPassword && _obscureText,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          inputFormatters: widget.inputFormatters,
          maxLines: widget.isPassword ? 1 : widget.maxLines,
          minLines: widget.isPassword ? 1 : widget.minLines,
          style: DesignConstants.p.copyWith(color: DesignConstants.text),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: DesignConstants.p.copyWith(
              color: DesignConstants.text.withValues(alpha: 0.5),
            ),
            helperText: widget.helperText,
            helperStyle: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
            filled: true,
            fillColor: DesignConstants.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(
                color: DesignConstants.text,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(
                color: DesignConstants.text,
                width: 2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(color: DesignConstants.primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(color: DesignConstants.badRed, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(color: DesignConstants.badRed, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(
                color: DesignConstants.text.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscureText ? Symbols.visibility_off_sharp : Symbols.visibility_sharp,
                      color: DesignConstants.text.withValues(alpha: 0.5),
                      weight: DesignConstants.iconWeight,
                    ),
                    onPressed: widget.enabled
                        ? () {
                            setState(() {
                              _obscureText = !_obscureText;
                            });
                          }
                        : null,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
