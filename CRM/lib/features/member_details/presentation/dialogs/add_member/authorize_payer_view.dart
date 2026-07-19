import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/authorize_progress.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/group_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/payer_waiver_sign_body.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// One pane of the authorize sequence: the payee-progress row plus the current
/// payee's waiver state — fetching (spinner), a load error (retry), or the
/// ready sign body. An inline error + retry surfaces a failed commit for the
/// SAME payee without leaving the pane.
class AuthorizePayerView extends StatelessWidget {
  final List<GroupMember> payees;
  final Set<String> committedIds;
  final int currentIndex;

  final String payerName;
  final String payeeName;
  final String gymName;

  final bool fetchingWaiver;
  final String? waiverError;
  final String waiverBody;
  final bool submitting;

  /// Set when the last commit for this payee failed — shown inline with retry.
  final String? commitError;

  final VoidCallback onWaiverRetry;
  final VoidCallback onCommitRetry;
  final void Function(String signerName, bool consent) onSignChanged;

  const AuthorizePayerView({
    super.key,
    required this.payees,
    required this.committedIds,
    required this.currentIndex,
    required this.payerName,
    required this.payeeName,
    required this.gymName,
    required this.fetchingWaiver,
    required this.waiverError,
    required this.waiverBody,
    required this.submitting,
    required this.commitError,
    required this.onWaiverRetry,
    required this.onCommitRetry,
    required this.onSignChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        AuthorizeProgress(
          payees: payees,
          committedIds: committedIds,
          currentIndex: currentIndex,
        ),
        _paneBody(),
      ],
    );
  }

  Widget _paneBody() {
    if (fetchingWaiver) {
      return const SizedBox(
        height: DesignConstants.dialogProcessingHeight,
        child: Center(child: AppSpinner()),
      );
    }
    if (waiverError != null) {
      return _InlineError(message: waiverError!, onRetry: onWaiverRetry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (commitError != null)
          _InlineError(message: commitError!, onRetry: onCommitRetry),
        PayerWaiverSignBody(
          payerName: payerName,
          payeeName: payeeName,
          gymName: gymName,
          waiverBody: waiverBody,
          enabled: !submitting,
          onChanged: onSignChanged,
        ),
      ],
    );
  }
}

/// A badRed error line with a Retry action, reused for the waiver-load failure
/// and a failed authorize commit.
class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.badRed.withValues(alpha: 0.12),
        borderRadius:
            BorderRadius.circular(DesignConstants.radiusSmall),
        border: Border.all(color: DesignConstants.badRed),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.error_sharp,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.badRed,
          ),
          Expanded(
            child: Text(
              message,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
          AppOutlineButton(
            text: 'Retry',
            onPressed: onRetry,
            borderRadius: DesignConstants.radiusSmall,
            textStyle: DesignConstants.pSmall,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingSmall,
              vertical: DesignConstants.spacingSmall,
            ),
          ),
        ],
      ),
    );
  }
}
