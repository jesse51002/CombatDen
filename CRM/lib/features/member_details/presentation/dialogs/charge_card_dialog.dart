import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/repositories/member_repository.dart';
import 'package:crm/features/member_details/presentation/dialogs/charge_card_payment_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/member_detail_bloc_settle.dart';
import 'package:crm/features/member_details/presentation/dialogs/charge_card_success_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/custom_card_capture.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/one_time_card_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/update_card_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

enum _ChargeStep { payer, payment, processing, success }

/// One-time ad-hoc charge for a member, billed to a chosen payer's
/// card. Two concerns are kept separate: first WHO is paying (a payer
/// radio step, shown only for a linked family), then WHICH card — the
/// payer's saved default (editable / set-a-new-default) or a one-off
/// card for this charge. The saved card is the SELECTED PAYER's own
/// card (fetched per payer, like the start wizard), so the card shown
/// is the one that will actually be charged. Submitting drives an
/// in-dialog spinner → success step; the outcome rides the bloc's
/// charge channel so the screen-level overlay + error dialog never
/// fire while this dialog is open.
class ChargeCardDialog extends StatefulWidget {
  final MemberDetailResponse member;

  const ChargeCardDialog({super.key, required this.member});

  static Future<void> show({
    required BuildContext context,
    required MemberDetailResponse member,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: ChargeCardDialog(member: member),
      ),
    );
  }

  @override
  State<ChargeCardDialog> createState() =>
      _ChargeCardDialogState();
}

class _ChargeCardDialogState extends State<ChargeCardDialog> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final MemberRepository _repository =
      MemberRepository(apiClient: ApiClient());

  late final MemberDetailBloc _bloc;
  late StartMembershipParticipant _payer;
  late _ChargeStep _step;
  late final int _successTokenAtOpen;

  /// The selected payer's billing detail — their OWN saved card lives
  /// at its root. Fetched per payer so the card shown is the one that
  /// will actually be charged.
  MemberDetailResponse? _payerDetail;
  final Map<String, MemberDetailResponse> _memberDetails = {};

  /// A one-off card for this charge (null = bill the saved default).
  CustomCardCapture? _customCard;

  /// When true the charge is settled out of band (cash) — no card.
  bool _paidCash = false;
  String? _error;

  // Retained at submit so the success step renders without re-reading
  // the form (the charge endpoint returns no payload).
  int? _chargedCents;
  String? _chargedReason;
  String? _chargedCardLabel;
  bool _chargedPaidCash = false;

  bool get _hasPayerChoice =>
      widget.member.authorizedPayers.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<MemberDetailBloc>();
    final st = _bloc.state;
    _successTokenAtOpen =
        st is MemberDetailLoaded ? st.chargeCardSuccess : 0;
    // Clear any prior charge error so a stale failure never flashes.
    // Done in initState (never dispose — emitting during the dialog's
    // own teardown races it).
    _bloc.add(const ChargeCardOutcomeCleared());
    _initPayer();
  }

  /// Default payer = the viewed member (self-pay). The payer step is
  /// only reached when there's a real choice — the member has
  /// authorized payers whose card could be charged instead; a member
  /// with none opens straight on the payment step.
  void _initPayer() {
    final viewed = widget.member;
    _memberDetails[viewed.memberId] = viewed;
    _payer = StartMembershipParticipant(
      memberId: viewed.memberId,
      name: viewed.fullName,
      photoUrl: viewed.photoUrl,
      isPayer: true,
    );
    _payerDetail = viewed;
    _step = viewed.authorizedPayers.isEmpty
        ? _ChargeStep.payment
        : _ChargeStep.payer;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadPayerDetail() async {
    final cached = _memberDetails[_payer.memberId];
    if (cached != null) {
      setState(() => _payerDetail = cached);
      return;
    }
    try {
      final detail =
          await _repository.getMemberDetail(_payer.memberId);
      if (!mounted) return;
      setState(() {
        _payerDetail = detail;
        _memberDetails[detail.memberId] = detail;
      });
    } catch (_) {
      // Best-effort: the saved-card section shows "no card" until it
      // loads; the backend stays the source of truth.
    }
  }

  void _onPayerSelected(StartMembershipParticipant p) {
    if (p.memberId == _payer.memberId) return;
    setState(() {
      _payer = StartMembershipParticipant(
        memberId: p.memberId,
        name: p.name,
        photoUrl: p.photoUrl,
        isPayer: true,
      );
      _payerDetail = _memberDetails[p.memberId];
      // A one-off card belongs to the payer who entered it.
      _customCard = null;
    });
    if (_payerDetail == null) _loadPayerDetail();
  }

  /// Sets a NEW saved default for the payer via the existing
  /// update-card flow (no remove option mid-charge), then re-reads the
  /// payer's billing so the new card shows.
  Future<void> _onEditCardOnFile() async {
    final st = _bloc.state;
    final tokenBefore =
        st is MemberDetailLoaded ? st.refreshToken : -1;
    await UpdateCardDialog.show(
      context: context,
      memberName: _payer.name,
      card: _payerDetail?.cardOnFile,
      targetMemberId: _payer.memberId,
      allowRemove: false,
    );
    if (!mounted) return;
    await awaitMemberDetailSettle(_bloc, tokenBefore);
    if (!mounted) return;
    _memberDetails.remove(_payer.memberId);
    await _loadPayerDetail();
  }

  Future<void> _onAddOrChangeCustomCard() async {
    final captured =
        await OneTimeCardDialog.show(context: context);
    if (captured == null || !mounted) return;
    setState(() => _customCard = captured);
  }

  void _onRemoveCustomCard() {
    setState(() => _customCard = null);
  }

  void _onPaidCashChanged(bool value) {
    setState(() => _paidCash = value);
  }

  String? _resolveCardLabel() {
    final oneOff = _customCard;
    if (oneOff != null) return oneOff.display;
    final saved = _payerDetail?.cardOnFile;
    if (saved == null) return null;
    return '${saved.brand} ···· ${saved.lastFour}';
  }

  void _submit() {
    final cents = parseDollarsToCents(_amount.text);
    final description = _description.text.trim();
    if (cents == null) {
      setState(() =>
          _error = 'Enter a valid amount greater than \$0.');
      return;
    }
    if (description.isEmpty) {
      setState(
          () => _error = 'Add a short reason for the charge.');
      return;
    }
    final cardLabel = _paidCash ? null : _resolveCardLabel();
    if (!_paidCash && cardLabel == null) {
      setState(() => _error =
          'Add a card on file or use a one-off card to charge.');
      return;
    }
    setState(() {
      _error = null;
      _chargedCents = cents;
      _chargedReason = description;
      _chargedCardLabel = cardLabel;
      _chargedPaidCash = _paidCash;
      _step = _ChargeStep.processing;
    });
    _bloc.add(ChargeCardRequested(
      amount: cents,
      description: description,
      paidByMemberId: _payer.memberId,
      paymentMethodId: _paidCash ? null : _customCard?.pmId,
      paidCash: _paidCash,
    ));
  }

  void _onState(BuildContext context, MemberDetailState state) {
    if (state is! MemberDetailLoaded) return;
    if (_step != _ChargeStep.processing) return;
    final err = state.chargeCardError;
    if (err != null) {
      setState(() {
        _error = err;
        _step = _ChargeStep.payment;
      });
      _bloc.add(const ChargeCardOutcomeCleared());
      return;
    }
    if (state.chargeCardSuccess != _successTokenAtOpen) {
      setState(() => _step = _ChargeStep.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberDetailBloc, MemberDetailState>(
      listenWhen: (prev, curr) => curr is MemberDetailLoaded,
      listener: _onState,
      child: AppDialog(
        title: 'Charge card',
        showCloseButton: _step != _ChargeStep.processing,
        body: _buildBody(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _ChargeStep.payer:
        return StartMembershipParticipantStep(
          member: widget.member,
          candidates: widget.member.authorizedPayers,
          selectedMemberId: _payer.memberId,
          payerMemberId: _payer.memberId,
          onSelected: _onPayerSelected,
          title: "Who's paying for ${widget.member.firstName}?",
          subtitle: 'Whose card is charged for '
              "${widget.member.firstName}'s purchase.",
          subtitleBuilder: (p) =>
              p.memberId == widget.member.memberId
                  ? 'Self-pay'
                  : 'Authorized payer',
        );
      case _ChargeStep.payment:
        return ChargeCardPaymentStep(
          beneficiaryName: widget.member.firstName,
          cardOnFile: _payerDetail?.cardOnFile,
          customCard: _customCard,
          amountController: _amount,
          descriptionController: _description,
          error: _error,
          paidCash: _paidCash,
          onPaidCashChanged: _onPaidCashChanged,
          onEditCardOnFile: _onEditCardOnFile,
          onAddOrChangeCustomCard: _onAddOrChangeCustomCard,
          onRemoveCustomCard: _onRemoveCustomCard,
        );
      case _ChargeStep.processing:
        return const _ChargeProcessing();
      case _ChargeStep.success:
        return ChargeCardSuccessView(
          amountCents: _chargedCents!,
          paidCash: _chargedPaidCash,
          cardLabel: _chargedCardLabel,
          reason: _chargedReason!,
          payerName: _hasPayerChoice ? _payer.name : null,
        );
    }
  }

  Widget _buildActions() {
    switch (_step) {
      case _ChargeStep.payer:
        return AppDialogActions(
          primaryLabel: 'Next',
          primaryOnPressed: () =>
              setState(() => _step = _ChargeStep.payment),
          secondaryLabel: 'Cancel',
          secondaryOnPressed: () => Navigator.of(context).pop(),
        );
      case _ChargeStep.payment:
        return AppDialogActions(
          primaryLabel: 'Charge',
          primaryOnPressed: _submit,
          secondaryLabel: _hasPayerChoice ? 'Back' : 'Cancel',
          secondaryOnPressed: _hasPayerChoice
              ? () => setState(() {
                    _step = _ChargeStep.payer;
                    _error = null;
                  })
              : () => Navigator.of(context).pop(),
        );
      case _ChargeStep.processing:
        return const AppDialogActions(
          primaryLabel: 'Charge',
          isLoading: true,
          primaryOnPressed: null,
        );
      case _ChargeStep.success:
        return AppDialogActions(
          primaryLabel: 'Done',
          primaryOnPressed: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _ChargeProcessing extends StatelessWidget {
  const _ChargeProcessing();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.dialogProcessingHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            const AppSpinner(),
            Text(
              'Charging…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
