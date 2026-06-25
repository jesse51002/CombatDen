import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// `[-] [field] [+]` duration picker for the freeze dialog —
/// a centered digit-only field flanked by step buttons. The
/// owning dialog holds the [controller] and bounds and
/// validates the value; this widget only renders and reports
/// edits via [onChanged] / [onIncrement] / [onDecrement].
class MonthsStepper extends StatelessWidget {
  final TextEditingController controller;
  final int minMonths;
  final int maxMonths;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onChanged;

  const MonthsStepper({
    super.key,
    required this.controller,
    required this.minMonths,
    required this.maxMonths,
    required this.onDecrement,
    required this.onIncrement,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text('Freeze duration', style: DesignConstants.h2),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            _StepButton(
              icon: Symbols.remove_sharp,
              onPressed: onDecrement,
            ),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  signed: false,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                textAlign: TextAlign.center,
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.text,
                ),
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: DesignConstants.card,
                  suffixText: 'months',
                  suffixStyle: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(
                    horizontal: DesignConstants.paddingSmall,
                    vertical: DesignConstants.paddingSmall,
                  ),
                  border: _border(DesignConstants.text),
                  enabledBorder: _border(DesignConstants.text),
                  focusedBorder:
                      _border(DesignConstants.primaryColor),
                ),
              ),
            ),
            _StepButton(
              icon: Symbols.add_sharp,
              onPressed: onIncrement,
            ),
          ],
        ),
        Text(
          'Between $minMonths and $maxMonths months.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusBig,
      ),
      borderSide: BorderSide(color: color, width: 2),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _StepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: DesignConstants.stepperButtonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignConstants.text,
          backgroundColor: DesignConstants.card,
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: DesignConstants.text,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
          ),
        ),
        child: Icon(
          icon,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeLarge,
          color: DesignConstants.text,
        ),
      ),
    );
  }
}
