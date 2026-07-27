import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/login/bloc/login_bloc.dart';
import 'package:mobile_app/features/login/bloc/login_event.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/no_membership_view.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/offline_view.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/data/repositories/member_portal_repository.dart';
import 'package:mobile_app/features/member_select/logic/apply_member_selection.dart';
import 'package:mobile_app/features/member_select/presentation/screens/member_select_screen.dart';
import 'package:mobile_app/shared/widgets/loading_screen.dart';

/// In-app "switch profile" entry (`AppRoutes.memberSelect`). Re-opens the
/// "Who's training?" picker with a freshly-fetched member list; selecting a
/// member re-runs selection + theme hydration and RESETS the app to a fresh
/// home. (Feature blocs re-read `selectedMember` on the reset — the feature
/// wiring phase enforces that.)
class SwitchProfileScreen extends StatefulWidget {
  const SwitchProfileScreen({super.key});

  @override
  State<SwitchProfileScreen> createState() => _SwitchProfileScreenState();
}

class _SwitchProfileScreenState extends State<SwitchProfileScreen> {
  late final MemberPortalRepository _repository =
      MemberPortalRepository(apiClient: ApiClient());

  late Future<List<MemberIdentity>> _future = _repository.getMyMembers();
  bool _busy = false;

  void _reload() =>
      setState(() => _future = _repository.getMyMembers());

  Future<void> _onSelected(MemberIdentity m) async {
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    // The ONE switch path, shared with the topbar's identity sheet.
    await applyMemberSelection(navigator: navigator, member: m);
  }

  void _signOut() =>
      context.read<LoginBloc>().add(const LoginSignOutRequested());

  String? get _email => Supabase.instance.client.auth.currentUser?.email;

  @override
  Widget build(BuildContext context) {
    if (_busy) return const LoadingScreen();
    return FutureBuilder<List<MemberIdentity>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          return OfflineView(onRetry: _reload, onSignOut: _signOut);
        }
        final members = snapshot.data ?? const <MemberIdentity>[];
        if (members.isEmpty) {
          return NoMembershipView(
            email: _email,
            onCheckAgain: _reload,
            onSignOut: _signOut,
          );
        }
        return MemberSelectScreen(
          members: members,
          onSelected: _onSelected,
          onUseDifferentEmail: _signOut,
        );
      },
    );
  }
}
