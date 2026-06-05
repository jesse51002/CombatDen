import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/member_details/data/models/duration_unit.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/memberships/data/models/membership_plan_create_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_price_request.dart';
import 'package:crm/features/memberships/data/models/membership_plan_update_request.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/presentation/widgets/linked_discount_section.dart';
import 'package:crm/features/memberships/presentation/widgets/plan_type_cards.dart';
import 'package:crm/features/memberships/presentation/widgets/waiver_multi_select.dart';
import 'package:crm/features/memberships/presentation/widgets/icon_option_cards.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
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
  final _tiers = List.generate(4, (_) => TextEditingController());
  final _formKey = GlobalKey<FormState>();

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
    for (var i = 0;
        i < plan.linkedDiscountPrices.length && i < _tiers.length;
        i++) {
      _tiers[i].text = (plan.linkedDiscountPrices[i] / 100).toStringAsFixed(2);
    }
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
    for (final c in _tiers) {
      c.dispose();
    }
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

  List<int> get _tierCents => [
        for (final c in _tiers)
          ((double.tryParse(c.text.trim()) ?? 0) * 100).round(),
      ];

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
    final price = _priceCents;
    if (price == null) return;
    final duration = _duration;
    final waiverIds = _waiverIds.toList();
    // Linked discount is recurring-only.
    final recurringLinked = _type == PlanType.recurring && _linkedEnabled;
    final tiers = recurringLinked ? _tierCents : <int>[];

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.repository.updatePlan(MembershipPlanUpdateRequest(
          planId: widget.plan!.planId,
          gymId: widget.gymId,
          data: MembershipPlanUpdateData(
            planName: name,
            planType: _type,
            classCount: _resolvedClassCount,
            durationAmount: duration.amount,
            durationUnit: duration.unit,
            waiverIds: waiverIds,
            linkedDiscountEnabled: recurringLinked,
            linkedDiscountPrices: tiers,
          ),
        ));
        if (price != widget.plan!.activePrice?.price) {
          await widget.repository.setPlanPrice(MembershipPlanPriceRequest(
            planId: widget.plan!.planId,
            gymId: widget.gymId,
            price: price,
          ));
        }
      } else {
        await widget.repository.createPlan(MembershipPlanCreateRequest(
          gymId: widget.gymId,
          planName: name,
          planType: _type,
          classCount: _resolvedClassCount,
          durationAmount: duration.amount,
          durationUnit: duration.unit,
          price: price,
          waiverIds: waiverIds,
          linkedDiscountEnabled: _linkedEnabled,
          linkedDiscountPrices: tiers,
        ));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString());
      }
    }
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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: DesignConstants.p.copyWith(color: DesignConstants.surface),
        ),
        backgroundColor: DesignConstants.badRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
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
            _Header(isEdit: _isEdit),
            CustomTextField(
              controller: _name,
              label: 'Name',
              hintText: 'Unlimited Class Membership',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            _Field(
              label: 'Membership Type',
              child: PlanTypeCards(
                selected: _type,
                onSelected: (t) => setState(() => _type = t),
              ),
            ),
            CustomTextField(
              controller: _price,
              label: 'Price (\$)',
              hintText: '165',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              validator: _validatePrice,
            ),
            _entitlement(),
            _waiversField(),
            // Linked (family) discount is a recurring-only concept.
            if (_type == PlanType.recurring)
              LinkedDiscountSection(
                enabled: _linkedEnabled,
                onEnabledChanged: (v) => setState(() => _linkedEnabled = v),
                priceController: _price,
                tierControllers: _tiers,
              ),
            _actions(),
          ],
        ),
          ),
        ),
      ),
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
                WaiverMultiSelect(
                  waivers: _waivers,
                  selectedIds: _waiverIds,
                  onToggle: (id) => setState(() {
                    _waiverIds.contains(id)
                        ? _waiverIds.remove(id)
                        : _waiverIds.add(id);
                  }),
                ),
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

  const _Header({required this.isEdit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).pop(),
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
