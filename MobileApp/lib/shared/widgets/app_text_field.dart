import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';

/// Labelled text field for the auth forms — adapted from the CRM's
/// `CustomTextField` so the two apps share one field treatment.
///
/// A [label] over a filled, rounded [TextFormField]; a password field gets a
/// visibility toggle. All visual tokens come from [DesignConstants].
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.isPassword = false,
    this.enabled = true,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool isPassword;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscureText = true;

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
    borderSide: BorderSide(color: color, width: DesignConstants.buttonBorder),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(widget.label, style: DesignConstants.h3),
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
          style: DesignConstants.p,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: DesignConstants.p.copyWith(
              color: DesignConstants.text3rd,
            ),
            filled: true,
            fillColor: DesignConstants.card,
            border: _border(DesignConstants.divider),
            enabledBorder: _border(DesignConstants.divider),
            focusedBorder: _border(DesignConstants.primaryColor),
            errorBorder: _border(DesignConstants.badRed),
            focusedErrorBorder: _border(DesignConstants.badRed),
            disabledBorder: _border(DesignConstants.text3rd),
            contentPadding: const EdgeInsets.all(
              DesignConstants.paddingSmall,
            ),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscureText
                          ? Symbols.visibility_off_sharp
                          : Symbols.visibility_sharp,
                      color: DesignConstants.text3rd,
                      weight: DesignConstants.iconWeight,
                      size: DesignConstants.iconSizeMd,
                    ),
                    onPressed: widget.enabled
                        ? () => setState(() => _obscureText = !_obscureText)
                        : null,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
