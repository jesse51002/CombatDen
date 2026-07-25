import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// "Take {name} off this signup?" — the confirmation the roster's trash
/// control shows before it removes anybody.
///
/// The shipped `KioskIdleWarning` / `KioskAbandonConfirm` surface reused whole,
/// including its button order: the SAFE choice is the primary, on the right.
/// Removal has no undo and the roster rows sit close together at kiosk scale,
/// so a member reaching for the biggest, bluest thing must land on "keep them".
/// It names the person — four rows wearing the same trash glyph cannot
/// otherwise say which one is going.
class KioskRemoveConfirm extends StatelessWidget {
  /// Whose removal is being confirmed. Blank falls back to a neutral line
  /// rather than an empty gap in the sentence.
  final String name;

  /// This person is the current PAYER, so removing them clears the payer and
  /// the next screen asks who pays — which the body has to say.
  final bool asksNextPayer;

  const KioskRemoveConfirm({
    super.key,
    required this.name,
    this.asksNextPayer = false,
  });

  @override
  Widget build(BuildContext context) {
    final who = name.trim();
    return Positioned.fill(
      // Opaque, so a tap on the veil is ABSORBED and never answers the question
      // either way.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignConstants.dialogMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(DesignConstants.paddingBig),
                child: Container(
                  padding: const EdgeInsets.all(DesignConstants.paddingBig),
                  decoration: BoxDecoration(
                    color: DesignConstants.popup,
                    borderRadius:
                        BorderRadius.circular(DesignConstants.radiusCard),
                    border: Border.all(color: DesignConstants.line),
                    boxShadow: DesignConstants.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: DesignConstants.spacingLarge,
                    children: [
                      const _RemoveIcon(),
                      Text(
                        who.isEmpty
                            ? 'Take them off this signup?'
                            : 'Take $who off this signup?',
                        style: DesignConstants.kioskPanelTitle,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        asksNextPayer
                            ? 'They\'re paying for everyone, so next you\'ll '
                                'choose who pays. You can add them again.'
                            : 'They come off the list and out of the total. '
                                'You can add them again.',
                        style: DesignConstants.kioskBody.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const _Answers(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Answers extends StatelessWidget {
  const _Answers();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        KioskOutlineButton(
          text: 'Yes, remove',
          onPressed: cubit.confirmRemovePerson,
        ),
        KioskPrimaryButton(
          text: 'Keep them',
          onPressed: cubit.dismissRemovePerson,
        ),
      ],
    );
  }
}

/// The shared disc, wearing the trash glyph the roster control carries.
class _RemoveIcon extends StatelessWidget {
  const _RemoveIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.accentSoft,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.delete_sharp,
        size: DesignConstants.iconSizeBig,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryColor,
      ),
    );
  }
}
