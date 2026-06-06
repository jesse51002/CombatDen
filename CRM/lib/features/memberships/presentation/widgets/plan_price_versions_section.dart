import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_with_count.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/presentation/dialogs/update_plan_price_dialog.dart';
import 'package:crm/features/memberships/presentation/widgets/plan_price_version_row.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/loading_dialog.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';

/// Edit-mode price control: the plan's current price plus any older
/// version that still has members on it, with an "Update price" button
/// and a per-old-price "Migrate" action that moves members forward.
///
/// Prices are versioned/immutable on the backend, so updating a price
/// mints a new active version (the old one is kept for the members still
/// on it). Updating the price and migrating both act immediately — they
/// are not staged behind the form's Save button. After a price is updated
/// the shared [priceController] is updated so the linked-discount totals
/// reflect the new current price, and a follow-up dialog offers to migrate
/// the members still on the previous price.
class PlanPriceVersionsSection extends StatefulWidget {
  final MembershipsRepository repository;
  final String planId;
  final String gymId;
  final TextEditingController priceController;

  const PlanPriceVersionsSection({
    super.key,
    required this.repository,
    required this.planId,
    required this.gymId,
    required this.priceController,
  });

  @override
  State<PlanPriceVersionsSection> createState() =>
      _PlanPriceVersionsSectionState();
}

class _PlanPriceVersionsSectionState extends State<PlanPriceVersionsSection> {
  // Explains what migrating does — no charge now, new price next cycle.
  static const _migrateExplanation =
      'Migrating moves everyone still on a previous price onto the current '
      'price. They are not charged anything now — the new price takes effect '
      'on their next billing cycle. Keep them on their current price to leave '
      'their billing unchanged until you migrate later.';

  List<MembershipPlanPriceWithCount>? _prices;
  String? _error;
  bool _busy = false;

  // Old price versions whose migration has been queued this session — the
  // background sync may not have completed, so don't re-trigger them.
  final Set<String> _migrating = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final prices = await widget.repository.listPlanPrices(
        widget.planId,
        widget.gymId,
      );
      if (mounted) setState(() => _prices = prices);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  MembershipPlanPriceWithCount? get _active {
    final prices = _prices;
    if (prices == null) return null;
    for (final p in prices) {
      if (p.isActive) return p;
    }
    return null;
  }

  List<MembershipPlanPriceWithCount> get _occupiedOld => [
        for (final p in _prices ?? const <MembershipPlanPriceWithCount>[])
          if (!p.isActive && p.memberCount > 0) p,
      ];

  int get _membersOnOldPrices =>
      _occupiedOld.fold<int>(0, (n, p) => n + p.memberCount);

  Future<void> _updatePrice() async {
    if (_busy) return;
    final cents = await UpdatePlanPriceDialog.show(context);
    if (cents == null || !mounted) return;

    setState(() => _busy = true);
    LoadingDialog.show(context, message: 'Updating price…');
    try {
      await widget.repository.setPlanPrice(
        MembershipPlanPriceRequest(
          planId: widget.planId,
          gymId: widget.gymId,
          price: cents,
        ),
      );
      // Keep the linked-discount math in sync with the new current price.
      widget.priceController.text = (cents / 100).toStringAsFixed(2);
      await _load();
    } catch (e) {
      if (mounted) {
        LoadingDialog.dismiss(context);
        setState(() => _busy = false);
      }
      _snack(e.toString(), isError: true);
      return;
    }
    if (!mounted) return;
    LoadingDialog.dismiss(context);
    setState(() => _busy = false);

    // The just-replaced price now holds the existing members — offer to
    // move them onto the new price.
    if (_membersOnOldPrices > 0) {
      final migrate = await _confirmMigrate(
        title: 'Migrate members?',
        primaryLabel: 'Migrate them',
        secondaryLabel: 'Keep current price',
      );
      if (migrate) await _runMigrate();
    }
  }

  Future<void> _migrateOld() async {
    if (_busy) return;
    final migrate = await _confirmMigrate(
      title: 'Migrate members',
      primaryLabel: 'Migrate',
      secondaryLabel: 'Cancel',
    );
    if (migrate) await _runMigrate();
  }

  Future<bool> _confirmMigrate({
    required String title,
    required String primaryLabel,
    required String secondaryLabel,
  }) async {
    final result = await AppDialog.show<bool>(
      context: context,
      title: title,
      primaryLabel: primaryLabel,
      secondaryLabel: secondaryLabel,
      body: Text(
        '$_membersOnOldPrices member(s) are still on a previous price.\n\n'
        '$_migrateExplanation',
        style: DesignConstants.p,
      ),
      primaryOnPressed: (dialogContext) =>
          Navigator.of(dialogContext).pop(true),
      secondaryOnPressed: (dialogContext) =>
          Navigator.of(dialogContext).pop(false),
    );
    return result ?? false;
  }

  Future<void> _runMigrate() async {
    setState(() {
      for (final p in _occupiedOld) {
        _migrating.add(p.priceId);
      }
    });
    try {
      await widget.repository.migrateAllToCurrentPrice(
        widget.planId,
        widget.gymId,
      );
      _snack('Migration queued');
      await _load();
    } catch (e) {
      if (mounted) setState(_migrating.clear);
      _snack(e.toString(), isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: DesignConstants.p.copyWith(color: DesignConstants.surface),
        ),
        backgroundColor:
            isError ? DesignConstants.badRed : DesignConstants.goodGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          ErrorMessage(message: _error!),
          AppOutlineButton(text: 'Retry', onPressed: _load),
        ],
      );
    }
    if (_prices == null) return const AppSpinner();

    final active = _active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (active != null)
          PlanPriceVersionRow(price: active, isCurrent: true),
        for (final old in _occupiedOld)
          PlanPriceVersionRow(
            price: old,
            isCurrent: false,
            migrating: _migrating.contains(old.priceId),
            onMigrate: _busy ? null : _migrateOld,
          ),
        AppOutlineButton(
          text: 'Update price',
          onPressed: _busy ? null : _updatePrice,
          borderRadius: DesignConstants.radiusSmall,
          icon: Icon(
            Icons.edit,
            size: DesignConstants.iconSizeSmall,
            color: DesignConstants.text,
          ),
        ),
      ],
    );
  }
}
