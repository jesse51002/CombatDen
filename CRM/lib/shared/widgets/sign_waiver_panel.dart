import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/constants/esign_constants.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_markdown_editor.dart';

/// Shared presentational sign-waiver form.
///
/// Renders the waiver body read-only, a signer-name field, the
/// ESIGN/UETA disclosure, and a consent checkbox. Calls
/// [onChanged] with the current (signerName, consent) pair on
/// every user interaction. The parent decides readiness — it
/// enables its "Sign" button when `signerName.isNotEmpty && consent`.
///
/// The waiver body is displayed through the supplied [controller]
/// (already loaded, always read-only here).
class SignWaiverPanel extends StatefulWidget {
  final QuillController controller;

  /// Whether the name field and checkbox are interactive.
  final bool enabled;

  final void Function(String signerName, bool consent) onChanged;

  const SignWaiverPanel({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<SignWaiverPanel> createState() => _SignWaiverPanelState();
}

class _SignWaiverPanelState extends State<SignWaiverPanel> {
  final TextEditingController _name = TextEditingController();
  bool _consent = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _notify() =>
      widget.onChanged(_name.text.trim(), _consent);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        SizedBox(
          height: DesignConstants.dialogWaiverEditorHeight,
          child: WaiverMarkdownEditor(
            controller: widget.controller,
          ),
        ),
        TextField(
          controller: _name,
          enabled: widget.enabled,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
            labelText: 'Type full name to sign',
          ),
        ),
        // ESIGN/UETA disclosure
        Container(
          padding: const EdgeInsets.all(
            DesignConstants.spacingMedium,
          ),
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
            border: Border.all(
              color: DesignConstants.text.withValues(alpha: 0.1),
            ),
          ),
          child: Text(
            kEsignDisclosure,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
        InkWell(
          onTap: widget.enabled
              ? () {
                  setState(() => _consent = !_consent);
                  _notify();
                }
              : null,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Checkbox(
                value: _consent,
                onChanged: widget.enabled
                    ? (v) {
                        setState(() => _consent = v ?? false);
                        _notify();
                      }
                    : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: DesignConstants.spacingMedium,
                  ),
                  child: Text(
                    'I agree to the electronic consent terms above '
                    'and confirm my typed name is my legal signature.',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
