import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/presentation/dialogs/card_field_box.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_field_label.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_note.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_secure_strip.dart';

/// Collects new card details via the Stripe [CardField]
/// (web-supported), tokenizes them into a Stripe
/// PaymentMethod client-side, and dispatches
/// [UpdateCardRequested] with the resulting
/// `payment_method_id` — the backend never sees raw PAN.
///
/// The request body the bloc builds is a
/// [MembersManagementUpdateCardRequest]; this dialog only
/// produces the `payment_method_id` it carries.
///
/// **The blast radius is stated before the field, not under it.** This is the
/// one control reachable from a checkout run that changes what happens to
/// memberships OUTSIDE it: the card saved here becomes the payer's default, so
/// every recurring membership they pay for moves onto it. That sentence is
/// warm — it is a consequence somebody should know before typing, not an error.
///
/// When a [card] is already on file and [allowRemove] is set the footer's left
/// gutter carries the destructive "Remove card". Removal isn't handled here —
/// tapping it pops `true` so the caller can run the existing confirmation flow
/// against a still-mounted page context.
class UpdateCardDialog extends StatefulWidget {
  final String memberName;
  final CardOnFile? card;

  /// The member whose saved card this edits. Null targets
  /// the currently viewed member; the start-memberships
  /// wizard sets it to the payer so the card is editable
  /// from any launching page.
  final String? targetMemberId;

  /// Whether to offer the destructive "Remove card" action.
  /// True on the member profile (the management surface);
  /// false in checkout flows (start / charge), where removing
  /// a card mid-purchase makes no sense — removal lives on the
  /// profile, behind its own confirmation, and this dialog
  /// says so rather than leaving staff hunting for it.
  final bool allowRemove;

  const UpdateCardDialog({
    super.key,
    required this.memberName,
    this.card,
    this.targetMemberId,
    this.allowRemove = true,
  });

  /// Resolves `true` only when the user taps "Remove card";
  /// `false` on save, cancel, or dismiss.
  static Future<bool> show({
    required BuildContext context,
    required String memberName,
    CardOnFile? card,
    String? targetMemberId,
    bool allowRemove = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<MemberDetailBloc>(),
        child: UpdateCardDialog(
          memberName: memberName,
          card: card,
          targetMemberId: targetMemberId,
          allowRemove: allowRemove,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<UpdateCardDialog> createState() =>
      _UpdateCardDialogState();
}

class _UpdateCardDialogState extends State<UpdateCardDialog> {
  bool _complete = false;
  bool _submitting = false;
  String? _error;

  /// What the rest of the copy calls them. A dialog that says the full name
  /// four times reads like a form letter.
  String get _first {
    final parts = widget.memberName.trim().split(' ');
    return parts.isEmpty || parts.first.isEmpty
        ? widget.memberName
        : parts.first;
  }

  Future<void> _submit() async {
    if (!_complete || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final paymentMethod =
          await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      context.read<MemberDetailBloc>().add(
            UpdateCardRequested(
              paymentMethod.id,
              targetMemberId: widget.targetMemberId,
            ),
          );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _kSaveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final error = _error;
    return TaskDialog(
      what: card == null ? _kAddWhat : _kWhat,
      who: widget.memberName,
      onClose: _submitting ? null : () => Navigator.of(context).pop(),
      closeTooltip: _kClose,
      title: card == null
          ? 'Add a card for $_first'
          : 'Replace $_first\'s card',
      subtitle: 'The new card becomes $_first\'s default straight away.',
      body: TaskPanel(
        children: [
          FlowInlineNotice(message: _blastRadius(card)),
          const TaskFieldLabel(label: 'Card details', note: _kStripeNote),
          CardFieldBox(
            onComplete: (isComplete) {
              if (isComplete != _complete) {
                setState(() => _complete = isComplete);
              }
            },
          ),
          FlowSecureStrip(gymName: selectedGym.gymName),
          if (error != null)
            Text(
              error,
              style: DesignConstants.pSemibold.copyWith(
                color: DesignConstants.badRed,
              ),
            ),
          if (card != null && !widget.allowRemove) TaskNote(_noRemove()),
        ],
      ),
      foot: TaskFoot(
        primaryLabel: _kSave,
        busy: _submitting,
        onPrimary: _complete && !_submitting ? _submit : null,
        secondaryLabel: _kCancel,
        onSecondary:
            _submitting ? null : () => Navigator.of(context).pop(),
        destructiveLabel:
            (card == null || !widget.allowRemove) ? null : _kRemove,
        onDestructive:
            _submitting ? null : () => Navigator.of(context).pop(true),
      ),
    );
  }

  /// Everything this one save reaches. It names the card being replaced, so
  /// nobody has to hold "which card was on file?" in their head while typing
  /// the next one.
  String _blastRadius(CardOnFile? card) {
    final reach = 'Every recurring membership $_first pays for — including '
        'ones this screen doesn\'t show — bills to it from its next cycle.';
    if (card == null) {
      return 'This becomes $_first\'s default card. $reach';
    }
    return 'This replaces the ${card.brand} ending ${card.lastFour}. $reach';
  }

  String _noRemove() =>
      'Cards can\'t be removed from here. Do that from $_first\'s profile, '
      'where what it stops paying for is visible.';
}

const String _kWhat = 'Update card on file';
const String _kAddWhat = 'Add a card on file';
const String _kClose = 'Close without saving a card';
const String _kStripeNote = 'Handled by Stripe';
const String _kSave = 'Save card';
const String _kCancel = 'Cancel';
const String _kRemove = 'Remove card';
const String _kSaveFailed =
    'We couldn\'t save that card. Check the details and try again.';
