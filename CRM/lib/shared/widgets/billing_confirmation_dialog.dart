import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// One bullet describing an effect of a pending billing
/// action (e.g. "$50 charged to Visa ···· 4242" or
/// "Billing paused for 3 months").
class BillingEffect {
  final IconData icon;
  final String text;
  final Color? iconColor;

  const BillingEffect({
    required this.icon,
    required this.text,
    this.iconColor,
  });
}

/// A member affected by a billing action, shown in the
/// confirmation's affected-people list.
class BillingAffectedPerson {
  final String fullName;
  final String initial;
  final String? photoUrl;

  const BillingAffectedPerson({
    required this.fullName,
    required this.initial,
    this.photoUrl,
  });
}

/// Shared final-step confirmation scaffold for any action
/// that moves money, pauses billing, or changes what a
/// member is charged. One consistent summary across every
/// such dialog: a lead sentence, bulleted effects, an
/// optional affected-people list, an optional warning, and
/// confirm + cancel. Returns `true` iff the user confirmed.
///
/// A reusable billing primitive — the member-detail billing
/// dialogs (a later workflow) call [show] with the effects
/// they computed from a preview.
class BillingConfirmationDialog {
  BillingConfirmationDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String summary,
    required String confirmLabel,
    List<BillingEffect> effects = const [],
    List<BillingAffectedPerson> affected = const [],
    Color? confirmColor,
    String cancelLabel = 'Cancel',
    String? warning,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: title,
        body: _Body(
          summary: summary,
          effects: effects,
          affected: affected,
          warning: warning,
        ),
        actions: AppDialogActions(
          primaryLabel: confirmLabel,
          primaryColor: confirmColor,
          primaryOnPressed: () =>
              Navigator.of(dialogContext).pop(true),
          secondaryLabel: cancelLabel,
          secondaryOnPressed: () =>
              Navigator.of(dialogContext).pop(false),
        ),
      ),
    );
    return result ?? false;
  }
}

class _Body extends StatelessWidget {
  final String summary;
  final List<BillingEffect> effects;
  final List<BillingAffectedPerson> affected;
  final String? warning;

  const _Body({
    required this.summary,
    required this.effects,
    required this.affected,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          summary,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text,
          ),
        ),
        if (effects.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children:
                effects.map((e) => _EffectRow(effect: e)).toList(),
          ),
        if (affected.isNotEmpty) _AffectedList(people: affected),
        if (warning != null) _WarningBanner(message: warning!),
      ],
    );
  }
}

class _EffectRow extends StatelessWidget {
  final BillingEffect effect;

  const _EffectRow({required this.effect});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          effect.icon,
          size: DesignConstants.iconSizeMedium,
          weight: DesignConstants.iconWeight,
          color: effect.iconColor ?? DesignConstants.primaryColor,
        ),
        Expanded(
          child: Text(
            effect.text,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _AffectedList extends StatelessWidget {
  final List<BillingAffectedPerson> people;

  const _AffectedList({required this.people});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          people.length == 1
              ? 'Affects 1 member:'
              : 'Affects ${people.length} members:',
          style: DesignConstants.h3,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingSmall,
          children:
              people.map((p) => _PersonRow(person: p)).toList(),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  final BillingAffectedPerson person;

  const _PersonRow({required this.person});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        CircleAvatar(
          radius: DesignConstants.iconSizeMedium,
          backgroundColor: DesignConstants.backgroundColor,
          backgroundImage: person.photoUrl != null
              ? NetworkImage(person.photoUrl!)
              : null,
          child: person.photoUrl == null
              ? Text(
                  person.initial,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text,
                  ),
                )
              : null,
        ),
        Flexible(
          child: Text(
            person.fullName,
            style: DesignConstants.p,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;

  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(
        DesignConstants.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.okYellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
        border: Border.all(
          color: DesignConstants.okYellow,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Symbols.warning_sharp,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.okYellow,
          ),
          Expanded(
            child: Text(
              message,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
