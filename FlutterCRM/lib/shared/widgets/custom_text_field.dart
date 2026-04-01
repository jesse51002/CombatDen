import 'package:flutter/material.dart';
import 'package:crm/core/constants/design_constants.dart';

/// Custom text field for forms
class CustomTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool isPassword;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.isPassword = false,
    this.enabled = true,
    this.validator,
    this.keyboardType,
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
      children: [
        Text(
          widget.label,
          style: DesignConstants.h2.copyWith(color: DesignConstants.text),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.isPassword && _obscureText,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          style: DesignConstants.p.copyWith(color: DesignConstants.text),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: DesignConstants.p.copyWith(
              color: DesignConstants.text.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: DesignConstants.cardBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(
                color: DesignConstants.buttonStroke,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              borderSide: BorderSide(
                color: DesignConstants.buttonStroke,
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
                color: DesignConstants.buttonStroke.withValues(alpha: 0.5),
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
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                      color: DesignConstants.text.withValues(alpha: 0.5),
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
