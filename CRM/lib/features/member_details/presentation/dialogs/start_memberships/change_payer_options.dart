import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/data/models/linked_account.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/change_payer_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_option_row.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';

/// Every way of answering "who pays", in four named groups.
///
/// The groups are the point. The launch member (self-pay) and their authorized
/// payers ANSWER the question on the spot; everybody else on the run's roster
/// answers it at the price of one signature; and the two adders reach somebody
/// on neither list. Naming each group is what stops the third looking like the
/// second — the founder's own report was that a person already on screen could
/// only be reached through a search for a name he was looking at.
///
/// Nobody appears twice: [inRun] is the roster minus the launch member and
/// minus everybody already in [authorized] (see
/// `MembershipWizardDerived.unauthorizedRosterPayers`).
class ChangePayerOptions extends StatelessWidget {
  /// The member whose page opened the run — always a valid payer, and the
  /// person every authorization here is written FOR.
  final String launchMemberId;
  final String launchMemberName;

  /// The launch member's authorized payers — selectable with no signature.
  final List<LinkedAccount> authorized;

  /// Roster rows who would have to be authorized first.
  final List<MembershipWizardPerson> inRun;

  final String selected;
  final ValueChanged<String> onSelect;

  /// Authorize a roster member, then select them.
  final ValueChanged<MembershipWizardPerson> onAuthorize;

  final VoidCallback onCreate;
  final VoidCallback onLink;

  const ChangePayerOptions({
    super.key,
    required this.launchMemberId,
    required this.launchMemberName,
    required this.authorized,
    required this.inRun,
    required this.selected,
    required this.onSelect,
    required this.onAuthorize,
    required this.onCreate,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        FlowDetailGroup(
          eyebrow: ChangePayerCopy.selfEyebrow,
          children: [
            WizardOptionRow(
              icon: Symbols.person_sharp,
              title: launchMemberName,
              meta: ChangePayerCopy.selfMeta,
              selected: selected == launchMemberId,
              onTap: () => onSelect(launchMemberId),
            ),
          ],
        ),
        if (authorized.isNotEmpty)
          FlowDetailGroup(
            eyebrow: ChangePayerCopy.authorizedEyebrow,
            children: [
              _OptionList(
                children: [
                  for (final account in authorized)
                    WizardOptionRow(
                      icon: Symbols.account_balance_wallet_sharp,
                      title: account.fullName,
                      meta: ChangePayerCopy.authorizedMeta,
                      selected: selected == account.memberId,
                      onTap: () => onSelect(account.memberId),
                    ),
                ],
              ),
            ],
          ),
        if (inRun.isNotEmpty)
          FlowDetailGroup(
            eyebrow: ChangePayerCopy.inRunEyebrow,
            children: [
              _OptionList(
                children: [
                  for (final person in inRun)
                    WizardOptionRow(
                      icon: Symbols.groups_sharp,
                      title: person.name,
                      meta: ChangePayerCopy.inRunMeta(launchMemberName),
                      // It opens the agreement rather than answering the
                      // question, so it wears the chevron, not the tick.
                      opensMore: true,
                      onTap: () => onAuthorize(person),
                    ),
                ],
              ),
            ],
          ),
        FlowDetailGroup(
          eyebrow: ChangePayerCopy.addEyebrow,
          children: [
            _OptionList(
              children: [
                WizardOptionRow(
                  icon: Symbols.person_add_sharp,
                  title: ChangePayerCopy.createTitle,
                  meta: ChangePayerCopy.createBody,
                  opensMore: true,
                  onTap: onCreate,
                ),
                WizardOptionRow(
                  icon: Symbols.search_sharp,
                  title: ChangePayerCopy.linkTitle,
                  meta: ChangePayerCopy.linkBody,
                  opensMore: true,
                  onTap: onLink,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Rows within ONE group, tighter than the gap between groups.
class _OptionList extends StatelessWidget {
  final List<Widget> children;

  const _OptionList({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: children,
    );
  }
}
