import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/constants/waiver_parameters.dart';
import 'package:crm/core/utils/waiver_render.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/payer_sign_column.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_person_copy.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_waiver_doc_panel.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';

/// Authorizing a payer for a payee: the agreement beside the panel it is
/// signed on. The document is the wider half because reading it is the job.
///
/// It owns the waiver controller and re-renders it live, so every placeholder
/// is filled while it is read — `{{member_name}}` is the PAYER (they are the
/// party agreeing), `{{payee_name}}` the person being paid for, plus the gym,
/// the date, and a `{{signer_name}}` that tracks the typed name letter by
/// letter. Nobody signs a document with a blank where their name goes.
///
/// The host fetches [waiverBody], owns the footer button, dispatches
/// `LinkParentRequested`, and watches for the commit; this body raises only
/// the live (name, consent) pair.
///
/// The placeholder substitution is the shared `renderWaiverPlaceholders` util,
/// so every surface that renders this agreement renders it identically.
class PayerWaiverSignBody extends StatefulWidget {
  /// The payer (signer) — fills `{{member_name}}` and `{{signer_name}}`.
  final String payerName;

  /// The payee the payer is authorized to pay for — `{{payee_name}}`.
  final String payeeName;

  /// The gym — `{{gym_name}}`.
  final String gymName;

  /// Raw template body of the payee's authorized-payer waiver.
  final String waiverBody;

  /// The waiver's own name, for the document panel's head. Null falls back to
  /// what the agreement always is.
  final String? waiverName;

  /// Whether the name field + consent tick are interactive.
  final bool enabled;

  /// Take the whole height the host gives and lay the two panels side by side,
  /// the document scrolling inside itself — what a host with a fold hands it.
  /// False stacks them at a fixed reading height instead, for a host that lays
  /// this out inside a scroll view and has no fold to give.
  final bool fillHeight;

  /// The live (signerName, consent) pair on every interaction.
  final void Function(String signerName, bool consent) onChanged;

  const PayerWaiverSignBody({
    super.key,
    required this.payerName,
    required this.payeeName,
    required this.gymName,
    required this.waiverBody,
    required this.onChanged,
    this.waiverName,
    this.enabled = true,
    this.fillHeight = false,
  });

  @override
  State<PayerWaiverSignBody> createState() =>
      _PayerWaiverSignBodyState();
}

class _PayerWaiverSignBodyState extends State<PayerWaiverSignBody> {
  final TextEditingController _signer = TextEditingController();
  QuillController? _controller;
  String _signerName = '';
  bool _consent = false;

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
    _signer.dispose();
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

  void _onNameChanged(String raw) {
    final name = raw.trim();
    final changed = name != _signerName;
    setState(() {
      _signerName = name;
      if (changed) {
        _controller?.dispose();
        _controller = _build();
      }
    });
    widget.onChanged(name, _consent);
  }

  void _onConsentChanged(bool value) {
    setState(() => _consent = value);
    widget.onChanged(_signerName, value);
  }

  @override
  Widget build(BuildContext context) {
    final gym = widget.gymName.trim();
    final name = widget.waiverName?.trim() ?? '';
    final document = FlowWaiverDocPanel(
      title: name.isEmpty ? StartPersonCopy.signDocTitle : name,
      versionLabel: gym.isEmpty ? null : gym,
      controller: _controller!,
    );
    // A commit in flight leaves the panel readable but untouchable — the same
    // freeze the disabled field and checkbox gave, without a second copy of
    // the sign panel that only exists to be greyed out.
    final signing = IgnorePointer(
      ignoring: !widget.enabled,
      child: PayerSignColumn(
        payerName: widget.payerName,
        payeeName: widget.payeeName,
        signerName: _signer,
        onSignerNameChanged: _onNameChanged,
        consent: _consent,
        onConsentChanged: _onConsentChanged,
      ),
    );
    if (!widget.fillHeight) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints.tightFor(
              height: DesignConstants.dialogWaiverEditorHeight,
            ),
            child: document,
          ),
          signing,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(flex: 3, child: document),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(child: signing),
        ),
      ],
    );
  }
}
