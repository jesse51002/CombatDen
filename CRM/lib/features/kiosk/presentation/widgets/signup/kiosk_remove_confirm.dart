import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';

/// "Take {name} off this signup?" — the confirmation the roster's trash
/// control shows before it removes anybody.
///
/// **Composition = the shipped `KioskIdleWarning` / `KioskAbandonConfirm`
/// surface, reused whole**: the same ground-at-92% veil, the same popup card,
/// the same accent-soft disc, the same type. The kiosk gets exactly ONE modal
/// vocabulary, so a member who has seen either of the others knows this one is
/// asking rather than telling.
///
/// **Button order and weight follow that pattern too: the SAFE choice is the
/// primary, on the right.** Removal has no undo and the roster rows sit close
/// together at kiosk scale, so a member reaching for the biggest, bluest thing
/// on the screen must land on "keep them".
///
/// It names the person, because a roster of four all wearing the same trash
/// glyph cannot otherwise say which one is about to go.
class KioskRemoveConfirm extends StatelessWidget {
  /// Whose removal is being confirmed. Blank falls back to a neutral line
  /// rather than an empty gap in the sentence.
  final String name;

  const KioskRemoveConfirm({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final who = name.trim();
    return Positioned.fill(
      // Opaque, so a tap on the veil is ABSORBED and never answers the
      // question either way — exactly as the abandon confirm does.
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
              child: Container(
                margin: const EdgeInsets.all(DesignConstants.paddingBig),
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
                      'They come off the list and out of the total. You can '
                      'add them again.',
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
