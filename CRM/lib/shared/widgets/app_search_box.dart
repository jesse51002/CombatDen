import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Rounded search box with magnifying glass icon.
///
/// Fully rounded by default with card background and
/// [DesignConstants] styling. All visual properties
/// are customizable.
class AppSearchBox extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final double? width;
  final double? height;
  final TextStyle? textStyle;

  /// The placeholder's ink. Defaults to the muted
  /// [DesignConstants.text3rd] the admin filters use. The
  /// kiosk passes [DesignConstants.text2nd] instead: its
  /// hint is a 22px instruction read from ~2m, and
  /// `text3rd` sits under the WCAG AA floor `PRODUCT.md`
  /// holds as a hard requirement.
  final Color? hintColor;

  const AppSearchBox({
    super.key,
    this.hintText = 'search name....',
    this.onChanged,
    this.controller,
    this.width,
    this.height,
    this.textStyle,
    this.hintColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? DesignConstants.h3;
    final hintInk = hintColor ?? DesignConstants.text3rd;

    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      style: style.copyWith(
        color: DesignConstants.text,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: style.copyWith(
          color: hintInk,
        ),
        prefixIcon: Icon(
          Symbols.search_sharp,
          color: DesignConstants.text3rd,
          size: DesignConstants.iconSizeMedium,
          weight: DesignConstants.iconWeight,
        ),
        filled: true,
        fillColor: DesignConstants.card,
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          borderSide: BorderSide(
            color: DesignConstants.text,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          borderSide: BorderSide(
            color: DesignConstants.text,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
          borderSide: BorderSide(
            color: DesignConstants.text,
          ),
        ),
      ),
      cursorColor: DesignConstants.text,
    );

    if (width != null || height != null) {
      return SizedBox(
        width: width,
        height: height,
        child: field,
      );
    }

    return field;
  }
}
