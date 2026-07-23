import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The Add-employee **success** state — the point of the surface. Access is
/// email-based (no invite to send), so this tells staff exactly how the new
/// hire gets in, with a one-tap copy of the literal steps (email substituted
/// live). Rendered once the invite has committed.
class AddEmployeeSuccessView extends StatefulWidget {
  final String firstName;
  final String email;

  const AddEmployeeSuccessView({
    super.key,
    required this.firstName,
    required this.email,
  });

  @override
  State<AddEmployeeSuccessView> createState() => _AddEmployeeSuccessViewState();
}

class _AddEmployeeSuccessViewState extends State<AddEmployeeSuccessView> {
  bool _copied = false;
  Timer? _resetTimer;

  List<String> get _lines => [
        '1. Go to app.combatden.net',
        '2. Create an account (or log in) with ${widget.email}',
        '3. Verify the email — the gym appears automatically',
      ];

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Align(
          child: Icon(
            Symbols.check_circle_sharp,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeBig,
            color: DesignConstants.goodGreen,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              '${widget.firstName} was added',
              textAlign: TextAlign.center,
              style: DesignConstants.h2,
            ),
            Text(
              'Access works by email — no invite to send. Share these steps '
              'so they can get in:',
              textAlign: TextAlign.center,
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        _InstructionsPanel(
          lines: _lines,
          copied: _copied,
          onCopy: _copy,
        ),
        Text(
          'Already has a CombatDen account with this email? They\'re in on '
          'their next sign-in.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

/// The quiet tinted (NOT lifted-card) block of literal, copyable sign-in steps.
class _InstructionsPanel extends StatelessWidget {
  final List<String> lines;
  final bool copied;
  final VoidCallback onCopy;

  const _InstructionsPanel({
    required this.lines,
    required this.copied,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final mono =
        DesignConstants.p.merge(DesignConstants.monoFont).copyWith(
              color: DesignConstants.text,
            );
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _CopyAffordance(copied: copied, onTap: onCopy),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [for (final line in lines) Text(line, style: mono)],
          ),
        ],
      ),
    );
  }
}

class _CopyAffordance extends StatelessWidget {
  final bool copied;
  final VoidCallback onTap;

  const _CopyAffordance({required this.copied, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            copied ? Symbols.check_sharp : Symbols.content_copy_sharp,
            size: DesignConstants.iconSizeSmall,
            color: DesignConstants.text2nd,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            copied ? 'Copied' : 'Copy instructions',
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
