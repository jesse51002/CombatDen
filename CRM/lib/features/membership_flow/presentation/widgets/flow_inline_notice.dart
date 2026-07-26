import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';

/// How loud an inline notice is, and the two things that decides.
enum FlowNoticeTone {
  /// Something is not going to happen the way it looks — a waiver republished
  /// under the reader, a card that will replace the one on file, a retry that
  /// has to be understood before it is pressed. Warm, never red: it is not the
  /// reader's fault, but they must register it.
  warm,

  /// A CONSEQUENCE worth stating, where nothing is wrong and nothing needs
  /// deciding — the blast radius of saving a default card, for instance.
  ///
  /// It exists because warm was doing this job and reading as an accusation:
  /// staff told us a yellow panel beside a card form "makes it seem like you
  /// did something wrong". Information that is merely important gets the
  /// accent wash instead, which stays prominent without sounding an alarm.
  info,
}

/// The signup lane's ONE inline notice: important, not the reader's fault, and
/// not a dead end. It is the shape every "you should know this before you carry
/// on" line takes — the waiver's republished-version warning, the payer
/// picker's redirect, the card step's "this replaces the card on your profile".
///
/// Its weight is the point: the surface's own BODY role on a tinted fill
/// out-weighs the ticked facts below it, prominent without alarm language, a
/// red treatment, or a modal. [tone] decides only how loudly — see
/// [FlowNoticeTone].
class FlowInlineNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  /// Defaults to [FlowNoticeTone.warm] so the kiosk's every notice — all of
  /// which are genuine "register this" lines — is unchanged.
  final FlowNoticeTone tone;

  const FlowInlineNotice({
    super.key,
    required this.message,
    this.onRetry,
    this.tone = FlowNoticeTone.warm,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    final retry = onRetry;
    final warm = tone == FlowNoticeTone.warm;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: warm
            ? DesignConstants.yellowDark
            : DesignConstants.accentSoft,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.info_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: warm
                ? DesignConstants.okYellow
                : DesignConstants.primaryColor,
          ),
          Expanded(
            child: Text(message, style: scale.body),
          ),
          if (retry != null)
            FlowOutlineButton(text: copy.retryAction, onPressed: retry),
        ],
      ),
    );
  }
}
