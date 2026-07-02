import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Labeled dropdown styled to match [CustomTextField]. It uses a
/// [DropdownButtonFormField] with the **same** `InputDecoration`
/// (fill, 2px rounded border, 16px content padding) as the text
/// field, so the two render at identical heights side by side.
/// [label] is optional — omit it when the surrounding section already
/// provides the heading.
class AppDropdownField<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hintText;

  const AppDropdownField({
    super.key,
    required this.items,
    this.label,
    this.value,
    this.onChanged,
    this.hintText,
  });

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
        if (label != null) Text(label!, style: DesignConstants.h2),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          dropdownColor: DesignConstants.popup,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          icon: Icon(
            Symbols.expand_more_sharp,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
          style: DesignConstants.p.copyWith(color: DesignConstants.text),
          hint: hintText != null
              ? Text(
                  hintText!,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                )
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: DesignConstants.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
              vertical: DesignConstants.paddingSmall,
            ),
            border: _border(DesignConstants.text),
            enabledBorder: _border(DesignConstants.text),
            focusedBorder: _border(DesignConstants.primaryColor),
          ),
        ),
      ],
    );
  }
}
