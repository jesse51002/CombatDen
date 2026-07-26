import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/data/repositories/member_portal_repository.dart';
import 'package:mobile_app/features/member_select/logic/apply_member_selection.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/identity_sheet_header.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/identity_sheet_sign_out_row.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/identity_switch_list.dart';
import 'package:mobile_app/shared/widgets/dialogs/sign_out_dialog.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';
import 'package:mobile_app/shared/widgets/sheets/app_bottom_sheet.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// Loads the member rows this email resolves to. Injectable so the sheet can
/// be driven without a live backend.
typedef MembersLoader = Future<List<MemberIdentity>> Function();

/// The ONE surface behind the topbar's avatar: who you're signed in as, the
/// other profiles on this email, and sign out.
///
/// It holds sign-out because this is the account surface — the profile/rank
/// screen is the RETENTION surface, and an account-exit action has no business
/// sitting beside a member's streak and rank.
class IdentitySheet extends StatefulWidget {
  const IdentitySheet({
    super.key,
    required this.onSignOut,
    this.loadMembers,
  });

  final MembersLoader? loadMembers;

  /// Run AFTER the sheet has dismissed itself: confirm, then sign out.
  final Future<void> Function() onSignOut;

  /// Open the sheet over [context]'s navigator.
  static Future<void> show(
    BuildContext context, {
    MembersLoader? loadMembers,
  }) {
    return showAppBottomSheet<void>(
      context: context,
      builder: (_) => IdentitySheet(
        loadMembers: loadMembers,
        // Bound to the HOST context (the topbar below), not the sheet's: the
        // sheet is gone by the time the dialog opens.
        onSignOut: () => _confirmSignOut(context),
      ),
    );
  }

  /// Dismiss FIRST, then confirm: the destructive confirmation is a
  /// full-attention decision, not something stacked on the surface that
  /// launched it. The bloc is captured before the await so no context crosses
  /// the async gap.
  static Future<void> _confirmSignOut(BuildContext context) async {
    if (!context.mounted) return;
    final bloc = context.read<LoginBloc>();
    final confirmed = await SignOutDialog.show(context);
    if (confirmed != true) return;
    bloc.add(const LoginSignOutRequested());
  }

  @override
  State<IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<IdentitySheet> {
  late final MembersLoader _load =
      widget.loadMembers ??
      MemberPortalRepository(apiClient: ApiClient()).getMyMembers;

  bool _loading = true;
  bool _failed = false;
  bool _busy = false;
  List<MemberIdentity> _others = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final members = await _load();
      if (!mounted) return;
      setState(() {
        _others = members
            .where((m) => m.memberId != selectedMember.memberId)
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _switchTo(MemberIdentity member) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    await applyMemberSelection(navigator: navigator, member: member);
  }

  Future<void> _signOut() async {
    Navigator.of(context).pop();
    await widget.onSignOut();
  }

  /// The Supabase email, read defensively: the app boots Supabase
  /// best-effort, so an uninitialized client must degrade to "no email"
  /// rather than take the sheet down.
  String? get _email {
    try {
      return Supabase.instance.client.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  /// The switch section is shown while loading, on failure, and when there ARE
  /// other profiles — never as an empty list or a disabled row.
  bool get _showSwitch => _loading || _failed || _others.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          IdentitySheetHeader(
            fullName: selectedMember.fullName,
            gymName: selectedMember.gymName ?? '',
            gymLogoUrl: selectedMember.gymLogoUrl,
            photoUrl: selectedMember.photoUrl,
            firstName: selectedMember.firstName,
            lastName: selectedMember.lastName,
            email: _email,
          ),
          if (_showSwitch) ...[
            const SectionDivider(),
            SubtitleSection(
              title: 'Switch profile',
              child: IdentitySwitchList(
                loading: _loading,
                failed: _failed,
                members: _others,
                busy: _busy,
                onRetry: _fetch,
                onSelected: _switchTo,
              ),
            ),
          ],
          const SectionDivider(),
          IdentitySheetSignOutRow(onTap: _signOut),
        ],
      ),
    );
  }
}
