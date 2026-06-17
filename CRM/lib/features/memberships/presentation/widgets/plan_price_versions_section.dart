import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_with_count.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/presentation/dialogs/update_plan_price_dialog.dart';
import 'package:crm/features/memberships/presentation/widgets/plan_price_version_row.dart';
import 'package:crm/features/tasks/bloc/tasks_bloc.dart';
import 'package:crm/features/tasks/bloc/tasks_event.dart';
import 'package:crm/features/tasks/bloc/tasks_state.dart';
import 'package:crm/features/tasks/data/models/task_enums.dart';
import 'package:crm/features/tasks/data/repositories/tasks_repository.dart';
import 'package:crm/features/tasks/presentation/widgets/reprice_task_progress.dart';
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
  final TasksRepository tasksRepository;
  final String planId;
  final String gymId;
  final String? planName;
  final TextEditingController priceController;

  // Fired with the upgrade task id and target price once a reprice is
  // queued, so an ancestor (the Plans tab) can drive the shared progress
  // bar.
  final void Function(String taskId, int targetPriceCents)?
      onRepriceTaskStarted;

  const PlanPriceVersionsSection({
    super.key,
    required this.repository,
    required this.tasksRepository,
    required this.planId,
    required this.gymId,
    required this.priceController,
    this.planName,
    this.onRepriceTaskStarted,
  });

  @override
  State<PlanPriceVersionsSection> createState() =>
      _PlanPriceVersionsSectionState();
}

class _PlanPriceVersionsSectionState
    extends State<PlanPriceVersionsSection> {
  // Explains what upgrading does — no charge now, new price next cycle.
  static const _migrateExplanation =
      'Upgrading moves everyone still on a previous price onto the current '
      'price. They will not be charged now — the new price takes effect on '
      'their next billing cycle. A background task will track the upgrade for '
      'each member. Keep them on their current price to leave their billing '
      'unchanged until you upgrade later.';

  List<MembershipPlanPriceWithCount>? _prices;
  String? _error;
  bool _busy = false;

  // Old price versions whose upgrade has been queued this session — the
  // background task may not have completed, so don't re-trigger them.
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
      return;
    }
    // Best-effort: auto-start polling if a reprice is already in flight.
    if (mounted) await _autoStartPollingIfNeeded();
  }

  /// Checks for an ongoing reprice task targeting this plan's active price
  /// and starts polling it if found. No-ops silently on failure or if
  /// already polling.
  Future<void> _autoStartPollingIfNeeded() async {
    final active = _active;
    if (active == null) return;

    // Don't double-dispatch if the bloc is already tracking this task.
    final currentState = context.read<TasksBloc>().state;
    if (currentState is TaskPolling || currentState is TaskPollingDone) return;

    try {
      final tasks =
          await widget.tasksRepository.getOngoingTasks(widget.gymId);
      for (final task in tasks) {
        if (task.taskType != TaskType.membershipReprice) continue;
        if (task.isTerminal) continue;
        final targets =
            task.items.any((i) => i.targetPriceId == active.priceId);
        if (!targets) continue;
        if (!mounted) return;
        context.read<TasksBloc>().add(TaskPollingStarted(
              taskId: task.taskId,
              gymId: widget.gymId,
              planName: widget.planName,
              targetPriceCents: active.price,
            ));
        return;
      }
    } catch (_) {
      // Silent — ongoing-task check is best-effort.
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
        title: 'Upgrade members?',
        primaryLabel: 'Upgrade them',
        secondaryLabel: 'Keep current price',
      );
      if (migrate) await _runMigrate();
    }
  }

  Future<void> _migrateOld() async {
    if (_busy) return;
    final migrate = await _confirmMigrate(
      title: 'Upgrade members',
      primaryLabel: 'Upgrade',
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
      final result = await widget.repository.repriceAllOnPlan(
        widget.planId,
        widget.gymId,
      );
      if (!mounted) return;
      if (result.taskId == null) {
        _snack('Everyone is already on the latest price.');
      } else {
        final targetCents = _active?.price ?? 0;
        widget.onRepriceTaskStarted?.call(result.taskId!, targetCents);
        // Also drive the in-page progress bar immediately.
        context.read<TasksBloc>().add(TaskPollingStarted(
              taskId: result.taskId!,
              gymId: widget.gymId,
              planName: widget.planName,
              targetPriceCents: targetCents,
            ));
        _snack('Upgrade started for ${result.membershipCount} member(s).');
      }
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
    return BlocListener<TasksBloc, TasksState>(
      listenWhen: (prev, curr) =>
          curr is TaskPolling || curr is TaskPollingDone,
      listener: (context, state) => _load(),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
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
        const RepriceTaskProgress(),
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
