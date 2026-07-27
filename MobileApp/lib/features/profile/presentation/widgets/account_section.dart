import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/shared/widgets/buttons/app_outline_button.dart';
import 'package:mobile_app/shared/widgets/dialogs/sign_out_dialog.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// The profile screen's account block: the signed-in Supabase email and the
/// sign-out action.
///
/// Sign-out lives HERE, not in the topbar: it's a rare, deliberate,
/// account-level action, while the topbar is mid-session chrome (its identity
/// block switches profile — a different, frequent action). Teardown is already
/// centralized: `MemberGate.dispose()` resets [SelectedMember] and the theme
/// when the sign-out unmounts the gate, so this only dispatches the event.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingBig),
      child: SubtitleSection(
        title: 'Account',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            if (email != null && email.isNotEmpty)
              Text(
                email,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            AppOutlineButton(
              text: 'Sign out',
              fullWidth: true,
              borderRadius: DesignConstants.radiusSmall,
              borderColor: DesignConstants.text3rd,
              textColor: DesignConstants.text2nd,
              onPressed: () => _confirmSignOut(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final bloc = context.read<LoginBloc>();
    final confirmed = await SignOutDialog.show(context);
    if (confirmed != true) return;
    bloc.add(const LoginSignOutRequested());
  }
}
