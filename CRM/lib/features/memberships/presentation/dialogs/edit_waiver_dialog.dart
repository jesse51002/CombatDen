import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/data/models/waiver_create_request.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_update_request.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// Create / edit a waiver: name + body text. Editing the body
/// publishes a new immutable version (members must re-sign);
/// when editing, the current body is fetched for prefill.
///
/// Self-contained: it writes through [MembershipsRepository] and
/// pops the saved [WaiverResponse] (or null on cancel / delete) so
/// callers can refresh a list or auto-select the new waiver.
class EditWaiverDialog extends StatefulWidget {
  final MembershipsRepository repository;
  final String gymId;
  final WaiverResponse? waiver;

  const EditWaiverDialog({
    super.key,
    required this.repository,
    required this.gymId,
    this.waiver,
  });

  /// Returns the created / updated waiver, or null on cancel / delete.
  static Future<WaiverResponse?> show({
    required BuildContext context,
    required MembershipsRepository repository,
    required String gymId,
    WaiverResponse? waiver,
  }) {
    return showDialog<WaiverResponse?>(
      context: context,
      builder: (_) => EditWaiverDialog(
        repository: repository,
        gymId: gymId,
        waiver: waiver,
      ),
    );
  }

  @override
  State<EditWaiverDialog> createState() => _EditWaiverDialogState();
}

class _EditWaiverDialogState extends State<EditWaiverDialog> {
  final _nameController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _loadingBody = false;
  bool _saving = false;

  bool get _isEdit => widget.waiver != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameController.text = widget.waiver!.name;
      _loadBody();
    }
  }

  Future<void> _loadBody() async {
    setState(() => _loadingBody = true);
    try {
      final full = await widget.repository
          .getWaiver(widget.waiver!.waiverId, widget.gymId);
      _bodyController.text = full.currentVersion?.body ?? '';
    } catch (_) {
      // Leave the body empty on a failed prefill; the user can
      // re-enter it (which republishes the version).
    } finally {
      if (mounted) setState(() => _loadingBody = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final body = _bodyController.text.trim();
    if (name.isEmpty || body.isEmpty) {
      _snack('Enter a name and waiver text.');
      return;
    }
    setState(() => _saving = true);
    try {
      final WaiverResponse saved;
      if (_isEdit) {
        saved = await widget.repository.updateWaiver(WaiverUpdateRequest(
          waiverId: widget.waiver!.waiverId,
          gymId: widget.gymId,
          data: WaiverUpdateData(name: name, body: body),
        ));
      } else {
        saved = await widget.repository.createWaiver(WaiverCreateRequest(
          gymId: widget.gymId,
          name: name,
          body: body,
        ));
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString());
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await widget.repository
          .deleteWaiver(widget.waiver!.waiverId, widget.gymId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString());
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: DesignConstants.p.copyWith(color: DesignConstants.surface),
        ),
        backgroundColor: DesignConstants.badRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: _isEdit ? 'Edit Waiver' : 'New Waiver',
      body: _loadingBody
          ? const Padding(
              padding: EdgeInsets.all(DesignConstants.paddingBig),
              child: Center(child: AppSpinner()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingLarge,
              children: [
                CustomTextField(
                  controller: _nameController,
                  label: 'Name',
                  hintText: 'Safety Acknowledgment Waiver',
                ),
                CustomTextField(
                  controller: _bodyController,
                  label: 'Waiver text',
                  hintText: 'The full waiver members agree to…',
                  keyboardType: TextInputType.multiline,
                  maxLines: 8,
                  minLines: 5,
                ),
                if (_isEdit)
                  Text(
                    'Editing the text publishes a new version. '
                    'Members must re-sign.',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.okYellow,
                    ),
                  ),
              ],
            ),
      actions: AppDialogActions(
        primaryLabel: _isEdit ? 'Save' : 'Create',
        primaryOnPressed: (_loadingBody || _saving) ? null : _save,
        isLoading: _saving,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
        destructiveLabel: _isEdit ? 'Delete' : null,
        destructiveOnPressed: _isEdit && !_saving ? _delete : null,
      ),
    );
  }
}
