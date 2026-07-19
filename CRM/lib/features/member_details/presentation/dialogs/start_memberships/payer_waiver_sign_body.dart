import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/constants/waiver_parameters.dart';
import 'package:crm/core/utils/waiver_render.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';
import 'package:crm/shared/widgets/sign_waiver_panel.dart';

/// Shared sign body for authorizing a payer for a payee: the intro line plus
/// the read-only rendered waiver + signature panel. Owns the waiver
/// controller and re-renders it live so `{{signer_name}}` tracks the typed
/// name. The host fetches [waiverBody], owns the footer button, dispatches
/// `LinkParentRequested`, and watches for the commit.
///
/// The placeholder-substitution ("render") logic is the shared
/// `renderWaiverPlaceholders` util — kept in one place so both the link-first
/// and new-member flows render identically (no duplicated render logic).
class PayerWaiverSignBody extends StatefulWidget {
  /// The payer (signer) — fills `{{member_name}}` and `{{signer_name}}`.
  final String payerName;

  /// The payee the payer is authorized to pay for — `{{payee_name}}`.
  final String payeeName;

  /// The gym — `{{gym_name}}`.
  final String gymName;

  /// Raw template body of the payee's authorized-payer waiver.
  final String waiverBody;

  /// Whether the name field + consent checkbox are interactive.
  final bool enabled;

  /// The live (signerName, consent) pair on every interaction.
  final void Function(String signerName, bool consent) onChanged;

  const PayerWaiverSignBody({
    super.key,
    required this.payerName,
    required this.payeeName,
    required this.gymName,
    required this.waiverBody,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<PayerWaiverSignBody> createState() =>
      _PayerWaiverSignBodyState();
}

class _PayerWaiverSignBodyState extends State<PayerWaiverSignBody> {
  QuillController? _controller;
  String _signerName = '';

  @override
  void initState() {
    super.initState();
    _controller = _build();
  }

  @override
  void didUpdateWidget(covariant PayerWaiverSignBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waiverBody != widget.waiverBody) {
      _controller?.dispose();
      _controller = _build();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Map<String, String> _values() => {
        kWaiverParamMemberName: widget.payerName,
        kWaiverParamPayeeName: widget.payeeName,
        kWaiverParamGymName: widget.gymName,
        kWaiverParamDate: waiverSignDateUtc(),
        // Empty name -> a literal ___ blank (escaped so markdown never reads
        // it as a rule); fills live once the signer types.
        kWaiverParamSignerName:
            _signerName.isEmpty ? r'\_\_\_' : _signerName,
      };

  QuillController _build() =>
      WaiverMarkdownEditor.controllerFromMarkdown(
        renderWaiverPlaceholders(widget.waiverBody, _values()),
        readOnly: true,
      );

  void _onChanged(String name, bool consent) {
    final nameChanged = name != _signerName;
    setState(() {
      _signerName = name;
      if (nameChanged) {
        _controller?.dispose();
        _controller = _build();
      }
    });
    widget.onChanged(name, consent);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          '${widget.payerName} authorizes paying for '
          '${widget.payeeName}. Review the waiver, then sign below.',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
        ),
        SignWaiverPanel(
          controller: _controller!,
          enabled: widget.enabled,
          onChanged: _onChanged,
        ),
      ],
    );
  }
}
