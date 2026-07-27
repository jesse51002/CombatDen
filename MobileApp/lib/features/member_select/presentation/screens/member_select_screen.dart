import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';
import 'package:mobile_app/features/member_select/presentation/widgets/member_row.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/text/app_headline.dart';

/// The "Who's training?" picker — one row per member the caller's email
/// resolves to. A pure presentation screen: the caller supplies the [members]
/// and the [onSelected] / [onUseDifferentEmail] callbacks (auto-skip for a
/// single member happens in the gate, never here).
class MemberSelectScreen extends StatelessWidget {
  const MemberSelectScreen({
    super.key,
    required this.members,
    required this.onSelected,
    required this.onUseDifferentEmail,
  });

  final List<MemberIdentity> members;
  final ValueChanged<MemberIdentity> onSelected;
  final VoidCallback onUseDifferentEmail;

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: DesignConstants.paddingBig),
            child: AppHeadline(
              title: "Who's training?",
              subtitle: 'Choose your membership to continue',
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(
                height: DesignConstants.spacingMedium,
              ),
              itemBuilder: (context, i) {
                final member = members[i];
                return MemberRow(
                  member: member,
                  onTap: () => onSelected(member),
                );
              },
            ),
          ),
          _DifferentEmailLink(onTap: onUseDifferentEmail),
        ],
      ),
    );
  }
}

/// "Not you? Use a different email" — signs out so a different account can be
/// used.
class _DifferentEmailLink extends StatelessWidget {
  const _DifferentEmailLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: DesignConstants.paddingSmall),
        child: Text(
          'Not you? Use a different email',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
