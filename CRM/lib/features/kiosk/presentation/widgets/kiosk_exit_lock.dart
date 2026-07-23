import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';

/// The discreet corner control that leaves kiosk. A small padlock tap target
/// in a screen corner (not a loud button — the member surface shouldn't invite
/// exits) that confirms, then signs the iPad out via [KioskSessionCubit].
class KioskExitLock extends StatelessWidget {
  const KioskExitLock({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _confirmExit(context),
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        width: DesignConstants.navMenuButtonSize,
        height: DesignConstants.navMenuButtonSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DesignConstants.surface,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(color: DesignConstants.line),
          boxShadow: DesignConstants.controlShadow,
        ),
        child: Icon(
          Symbols.lock_sharp,
          size: DesignConstants.iconSizeLarge,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }

  /// Read the cubit before the await (never touch a `BuildContext` across the
  /// async gap — this widget's element can be torn down when the sign-out swaps
  /// the tree), confirm, then exit.
  Future<void> _confirmExit(BuildContext context) async {
    final cubit = context.read<KioskSessionCubit>();
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Exit Kiosk Mode?',
      message: 'This signs the iPad out. You’ll need to sign back in to '
          'manage your gym.',
      confirmLabel: 'Exit & sign out',
      confirmColor: DesignConstants.badRed,
    );
    if (!confirmed) return;
    cubit.exitKiosk();
  }
}
