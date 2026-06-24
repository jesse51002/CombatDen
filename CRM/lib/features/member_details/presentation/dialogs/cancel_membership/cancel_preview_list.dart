import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/payer_invoice_change.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/widgets/invoice_preview_section.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The multi-person cancel preview: one attributed invoice section per
/// affected payer. Fetches the per-payer cost preview for [itemIds] once,
/// keeps only the payers actually affected (those who fund a cancelled
/// membership), and renders each as a "billed to {payer}" recurring
/// current → new. Different payers fund different memberships, so several
/// sections can appear — the disclaimer above explains why.
class CancelPreviewList extends StatefulWidget {
  final MemberRepository repository;
  final MemberDetailResponse member;
  final List<String> itemIds;
  final int fallbackMonthly;

  const CancelPreviewList({
    super.key,
    required this.repository,
    required this.member,
    required this.itemIds,
    required this.fallbackMonthly,
  });

  @override
  State<CancelPreviewList> createState() => _CancelPreviewListState();
}

class _CancelPreviewListState extends State<CancelPreviewList> {
  late Future<List<PayerInvoiceChange>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.previewCancelMemberships(
      widget.itemIds,
      widget.member.memberId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PayerInvoiceChange>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 80,
            child: Center(child: AppSpinner()),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Could not load the cancellation preview.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.badRed,
            ),
          );
        }
        final affected = (snapshot.data ?? const [])
            .where((c) => c.affected)
            .toList();
        if (affected.isEmpty) {
          return Text(
            'No change to recurring billing.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: affected.map(_payerSection).toList(),
        );
      },
    );
  }

  Widget _payerSection(PayerInvoiceChange change) {
    return InvoicePreviewSection(
      // The preview half is already fetched; loadCurrent supplies the
      // payer's current recurring bill as the "before".
      loadPreview: () async => change.preview,
      loadCurrent: () => widget.repository
          .getUpcomingInvoice(change.payerMemberId),
      showDueNow: false,
      recurringFallbackMonthly: widget.fallbackMonthly,
      payerName: change.payerFullName,
      payerPhotoUrl:
          widget.member.photoUrlForMember(change.payerMemberId),
      emptyLabel: 'No change to recurring billing.',
      errorLabel: 'Could not load the cancellation preview.',
    );
  }
}
