import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_flow.dart';
import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_search_box.dart';

/// Search box + Add New Member button row for the
/// Members list screen.
///
/// Drives [onSearchChanged] on every keystroke; debounce
/// lives in [MembersListBloc]. "Add New Member" opens the
/// [AddMemberFlow]; when it closes the list reloads so a new
/// member appears.
class MembersListControls extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const MembersListControls({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  @override
  State<MembersListControls> createState() =>
      _MembersListControlsState();
}

class _MembersListControlsState
    extends State<MembersListControls> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.searchQuery,
    );
  }

  @override
  void didUpdateWidget(
    covariant MembersListControls oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    // Sync the controller when the bloc resets the query
    // (e.g. view switch) without clobbering cursor.
    if (widget.searchQuery != oldWidget.searchQuery &&
        widget.searchQuery != _controller.text) {
      _controller.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Opens the add-member flow, then reloads the list so any new member
  /// surfaces (mirrors the People screen's init/retry load) — unless the flow
  /// already navigated to a member's detail page.
  Future<void> _onAddMember() async {
    final bloc = context.read<MembersListBloc>();
    final outcome = await AddMemberFlow.show(context);
    if (!mounted) return;
    if (outcome.createdCount > 0 && !outcome.navigatedToMember) {
      bloc.add(MembersListInitRequested(selectedGym.gymId ?? ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingBig,
      children: [
        Expanded(
          child: AppSearchBox(
            hintText: 'search name...',
            controller: _controller,
            onChanged: widget.onSearchChanged,
          ),
        ),
        AppPrimaryButton(
          text: 'Add New Member',
          textStyle: DesignConstants.h2,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
            vertical: DesignConstants.spacingMedium,
          ),
          onPressed: _onAddMember,
        ),
      ],
    );
  }
}
