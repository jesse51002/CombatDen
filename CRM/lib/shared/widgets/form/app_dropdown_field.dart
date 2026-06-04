import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Labeled dropdown styled to match [CustomTextField]: a card-filled box
/// with a 2px border and rounded corners, label above.
class AppDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hintText;

  const AppDropdownField({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(label, style: DesignConstants.h2),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingSmall,
          ),
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
            border: Border.all(
              color: DesignConstants.text,
              width: DesignConstants.buttonBorder,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
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
            ),
          ),
        ),
      ],
    );
  }
}
