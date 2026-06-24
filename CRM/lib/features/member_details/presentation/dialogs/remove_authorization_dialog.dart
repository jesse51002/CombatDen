import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/payer_invoice_change.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_complete_list.dart';
import 'package:crm/features/member_details/presentation/dialogs/cancel_membership/cancel_target.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Confirms removing a payment authorization, then shows the cascading cancel's
/// completion screen — the same succeeded/failed treatment a direct cancel uses.
///
/// Review phase: shows the cost preview ONLY when the payer is actually affected
/// (the backend's membership-level `affected` flag). When nothing is funded it
/// says so plainly. On "Remove & cancel" it dispatches
/// [RemoveAuthorizationRequested] (the backend cancels those memberships, then
/// de-authorizes the pair) and moves to the complete phase.
///
/// Complete phase: lists which funded memberships were cancelled / failed
/// ([CancelCompleteList]) plus a clear "{Payer} can no longer pay for {member}
/// — unlink complete" line.
///
/// Pair-scoped, so a single payer's outcome is shown. [payeeMemberId] is the
/// member being paid for; [payerMemberId] is the payer being removed.
class RemoveAuthorizationDialog extends StatefulWidget {
  final String payeeMemberId;
  final String payerMemberId;
  final String accountName;
  final int fallbackMonthly;

  /// The payer's photo, for the per-payer invoice attribution. Resolved by
  /// the caller (the payer is the focused member or the linked account, by
  /// section); null falls back to an initials avatar.
  final String? payerPhotoUrl;

  const RemoveAuthorizationDialog({
    super.key,
    required this.payeeMemberId,
    required this.payerMemberId,
    required this.accountName,
    required this.fallbackMonthly,
    this.payerPhotoUrl,
  });

  static Future<void> show({
    required BuildContext context,
    required String payeeMemberId,
    required String payerMemberId,
    required String accountName,
    required int fallbackMonthly,
    String? payerPhotoUrl,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: RemoveAuthorizationDialog(
          payeeMemberId: payeeMemberId,
          payerMemberId: payerMemberId,
          accountName: accountName,
          fallbackMonthly: fallbackMonthly,
          payerPhotoUrl: payerPhotoUrl,
        ),
      ),
    );
  }

  @override
  State<RemoveAuthorizationDialog> createState() =>
      _RemoveAuthorizationDialogState();
}

/// The two phases of the remove-authorization dialog.
enum _Phase { review, complete }

class _RemoveAuthorizationDialogState
    extends State<RemoveAuthorizationDialog> {
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());
  late final Future<List<PayerInvoiceChange>> _preview =
      _repository.previewRemoveAuthorization(
    widget.payeeMemberId,
    widget.payerMemberId,
  );

  _Phase _phase = _Phase.review;

  /// Snapshot of the funded memberships captured when the user confirms, so
  /// the completion screen can label rows by plan + member.
  List<CancelTarget> _confirmedTargets = const [];

  // ── Targets ──────────────────────────────────────────────

  /// The recurring memberships funded across the (payee, payer) relationship —
  /// exactly what the unlink cancels — resolved from the loaded member detail.
  /// The viewed member is either the payer (the funded rows live in `paysFor`)
  /// or the payee (the funded rows are their own memberships paid by the payer).
  List<CancelTarget> _fundedTargets(MemberDetailResponse member) {
    final payeeName =
        member.nameForMember(widget.payeeMemberId) ?? 'this member';
    final payerName =
        member.nameForMember(widget.payerMemberId) ?? widget.accountName;

    if (member.memberId == widget.payerMemberId) {
      // Viewed member is the payer → funded rows are in `paysFor`.
      for (final p in member.paysFor) {
        if (p.memberId != widget.payeeMemberId) continue;
        return p.memberships
            .map(
              (m) => CancelTarget(
                itemId: m.itemId,
                planName: m.planName,
                subjectName: payeeName,
                payerName: payerName,
                isOwn: false,
              ),
            )
            .toList();
      }
      return const [];
    }

    // Viewed member is the payee → funded rows are their own recurring
    // memberships paid by the payer.
    return member.memberships
        .where(
          (m) =>
              m.paidByMemberId == widget.payerMemberId &&
              m.planType?.toLowerCase() == 'recurring' &&
              !isTerminalStatus(m.status),
        )
        .map(
          (m) => CancelTarget(
            itemId: m.itemId,
            planName: m.planName,
            subjectName: payeeName,
            payerName: payerName,
            isOwn: false,
          ),
        )
        .toList();
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MemberDetailBloc, MemberDetailState>(
      listenWhen: (prev, curr) {
        if (curr is! MemberDetailLoaded) return false;
        if (prev is! MemberDetailLoaded) return false;
        // The remove-authorization request settled — flip to the complete
        // phase whether it produced an outcome (cancelled rows) or a hard
        // error (the screen-level error path shows the message).
        return prev.isRemovingAuthorization &&
            !curr.isRemovingAuthorization;
      },
      listener: (context, state) {
        setState(() => _phase = _Phase.complete);
      },
      builder: (context, blocState) {
        final isRemoving = blocState is MemberDetailLoaded &&
            blocState.isRemovingAuthorization;
        return AppDialog(
          title: 'Remove authorization',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: _buildBody(
              blocState: blocState,
              isRemoving: isRemoving,
            ),
          ),
          actions: _buildActions(isRemoving: isRemoving),
        );
      },
    );
  }

  List<Widget> _buildBody({
    required MemberDetailState blocState,
    required bool isRemoving,
  }) {
    if (_phase == _Phase.review) return _reviewBody();

    if (isRemoving) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: DesignConstants.spacingBig,
          ),
          child: Center(child: AppSpinner()),
        ),
      ];
    }
    if (blocState is MemberDetailLoaded &&
        blocState.removeAuthorizationOutcome != null) {
      return [
        _UnlinkSuccessLine(
          payerName: widget.accountName,
          payeeName: _payeeName(blocState.member),
        ),
        CancelCompleteList(
          targets: _confirmedTargets,
          outcome: blocState.removeAuthorizationOutcome!,
        ),
      ];
    }
    // No outcome → the remove failed hard (the bloc set actionError). Show the
    // failure inline so the dialog doesn't look like a silent success.
    return const [_UnlinkFailedNote()];
  }

  List<Widget> _reviewBody() {
    return [
      Text(
        'Removing ${widget.accountName} cancels the recurring memberships '
        'funded across this relationship.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
      FutureBuilder<List<PayerInvoiceChange>>(
        future: _preview,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 80,
              child: Center(child: AppSpinner()),
            );
          }
          final affected = (snapshot.data ?? const [])
              .where((c) => c.affected)
              .toList();
          if (affected.isEmpty) {
            return _NoChangeNote();
          }
          // Pair-scoped → one affected payer.
          final change = affected.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingMedium,
            children: [
              // A removal is always a single payer→payee relationship, so the
              // multi-payer "separate invoice per payer" disclaimer (shown on
              // the cancel dialog) does not apply here.
              Text(
                'Billing after removal',
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              InvoicePreviewSection(
                loadPreview: () async => change.preview,
                loadCurrent: () => _repository
                    .getUpcomingInvoice(change.payerMemberId),
                showDueNow: false,
                recurringFallbackMonthly: widget.fallbackMonthly,
                payerName: change.payerFullName,
                payerPhotoUrl: widget.payerPhotoUrl,
                emptyLabel: 'No recurring billing change.',
                errorLabel: 'Could not load the billing preview.',
              ),
            ],
          );
        },
      ),
    ];
  }

  AppDialogActions _buildActions({required bool isRemoving}) {
    if (_phase == _Phase.review) {
      return AppDialogActions(
        primaryLabel: 'Remove & cancel',
        primaryColor: DesignConstants.badRed,
        primaryOnPressed: _confirmRemove,
        secondaryLabel: 'Cancel',
        secondaryOnPressed: () => Navigator.of(context).pop(),
      );
    }
    return AppDialogActions(
      primaryLabel: 'Done',
      primaryOnPressed: isRemoving ? null : _close,
    );
  }

  void _confirmRemove() {
    final s = context.read<MemberDetailBloc>().state;
    if (s is MemberDetailLoaded) {
      _confirmedTargets = _fundedTargets(s.member);
    }
    // Move to the complete phase's loading state immediately; the
    // BlocConsumer listener confirms it once the request settles.
    setState(() => _phase = _Phase.complete);
    context.read<MemberDetailBloc>().add(
          RemoveAuthorizationRequested(
            memberId: widget.payeeMemberId,
            payerMemberId: widget.payerMemberId,
          ),
        );
  }

  void _close() {
    context
        .read<MemberDetailBloc>()
        .add(const RemoveAuthorizationOutcomeCleared());
    Navigator.of(context).pop();
  }

  String _payeeName(MemberDetailResponse member) =>
      member.nameForMember(widget.payeeMemberId) ?? 'this member';
}

/// The success banner for a completed unlink — states plainly that the payer
/// can no longer pay for the member.
class _UnlinkSuccessLine extends StatelessWidget {
  final String payerName;
  final String payeeName;

  const _UnlinkSuccessLine({
    required this.payerName,
    required this.payeeName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          Symbols.link_off_sharp,
          size: DesignConstants.iconSizeMedium,
          color: DesignConstants.goodGreen,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Text(
            '$payerName can no longer pay for $payeeName — unlink complete.',
            style: DesignConstants.p,
          ),
        ),
      ],
    );
  }
}

class _UnlinkFailedNote extends StatelessWidget {
  const _UnlinkFailedNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          Symbols.error_sharp,
          size: DesignConstants.iconSizeMedium,
          color: DesignConstants.badRed,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Text(
            'The authorization couldn\'t be removed — a Stripe error '
            'prevented it. Reload and try again.',
            style: DesignConstants.p,
          ),
        ),
      ],
    );
  }
}

class _NoChangeNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Text(
        'No memberships are funded across this relationship — removing it '
        'changes no billing.',
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
    );
  }
}
