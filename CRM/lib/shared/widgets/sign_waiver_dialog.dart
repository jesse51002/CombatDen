import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/utils/waiver_render.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/sign_waiver_panel.dart';

enum _Phase { loading, form, submitting, success, stale, error }

/// Standalone waiver-signing dialog. Fetches the waiver by
/// [waiverId] + [gymId], shows it in [SignWaiverPanel], and POSTs
/// the signature. Terminal steps: a green success view or an error
/// message. Calls [onSigned] when the signature is committed so the
/// parent can refresh its state.
///
/// Phases: loading → form → submitting → success | stale | error.
/// The [MemberDetailBloc]'s [refreshToken] is bumped by the bloc's
/// own mutation after signing — this dialog does NOT dispatch a bloc
/// event; it calls the repository directly and invokes [onSigned]
/// so the parent (e.g. the waivers section) can re-fetch.
class SignWaiverDialog extends StatefulWidget {
  final String waiverId;
  final String gymId;
  final String memberId;
  final String memberName;

  /// Called after a successful signature so the parent can
  /// refresh its waiver-status list.
  final VoidCallback? onSigned;

  const SignWaiverDialog({
    super.key,
    required this.waiverId,
    required this.gymId,
    required this.memberId,
    required this.memberName,
    this.onSigned,
  });

  static Future<void> show({
    required BuildContext context,
    required String waiverId,
    required String gymId,
    required String memberId,
    required String memberName,
    VoidCallback? onSigned,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: SignWaiverDialog(
          waiverId: waiverId,
          gymId: gymId,
          memberId: memberId,
          memberName: memberName,
          onSigned: onSigned,
        ),
      ),
    );
  }

  @override
  State<SignWaiverDialog> createState() => _SignWaiverDialogState();
}

class _SignWaiverDialogState extends State<SignWaiverDialog> {
  final MembershipsRepository _repo =
      MembershipsRepository(apiClient: ApiClient());

  _Phase _phase = _Phase.loading;
  WaiverResponse? _waiver;
  QuillController? _controller;
  String _templateBody = ''; // raw template body; rendered into _controller
  String _signerName = '';
  bool _consent = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWaiver();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadWaiver() async {
    try {
      final waiver =
          await _repo.getWaiver(widget.waiverId, widget.gymId);
      if (!mounted) return;
      setState(() {
        _waiver = waiver;
        _templateBody = waiver.currentVersion?.body ?? '';
        _controller = _buildController();
        _phase = _Phase.form;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load waiver. Please try again.';
        _phase = _Phase.error;
      });
    }
  }

  // Display-only render of the body with the values the backend substitutes
  // at sign time: member_name is the signed-for member, gym_name/date are
  // fixed, and signer_name follows the live typed name (empty leaves the
  // token literal so the signer sees where their name will land).
  Map<String, String> _renderValues() => {
        'member_name': widget.memberName,
        'gym_name': selectedGym.displayName,
        'date': waiverSignDateUtc(),
        'signer_name': _signerName,
      };

  QuillController _buildController() =>
      WaiverMarkdownEditor.controllerFromMarkdown(
        renderWaiverPlaceholders(_templateBody, _renderValues()),
        readOnly: true,
      );

  // Each keystroke of the signer name re-renders the body: dispose the old
  // read-only controller and rebuild it so {{signer_name}} tracks live. Bodies
  // are short, so a per-keystroke rebuild is fine.
  void _onPanelChanged(String name, bool consent) {
    final nameChanged = name != _signerName;
    setState(() {
      _signerName = name;
      _consent = consent;
      if (nameChanged) {
        _controller?.dispose();
        _controller = _buildController();
      }
    });
  }

  bool get _canSign =>
      _consent && _signerName.isNotEmpty && _phase == _Phase.form;

  Future<void> _submit() async {
    final waiver = _waiver;
    final versionId = waiver?.currentVersionId;
    if (waiver == null || versionId == null || !_canSign) return;
    setState(() => _phase = _Phase.submitting);
    try {
      await _repo.recordWaiverSignature(
        waiverId: widget.waiverId,
        gymId: widget.gymId,
        memberId: widget.memberId,
        waiverVersionId: versionId,
        signerName: _signerName,
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.success);
      widget.onSigned?.call();
    } on WaiverStaleVersionException {
      if (!mounted) return;
      setState(() => _phase = _Phase.stale);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: _title,
      body: _body(context),
      actions: _actions(context),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.success:
        return 'Waiver signed';
      case _Phase.stale:
        return 'Waiver updated';
      case _Phase.error:
        return 'Error';
      default:
        return _waiver?.name ?? 'Sign waiver';
    }
  }

  Widget _body(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: AppSpinner());
      case _Phase.form:
      case _Phase.submitting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            Text(
              'Signing on behalf of ${widget.memberName}. '
              'Read the waiver, then type your name and consent below.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text,
              ),
            ),
            SignWaiverPanel(
              controller: _controller!,
              enabled: _phase == _Phase.form,
              onChanged: _onPanelChanged,
            ),
          ],
        );
      case _Phase.success:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            Icon(
              Symbols.check_circle_sharp,
              size: DesignConstants.iconSizeBig,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.goodGreen,
            ),
            Text(
              'Waiver signed successfully for ${widget.memberName}.',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ],
        );
      case _Phase.stale:
        return Text(
          'This waiver was updated since it loaded. Close this dialog '
          'and open it again to sign the latest version.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
        );
      case _Phase.error:
        return Text(
          _errorMessage ?? 'An unexpected error occurred.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.badRed,
          ),
        );
    }
  }

  Widget? _actions(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return null;
      case _Phase.form:
        return AppDialogActions(
          primaryLabel: 'Sign waiver',
          primaryOnPressed: _canSign ? _submit : null,
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _Phase.submitting:
        return AppDialogActions(
          primaryLabel: 'Sign waiver',
          isLoading: true,
          secondaryLabel: 'Cancel',
        );
      case _Phase.success:
      case _Phase.stale:
      case _Phase.error:
        return AppDialogActions(
          primaryLabel: 'Close',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}
