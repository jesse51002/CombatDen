import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_panel.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers/waivers_run_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_sign_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_waiver_doc_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_waiver_status.dart';

/// The waivers step's fold: the document on the left, the signature and the
/// run's own list on the right.
///
/// The document is the wider half because reading it is the job; the column
/// beside it is three controls and a list, and scrolls inside itself so the
/// footer never moves. With the run finished there is nothing to read, so the
/// list stands alone.
class WizardWaiversBody extends StatelessWidget {
  final bool stale;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  /// The rendered, read-only body. Null while the read is in flight, after it
  /// failed, and once the run is done.
  final QuillController? controller;

  final String? waiverName;
  final int? versionNumber;

  /// Whose signature this is.
  final String memberName;

  final TextEditingController signerName;
  final ValueChanged<String> onSignerNameChanged;
  final bool consent;
  final ValueChanged<bool> onConsentChanged;

  /// Every signature the run owes, marked.
  final List<WizardWaiverEntry> entries;

  /// Nothing left to sign — the document half is dropped entirely.
  final bool done;

  const WizardWaiversBody({
    super.key,
    required this.stale,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.controller,
    required this.memberName,
    required this.signerName,
    required this.onSignerNameChanged,
    required this.consent,
    required this.onConsentChanged,
    required this.entries,
    required this.done,
    this.waiverName,
    this.versionNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        // A republished waiver announces itself rather than swapping the text
        // under somebody mid-signature.
        if (stale)
          const FlowInlineNotice(message: WizardWaiversCopy.staleNotice),
        Expanded(
          child: done
              ? SingleChildScrollView(child: _RunPanel(entries: entries))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DesignConstants.spacingLarge,
                  children: [
                    Expanded(flex: 3, child: _Document(this)),
                    Expanded(
                      flex: 2,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          spacing: DesignConstants.spacingLarge,
                          children: [
                            FlowSignPanel(
                              memberName: memberName,
                              eyebrow: WizardWaiversCopy.signingForEyebrow,
                              signerName: signerName,
                              onSignerNameChanged: onSignerNameChanged,
                              consent: consent,
                              onConsentChanged: onConsentChanged,
                            ),
                            _RunPanel(entries: entries),
                          ],
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

/// The document, or the read that has not produced one yet. A failed read is a
/// retry in place, never a dead end — the escape in the gutter is still the
/// way out.
class _Document extends StatelessWidget {
  final WizardWaiversBody body;

  const _Document(this.body);

  @override
  Widget build(BuildContext context) {
    final controller = body.controller;
    if (controller == null) {
      return FlowWaiverStatus(
        loading: body.loading,
        failed: body.failed,
        onRetry: body.onRetry,
      );
    }
    final version = body.versionNumber;
    return FlowWaiverDocPanel(
      title: body.waiverName ?? WizardWaiversCopy.unnamedWaiver,
      versionLabel:
          version == null ? null : WizardWaiversCopy.versionLabel(version),
      controller: controller,
    );
  }
}

class _RunPanel extends StatelessWidget {
  final List<WizardWaiverEntry> entries;

  const _RunPanel({required this.entries});

  @override
  Widget build(BuildContext context) {
    return WizardPanel(
      children: [WizardWaiversRunGroup(entries: entries)],
    );
  }
}
