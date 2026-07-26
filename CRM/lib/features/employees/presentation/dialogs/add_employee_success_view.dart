import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';

/// The Add-employee **success** state — the point of the surface. Access is
/// email-based, so this tells staff exactly how the new hire gets in, with a
/// one-tap copy of the literal steps (email substituted live). Rendered once
/// the create has committed.
///
/// [invite] is what the backend actually did about the onboarding email, and
/// it is reported verbatim: a held or suppressed send says so, and a create
/// made without inviting says the steps have to be passed on by hand. The
/// instructions are shown either way — an invite that WAS sent contains them,
/// but staff often walk the person through it at the desk anyway.
class AddEmployeeSuccessView extends StatefulWidget {
  final String firstName;
  final String email;
  final InviteOutcome invite;

  const AddEmployeeSuccessView({
    super.key,
    required this.firstName,
    required this.email,
    required this.invite,
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

  /// The honest sentence between the name and the instructions. Only
  /// [InviteOutcome.queued] may say the email went out; every other outcome
  /// says the steps have to reach the person some other way.
  String get _inviteLine => switch (widget.invite) {
        InviteOutcome.queued =>
          'Their sign-in instructions are on the way by email. Share these '
              'steps too if you want to walk them through it:',
        InviteOutcome.notRequested =>
          'No invite was sent. Share these steps so they can get in:',
        InviteOutcome.held =>
          'Invites are off right now, so nothing was emailed. Share these '
              'steps so they can get in:',
        InviteOutcome.skippedNoEmail =>
          'There was no email on file to send to. Share these steps so they '
              'can get in:',
        // A staff nudge is TRANSACTIONAL, so an unsubscribe can never
        // suppress it — reaching here means the address hard-bounced.
        // Saying "unsubscribed" would send staff chasing the wrong fix.
        InviteOutcome.skippedSuppressed =>
          "That address isn't accepting mail, so nothing was emailed. "
              'Share these steps so they can get in:',
        InviteOutcome.unknown =>
          "We couldn't confirm the invite was sent. Share these steps so "
              'they can get in:',
      };

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
              _inviteLine,
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
