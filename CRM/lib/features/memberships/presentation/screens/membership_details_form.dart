import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/linked_discount_value.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/memberships/data/models/membership_plan_create_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_update_request.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/linked_discount_section.dart';
import 'package:crm/features/memberships/presentation/widgets/plan_price_versions_section.dart';
import 'package:crm/features/memberships/presentation/widgets/plan_type_cards.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_multi_select.dart';
import 'package:crm/features/memberships/presentation/widgets/icon_option_cards.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';

/// The Membership Details create/edit form. Performs the create /
/// update / delete directly via [MembershipsRepository] and pops
/// `true` on success so the caller can refresh its list.
class MembershipDetailsForm extends StatefulWidget {
  final MembershipsRepository repository;
  final String gymId;
  final MembershipPlanResponse? plan;

  const MembershipDetailsForm({
    super.key,
    required this.repository,
    required this.gymId,
    this.plan,
  });

  @override
  State<MembershipDetailsForm> createState() =>
      _MembershipDetailsFormState();
}

class _MembershipDetailsFormState extends State<MembershipDetailsForm> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _classCount = TextEditingController(text: '10');
  final _trialLength = TextEditingController(text: '1');
  final _formKey = GlobalKey<FormState>();

  // Family tiers as real discount values ($ off / % off), owned by the
  // linked-discount section and mirrored here for save.
  List<LinkedDiscountValue> _linkedValues = const [];

  // The form reads best capped to a column width rather than stretched
  // across the whole content area.
  static const double _maxContentWidth = 640;

  PlanType _type = PlanType.recurring;
  DurationUnit _trialUnit = DurationUnit.week;
  bool _unlimited = true;
  bool _linkedEnabled = false;
  final Set<String> _waiverIds = {};

  List<WaiverResponse> _waivers = const [];
  bool _loadingWaivers = true;
  bool _saving = false;

  bool get _isEdit => widget.plan != null;

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadWaivers();
  }

  void _prefill() {
    final plan = widget.plan;
    if (plan == null) return;
    _name.text = plan.planName;
    _type =
        plan.planType == PlanType.unknown ? PlanType.recurring : plan.planType;
    _unlimited = plan.classCount == null;
    if (plan.classCount != null) _classCount.text = '${plan.classCount}';
    if (plan.durationAmount != null) {
      _trialLength.text = '${plan.durationAmount}';
    }
    if (plan.durationUnit != null && plan.durationUnit != DurationUnit.unknown) {
      _trialUnit = plan.durationUnit!;
    }
    final price = plan.activePrice?.price;
    if (price != null) _price.text = (price / 100).toStringAsFixed(2);
    _waiverIds.addAll(plan.waiverIds);
    _linkedEnabled = plan.linkedDiscountEnabled;
    _linkedValues = List.of(plan.linkedDiscountValues);
  }

  Future<void> _loadWaivers() async {
    try {
      final waivers =
          await widget.repository.listWaivers(widget.gymId);
      if (mounted) setState(() => _waivers = waivers);
    } catch (_) {
      // Leave the waiver list empty on failure; the rest still works.
    } finally {
      if (mounted) setState(() => _loadingWaivers = false);
    }
  }

  // Manage / create waivers on the dedicated Waivers tab. This leaves
  // the membership form (per the chosen flow).
  void _goToWaivers() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.membershipsWaivers);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _classCount.dispose();
    _trialLength.dispose();
    super.dispose();
  }

  int? get _priceCents {
    final d = double.tryParse(_price.text.trim());
    return d == null ? null : (d * 100).round();
  }

  // For one-time plans a class count is required; unlimited only
  // applies to recurring/trial.
  int? get _resolvedClassCount {
    if (_type != PlanType.oneTime && _unlimited) return null;
    return int.tryParse(_classCount.text.trim());
  }

  // Recurring is locked to 1 month by the backend; trial uses its
  // length; one-time has no period.
  ({int? amount, DurationUnit? unit}) get _duration {
    switch (_type) {
      case PlanType.recurring:
        return (amount: 1, unit: DurationUnit.month);
      case PlanType.trial:
        return (
          amount: int.tryParse(_trialLength.text.trim()),
          unit: _trialUnit,
        );
      case PlanType.oneTime:
      case PlanType.unknown:
        return (amount: null, unit: null);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _name.text.trim();
    final duration = _duration;
    final waiverIds = _waiverIds.toList();
    // Linked discount is recurring-only.
    final recurringLinked = _type == PlanType.recurring && _linkedEnabled;
    final linkedValues = recurringLinked ? _linkedValues : <LinkedDiscountValue>[];
    if (recurringLinked && linkedValues.isEmpty) {
      _snack('Enter at least one family discount, or turn linked off.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        // Price is edited via the versioned price section, not here —
        // Save only persists the plan metadata.
        await widget.repository.updatePlan(MembershipPlanUpdateRequest(
          planId: widget.plan!.planId,
          gymId: widget.gymId,
          data: MembershipPlanUpdateData(
            planName: name,
            classCount: _resolvedClassCount,
            durationAmount: duration.amount,
            durationUnit: duration.unit,
            waiverIds: waiverIds,
            linkedDiscountEnabled: recurringLinked,
            linkedDiscountValues: linkedValues,
          ),
        ));
      } else {
        final price = _priceCents;
        if (price == null) {
          setState(() => _saving = false);
          return;
        }
        await widget.repository.createPlan(MembershipPlanCreateRequest(
          gymId: widget.gymId,
          planName: name,
          planType: _type,
          classCount: _resolvedClassCount,
          durationAmount: duration.amount,
          durationUnit: duration.unit,
          price: price,
          waiverIds: waiverIds,
          linkedDiscountEnabled: recurringLinked,
          linkedDiscountValues: linkedValues,
        ));
      }
      if (mounted) {
        _snack(
          _isEdit ? 'Membership saved.' : 'Membership created.',
          isError: false,
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString());
      }
    }
  }

  // Leaving the form discards in-progress changes, so confirm first. Shown
  // for both the Back button and a system/Escape back (via PopScope).
  Future<void> _handleBack() async {
    if (_saving) return;
    final leave = await ConfirmationModal.show(
      context: context,
      title: 'Leave without saving?',
      message: 'Your changes here will be lost.',
      confirmLabel: 'Leave',
      confirmColor: DesignConstants.badRed,
      cancelLabel: 'Keep editing',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await widget.repository.deletePlan(widget.plan!.planId, widget.gymId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString());
      }
    }
  }

  void _snack(String message, {bool isError = true}) {
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            _Header(isEdit: _isEdit, onBack: _handleBack),
            CustomTextField(
              controller: _name,
              label: 'Name',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            _membershipTypeField(),
            _priceField(),
            _entitlement(),
            _waiversField(),
            // Linked (family) discount is a recurring-only concept.
            if (_type == PlanType.recurring)
              LinkedDiscountSection(
                enabled: _linkedEnabled,
                onEnabledChanged: (v) => setState(() => _linkedEnabled = v),
                initialValues: _linkedValues,
                onChanged: (v) => _linkedValues = v,
                priceController: _price,
              ),
            _actions(),
          ],
        ),
          ),
        ),
      ),
    ),
    );
  }

  // Membership type is fixed at creation. Create lets you pick it; edit
  // only displays it (changing a plan's type after the fact would break the
  // billing model, so it's locked).
  Widget _membershipTypeField() {
    return _Field(
      label: 'Membership Type',
      child: _isEdit
          ? _TypeDisplay(type: _type)
          : PlanTypeCards(
              selected: _type,
              onSelected: (t) => setState(() => _type = t),
            ),
    );
  }

  // Create: a single price input. Edit: the versioned price list with
  // "add new price" + per-old-price migrate (prices are immutable
  // versions, so an edit mints a new one rather than overwriting).
  Widget _priceField() {
    if (_isEdit) {
      return _Field(
        label: 'Price (\$)',
        child: PlanPriceVersionsSection(
          repository: widget.repository,
          planId: widget.plan!.planId,
          gymId: widget.gymId,
          priceController: _price,
        ),
      );
    }
    return CustomTextField(
      controller: _price,
      label: 'Price (\$)',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      validator: _validatePrice,
    );
  }

  String? _validatePrice(String? v) {
    final d = double.tryParse(v?.trim() ?? '');
    if (d == null) return 'Enter a price';
    if (d < 0) return 'Must be 0 or more';
    return null;
  }

  String? _validatePositiveInt(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n <= 0) ? 'Enter a number above 0' : null;
  }

  Widget _waiversField() {
    return _Field(
      label: 'Waivers',
      child: _loadingWaivers
          ? Text(
              'Loading…',
              style: DesignConstants.p.copyWith(
                color: DesignConstants.text2nd,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  'Members must sign the selected waiver(s) before they can '
                  'sign up.',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
                // No waivers exist yet → offer the way to create them. Once the
                // gym has waivers you just pick from the list (no Manage button).
                if (_waivers.isEmpty)
                  AppOutlineButton(
                    text: 'Manage waivers',
                    onPressed: _goToWaivers,
                    borderRadius: DesignConstants.radiusBig,
                    textStyle: DesignConstants.pSmall,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignConstants.spacingMedium,
                      vertical: DesignConstants.spacingSmall,
                    ),
                    icon: Icon(
                      Icons.arrow_forward,
                      size: DesignConstants.iconSizeSmall,
                      color: DesignConstants.text,
                    ),
                  )
                else
                  WaiverMultiSelect(
                    waivers: _waivers,
                    selectedIds: _waiverIds,
                    onToggle: (id) => setState(() {
                      _waiverIds.contains(id)
                          ? _waiverIds.remove(id)
                          : _waiverIds.add(id);
                    }),
                  ),
              ],
            ),
    );
  }

  Widget _entitlement() {
    return _Field(
      label: 'Entitlement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (_type != PlanType.oneTime)
            IconOptionCards(
              options: const [
                IconOption(
                  icon: Symbols.all_inclusive_sharp,
                  label: 'Unlimited',
                ),
                IconOption(
                  icon: Symbols.confirmation_number_sharp,
                  label: 'Class Pack',
                ),
              ],
              selectedIndex: _unlimited ? 0 : 1,
              onSelected: (i) => setState(() => _unlimited = i == 0),
            ),
          if (_type == PlanType.oneTime || !_unlimited)
            CustomTextField(
              controller: _classCount,
              label: 'Number of classes',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _validatePositiveInt,
            ),
          if (_type == PlanType.recurring)
            Text(
              'Recurring memberships bill the member once a month.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          if (_type == PlanType.trial)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Expanded(
                  child: CustomTextField(
                    controller: _trialLength,
                    label: 'Trial length',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: _validatePositiveInt,
                  ),
                ),
                Expanded(
                  child: AppDropdownField<DurationUnit>(
                    label: 'Unit',
                    value: _trialUnit,
                    items: const [
                      DropdownMenuItem(
                        value: DurationUnit.week,
                        child: Text('Week'),
                      ),
                      DropdownMenuItem(
                        value: DurationUnit.month,
                        child: Text('Month'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _trialUnit = v ?? _trialUnit),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        if (_isEdit)
          AppOutlineButton(
            text: 'Delete',
            onPressed: _saving ? null : _delete,
            borderRadius: DesignConstants.radiusSmall,
            borderColor: DesignConstants.badRed,
            textStyle: DesignConstants.h3.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
        const Spacer(),
        AppPrimaryButton(
          text: _isEdit ? 'Save' : 'Create',
          onPressed: _saving ? null : _save,
          isLoading: _saving,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final bool isEdit;
  final VoidCallback onBack;

  const _Header({required this.isEdit, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        InkWell(
          onTap: onBack,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                Icons.chevron_left,
                size: DesignConstants.iconSizeLarge,
                color: DesignConstants.text2nd,
              ),
              Text(
                'Back',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
        Text(
          isEdit ? 'Membership Details' : 'New Membership',
          style: DesignConstants.big2,
        ),
      ],
    );
  }
}

/// A labeled form section (label above its [child]).
class _Field extends StatelessWidget {
  final String label;
  final Widget child;

  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(label, style: DesignConstants.h2),
        child,
      ],
    );
  }
}

/// Read-only membership-type display for the edit screen — the type is
/// fixed at creation, so it is shown (icon + label + subtitle) with a lock
/// affordance rather than the interactive [PlanTypeCards] selector.
class _TypeDisplay extends StatelessWidget {
  final PlanType type;

  const _TypeDisplay({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, subtitle) = _meta(type);
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        border: Border.all(color: DesignConstants.line),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Row(
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            icon,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingTiny,
              children: [
                Text(type.displayLabel, style: DesignConstants.pBig),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            Symbols.lock_sharp,
            size: DesignConstants.iconSizeSmall,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
          ),
        ],
      ),
    );
  }

  // Mirrors the icon/subtitle copy in PlanTypeCards.
  (IconData, String) _meta(PlanType t) {
    switch (t) {
      case PlanType.recurring:
        return (Symbols.calendar_month_sharp, 'Billed monthly');
      case PlanType.oneTime:
        return (Symbols.attach_money_sharp, 'Single payment');
      case PlanType.trial:
        return (Symbols.card_giftcard_sharp, 'Limited-time');
      case PlanType.unknown:
        return (Symbols.help_sharp, '');
    }
  }
}
