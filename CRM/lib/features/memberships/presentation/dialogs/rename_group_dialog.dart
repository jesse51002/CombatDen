import 'package:flutter/material.dart';

import 'package:crm/features/memberships/bloc/ranks/ranks_bloc.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Rename a whole main-rank group. Applies the new name to every
/// sub-rank in the group (the rows share a denormalised `main_name`).
class RenameGroupDialog extends StatefulWidget {
  final RanksBloc bloc;
  final String gymId;
  final String currentName;
  final List<String> rankIds;

  const RenameGroupDialog({
    super.key,
    required this.bloc,
    required this.gymId,
    required this.currentName,
    required this.rankIds,
  });

  static Future<void> show({
    required BuildContext context,
    required RanksBloc bloc,
    required String gymId,
    required String currentName,
    required List<String> rankIds,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => RenameGroupDialog(
        bloc: bloc,
        gymId: gymId,
        currentName: currentName,
        rankIds: rankIds,
      ),
    );
  }

  @override
  State<RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<RenameGroupDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _controller.text.trim();
    if (name != widget.currentName) {
      widget.bloc.add(RankGroupRenamed(
        gymId: widget.gymId,
        rankIds: widget.rankIds,
        newName: name,
      ));
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Rename Rank',
      body: Form(
        key: _formKey,
        child: CustomTextField(
          controller: _controller,
          label: 'Main rank name',
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
      ),
      actions: AppDialogActions(
        primaryLabel: 'Save',
        primaryOnPressed: _save,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
