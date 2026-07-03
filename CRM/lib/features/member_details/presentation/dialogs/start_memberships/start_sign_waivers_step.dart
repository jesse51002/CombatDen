import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';
import 'package:crm/shared/widgets/sign_waiver_dialog.dart';

/// Shows the required-but-unsigned waivers that blocked the
/// start-memberships POST (422 waiver gate). Each row has a
/// Sign button that opens [SignWaiverDialog]; when the last
/// pending signature lands [onAllSigned] fires so the wizard
/// can enable its Next button.
class StartSignWaiversStep extends StatefulWidget {
  final List<WaiverGateItem> unsigned;
  final String gymId;
  final Map<String, String> memberNames;
  final VoidCallback onAllSigned;

  const StartSignWaiversStep({
    super.key,
    required this.unsigned,
    required this.gymId,
    required this.memberNames,
    required this.onAllSigned,
  });

  @override
  State<StartSignWaiversStep> createState() =>
      _StartSignWaiversStepState();
}

class _StartSignWaiversStepState
    extends State<StartSignWaiversStep> {
  /// Keys: '${memberId}:${waiverId}' — one entry per gate item.
  final Set<String> _signed = {};

  String _key(WaiverGateItem item) =>
      '${item.memberId}:${item.waiverId}';

  void _markSigned(WaiverGateItem item) {
    setState(() => _signed.add(_key(item)));
    if (_signed.length >= widget.unsigned.length) {
      widget.onAllSigned();
    }
  }

  bool _isSigned(WaiverGateItem item) =>
      _signed.contains(_key(item));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        _Header(count: widget.unsigned.length),
        for (final item in widget.unsigned)
          _WaiverRow(
            item: item,
            memberName: widget.memberNames[item.memberId] ??
                'Member',
            gymId: widget.gymId,
            signed: _isSigned(item),
            onSigned: () => _markSigned(item),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int count;

  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    final plural = count == 1 ? 'waiver' : 'waivers';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(
          'Sign required $plural',
          style: DesignConstants.h2,
        ),
        Text(
          '$count $plural must be signed before '
          'these memberships can start. Sign each one '
          'below, then continue to review the charges.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}

class _WaiverRow extends StatelessWidget {
  final WaiverGateItem item;
  final String memberName;
  final String gymId;
  final bool signed;
  final VoidCallback onSigned;

  const _WaiverRow({
    required this.item,
    required this.memberName,
    required this.gymId,
    required this.signed,
    required this.onSigned,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingLarge),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.line,
          width: DesignConstants.buttonBorderSize,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            signed
                ? Symbols.check_circle_sharp
                : Symbols.draw_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: signed
                ? DesignConstants.goodGreen
                : DesignConstants.text2nd,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(
                  item.name,
                  style: DesignConstants.p,
                ),
                Text(
                  'For $memberName',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          if (signed)
            const InvoiceChip(
              label: 'Signed',
              tone: InvoiceChipTone.good,
            )
          else
            AppOutlineButton(
              text: 'Sign',
              borderRadius: DesignConstants.radiusSmall,
              textStyle: DesignConstants.pSmall,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.spacingLarge,
                vertical: DesignConstants.spacingSmall,
              ),
              onPressed: () => SignWaiverDialog.show(
                context: context,
                waiverId: item.waiverId,
                gymId: gymId,
                memberId: item.memberId,
                memberName: memberName,
                onSigned: onSigned,
              ),
            ),
        ],
      ),
    );
  }
}
