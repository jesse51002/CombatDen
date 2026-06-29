import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/memberships/data/models/waiver_create_request.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/models/waiver_signatory_row.dart';
import 'package:crm/features/memberships/data/models/waiver_update_request.dart';
import 'package:crm/features/memberships/data/models/waiver_version_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// Full-screen waiver editor: a rich-text (Markdown) body on the left, the
/// version history + per-version signature counts on the right, and tabs for
/// the signed-members roster. Saving edits the current version in place while
/// it is unsigned and mints a new version once it has been signed.
class WaiverEditorScreen extends StatelessWidget {
  final WaiverResponse? waiver;

  const WaiverEditorScreen({super.key, this.waiver});

  @override
  Widget build(BuildContext context) {
    final gymId = selectedGym.gymId ?? '';
    return RepositoryProvider<MembershipsRepository>(
      create: (_) => MembershipsRepository(apiClient: ApiClient()),
      child: AppShell(
        activeRoute: AppRoutes.memberships,
        child: Builder(
          builder: (ctx) => _WaiverEditorBody(
            repository: ctx.read<MembershipsRepository>(),
            gymId: gymId,
            waiver: waiver,
          ),
        ),
      ),
    );
  }
}

class _WaiverEditorBody extends StatefulWidget {
  final MembershipsRepository repository;
  final String gymId;
  final WaiverResponse? waiver;

  const _WaiverEditorBody({
    required this.repository,
    required this.gymId,
    this.waiver,
  });

  @override
  State<_WaiverEditorBody> createState() => _WaiverEditorBodyState();
}

class _WaiverEditorBodyState extends State<_WaiverEditorBody> {
  final _name = TextEditingController();
  QuillController? _edit; // the editable current-version controller
  QuillController? _view; // a read-only controller for an old version
  StreamSubscription<DocChange>? _editSub;

  int _tab = 0;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _selectedVersionId; // null = editing the current version

  WaiverResponse? _waiver; // mutable: refreshed after each save
  String _originalName = '';
  String _originalBody = '';
  List<WaiverVersionResponse> _versions = const [];
  List<WaiverSignatoryRow> _signatories = const [];

  bool get _isEdit => _waiver != null;

  // Signatures on the version being edited — derived from the versions list so
  // it stays accurate after a save mints a new (0-signature) version.
  int get _currentSigned {
    final cvId = _waiver?.currentVersionId;
    for (final v in _versions) {
      if (v.versionId == cvId) return v.signatureCount;
    }
    return _waiver?.currentVersionSignedCount ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _waiver = widget.waiver;
    _name.text = _waiver?.name ?? '';
    _name.addListener(_markDirty);
    if (_isEdit) {
      _load();
    } else {
      _initEditController('');
      _loading = false;
    }
  }

  void _initEditController(String body) {
    _edit = WaiverMarkdownEditor.controllerFromMarkdown(body);
    _originalBody = WaiverMarkdownEditor.markdownFromController(_edit!);
    _originalName = _name.text.trim();
    _editSub = _edit!.document.changes.listen((_) => _markDirty());
  }

  Future<void> _load() async {
    try {
      final full = await widget.repository
          .getWaiver(_waiver!.waiverId, widget.gymId);
      final versions = await widget.repository
          .listWaiverVersions(_waiver!.waiverId, widget.gymId);
      final sigs = await widget.repository
          .listWaiverSignatories(_waiver!.waiverId, widget.gymId);
      _initEditController(full.currentVersion?.body ?? '');
      if (mounted) {
        setState(() {
          _versions = versions;
          _signatories = sigs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(e.toString(), isError: true);
      }
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _editSub?.cancel();
    _edit?.dispose();
    _view?.dispose();
    super.dispose();
  }

  void _selectVersion(WaiverVersionResponse? version) {
    _view?.dispose();
    setState(() {
      if (version == null) {
        _selectedVersionId = null;
        _view = null;
      } else {
        _selectedVersionId = version.versionId;
        _view = WaiverMarkdownEditor.controllerFromMarkdown(
          version.body,
          readOnly: true,
        );
      }
    });
  }

  Future<void> _handleBack() async {
    if (_saving) return;
    if (_dirty) {
      final leave = await ConfirmationModal.show(
        context: context,
        title: 'Leave without saving?',
        message: 'Your changes here will be lost.',
        confirmLabel: 'Leave',
        confirmColor: DesignConstants.badRed,
        cancelLabel: 'Keep editing',
      );
      if (!leave) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final body = WaiverMarkdownEditor.markdownFromController(_edit!);
    if (name.isEmpty || body.isEmpty) {
      _snack('Enter a name and waiver text.', isError: true);
      return;
    }

    // Nothing actually changed — confirm without a pointless backend round-trip
    // (no new version, no error shown).
    if (_isEdit && name == _originalName && body == _originalBody) {
      if (_dirty) setState(() => _dirty = false);
      _snack('Saved.');
      return;
    }

    // Editing a signed version mints a new one — confirm first.
    if (_isEdit && _currentSigned > 0) {
      final go = await ConfirmationModal.show(
        context: context,
        title: 'Saving creates a new version',
        message: '$_currentSigned member(s) have already signed this version, '
            'so saving creates a new one. If this change is legally meaningful, '
            'email those members the update or have them re-sign — for a minor '
            'wording fix that is usually not needed.',
        confirmLabel: 'Save new version',
      );
      if (!go) return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.repository.updateWaiver(WaiverUpdateRequest(
          waiverId: _waiver!.waiverId,
          gymId: widget.gymId,
          data: WaiverUpdateData(name: name, body: body),
        ));
      } else {
        _waiver = await widget.repository.createWaiver(WaiverCreateRequest(
          gymId: widget.gymId,
          name: name,
          body: body,
        ));
      }
      // Document editing — stay on the page; refresh versions/counts so a
      // newly-minted version shows up immediately.
      await _refresh();
      _originalName = name;
      _originalBody = body;
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = false;
        });
        _snack('Saved.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString(), isError: true);
      }
    }
  }

  Future<void> _refresh() async {
    final waiver = _waiver;
    if (waiver == null) return;
    final full = await widget.repository.getWaiver(waiver.waiverId, widget.gymId);
    final versions = await widget.repository
        .listWaiverVersions(waiver.waiverId, widget.gymId);
    final sigs = await widget.repository
        .listWaiverSignatories(waiver.waiverId, widget.gymId);
    if (mounted) {
      setState(() {
        _waiver = full;
        _versions = versions;
        _signatories = sigs;
      });
    }
  }

  Future<void> _delete() async {
    final go = await ConfirmationModal.show(
      context: context,
      title: 'Delete this waiver?',
      message: 'It will be removed and you will lose access to all of its data, '
          'including its version history.',
      confirmLabel: 'Delete',
      confirmColor: DesignConstants.badRed,
    );
    if (!go) return;
    setState(() => _saving = true);
    try {
      await widget.repository.deleteWaiver(_waiver!.waiverId, widget.gymId);
      _dirty = false;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString(), isError: true);
      }
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: DesignConstants.p.copyWith(color: DesignConstants.onAccent),
        ),
        backgroundColor:
            isError ? DesignConstants.badRed : DesignConstants.goodGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: _loading
            ? const Center(child: AppSpinner())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingLarge,
                children: [
                  _header(),
                  CustomTextField(
                    controller: _name,
                    label: 'Name',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  ViewSwitcher(
                    labels: const ['Edit Waiver', 'View Signed Members'],
                    selectedIndex: _tab,
                    onSelected: (i) => setState(() => _tab = i),
                  ),
                  Expanded(child: _tab == 0 ? _editTab() : _signedTab()),
                  _footer(),
                ],
              ),
      ),
    );
  }

  Widget _header() {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        InkWell(
          onTap: _handleBack,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Icon(
            Symbols.arrow_back_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
          ),
        ),
        Text(_isEdit ? 'Edit Waiver' : 'New Waiver', style: DesignConstants.big2),
        const Spacer(),
        if (_dirty)
          Text(
            '• Unsaved changes',
            style: DesignConstants.pSmall
                .copyWith(color: DesignConstants.text2nd),
          ),
      ],
    );
  }

  Widget _editTab() {
    // Create mode has no versions yet — show just the editor.
    if (!_isEdit) return _editorPane();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _editorPane()),
        const Hairline(vertical: true),
        SizedBox(width: 260, child: _versionsPanel()),
      ],
    );
  }

  Widget _editorPane() {
    if (_selectedVersionId == null || _view == null) {
      return WaiverMarkdownEditor(controller: _edit!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          children: [
            Text(
              'Viewing an older version (read-only)',
              style: DesignConstants.pSmall
                  .copyWith(color: DesignConstants.text2nd),
            ),
            const Spacer(),
            AppOutlineButton(
              text: 'Back to editing',
              onPressed: () => _selectVersion(null),
              borderRadius: DesignConstants.radiusSmall,
              textStyle: DesignConstants.pSmall,
            ),
          ],
        ),
        Expanded(child: WaiverMarkdownEditor(controller: _view!)),
      ],
    );
  }

  Widget _versionsPanel() {
    return Padding(
      padding: const EdgeInsets.only(left: DesignConstants.spacingLarge),
      child: ListView(
        children: [
          Text('Versions', style: DesignConstants.h2),
          _versionTile(
            label: 'Current (editing)',
            subtitle: '$_currentSigned signed',
            selected: _selectedVersionId == null,
            onTap: () => _selectVersion(null),
          ),
          for (final v in _versions)
            if (v.versionId != _waiver!.currentVersionId)
              _versionTile(
                label: 'v${v.versionNumber}',
                subtitle: '${v.signatureCount} signed',
                selected: _selectedVersionId == v.versionId,
                onTap: () => _selectVersion(v),
              ),
        ],
      ),
    );
  }

  Widget _versionTile({
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        margin: const EdgeInsets.only(top: DesignConstants.spacingMedium),
        padding: const EdgeInsets.all(DesignConstants.paddingSmall),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? DesignConstants.primaryColor : DesignConstants.line,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text(label, style: DesignConstants.pBig),
            Text(
              subtitle,
              style:
                  DesignConstants.pSmall.copyWith(color: DesignConstants.text2nd),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signedTab() {
    if (_signatories.isEmpty) {
      return Text(
        'No members have signed this waiver yet.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      );
    }
    return SingleChildScrollView(
      child: AppDataTable(
        shrinkWrap: true,
        columns: const [
          AppDataTableColumn(label: 'Member', fill: true),
          AppDataTableColumn(label: 'Status', minWidth: 160),
          AppDataTableColumn(label: 'Version', minWidth: 100),
          AppDataTableColumn(label: '', minWidth: 150),
        ],
        rows: [
          for (final s in _signatories)
            AppDataTableRow(
              cells: [
                Text('${s.firstName} ${s.lastName}', style: DesignConstants.p),
                Text(_statusLabel(s), style: DesignConstants.p),
                Text(
                  s.versionNumber == null ? '—' : 'v${s.versionNumber}',
                  style: DesignConstants.p,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppOutlineButton(
                    text: 'Member Sign',
                    onPressed: () => _openSignScreen(s),
                    borderRadius: DesignConstants.radiusSmall,
                    textStyle: DesignConstants.pSmall,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignConstants.spacingMedium,
                      vertical: DesignConstants.spacingSmall,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _statusLabel(WaiverSignatoryRow s) {
    if (!s.signed) return 'Not signed';
    return s.signedCurrentVersion ? 'Signed' : 'Signed (older version)';
  }

  // The member sign screen (front-desk capture) is not built yet — the button
  // is present but inert for now.
  void _openSignScreen(WaiverSignatoryRow s) {
    _snack('Member signing screen is coming soon.');
  }

  Widget _footer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        AppPrimaryButton(
          text: _isEdit ? 'Save' : 'Create',
          onPressed: _saving ? null : _save,
          isLoading: _saving,
          fullWidth: true,
        ),
        if (_isEdit)
          AppOutlineButton(
            text: 'Delete',
            onPressed: _saving ? null : _delete,
            fullWidth: true,
            borderColor: DesignConstants.badRed,
            textColor: DesignConstants.badRed,
            borderRadius: DesignConstants.radiusSmall,
          ),
      ],
    );
  }
}
