import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_search_box.dart';

/// Search box + Add New Member button row for the
/// Members list screen.
///
/// Drives [onSearchChanged] on every keystroke; debounce
/// lives in [MembersListBloc]. The Add New Member button
/// is a no-op stub (out-of-scope this pass).
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
          onPressed: () => debugPrint(
            'Add Member flow is out of scope this pass',
          ),
        ),
      ],
    );
  }
}
