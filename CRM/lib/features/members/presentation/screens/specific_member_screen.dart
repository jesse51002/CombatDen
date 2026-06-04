import 'package:flutter/material.dart';

import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/screens/member_detail_screen.dart';
import 'package:crm/shared/widgets/loading_screen.dart';

/// Route host for the Specific Member detail screen.
///
/// Thin wrapper around the billing-rich [MemberDetailScreen]
/// (which lives in the `member_details` feature). It resolves
/// which member to show:
///
/// - When navigated with a `String` member id as the route
///   argument (`Navigator.pushNamed(context, members/detail,
///   arguments: memberId)`), it mounts that member directly.
/// - With no argument (e.g. a direct nav or deep link), it
///   resolves the first member of the app-wide
///   [selectedGym] and mounts them, so the screen always has
///   a real member to render.
class SpecificMemberScreen extends StatelessWidget {
  const SpecificMemberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final gymId = selectedGym.gymId;

    if (args is String && args.isNotEmpty) {
      return MemberDetailScreen(
        memberId: args,
        gymId: gymId,
      );
    }

    // No explicit member: resolve the first roster member
    // for the selected gym, then mount the detail screen.
    return _FirstMemberResolver(gymId: gymId);
  }
}

/// Fetches the first member of [gymId] and mounts the
/// detail screen for them. Used only when the route arrives
/// without a member-id argument.
class _FirstMemberResolver extends StatefulWidget {
  final String? gymId;

  const _FirstMemberResolver({required this.gymId});

  @override
  State<_FirstMemberResolver> createState() =>
      _FirstMemberResolverState();
}

class _FirstMemberResolverState
    extends State<_FirstMemberResolver> {
  late final MemberRepository _repository;
  late Future<String?> _firstMemberId;

  @override
  void initState() {
    super.initState();
    _repository = MemberRepository(apiClient: ApiClient());
    _firstMemberId = _resolve();
  }

  Future<String?> _resolve() async {
    final gymId = widget.gymId;
    if (gymId == null || gymId.isEmpty) return null;
    // One page is enough to grab the first member. Do NOT pass
    // pageSize: 1 — getAllMembers paginates, so a page size of 1
    // walks the whole roster one request at a time (~N calls).
    final members = await _repository.getAllMembers(gymId);
    return members.isEmpty ? null : members.first.memberId;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _firstMemberId,
      builder: (context, snapshot) {
        if (snapshot.connectionState !=
            ConnectionState.done) {
          return const LoadingScreen();
        }
        final id = snapshot.data;
        // With or without a resolved id, mount the detail
        // screen: a real id renders the member; an empty id
        // lets the bloc surface its in-screen load error +
        // retry rather than a bespoke dead end here.
        return MemberDetailScreen(
          memberId: id ?? '',
          gymId: widget.gymId,
        );
      },
    );
  }
}
