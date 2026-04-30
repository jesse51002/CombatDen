import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Column titles row above the members table. Each title sits over its
/// own column and is underlined by a hairline rule that runs the width
/// of that column only.
class MembersTableHeader extends StatelessWidget {
  const MembersTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(child: _HeaderCell(label: 'Name')),
        Expanded(child: _HeaderCell(label: 'Contact')),
        Expanded(child: _HeaderCell(label: 'Rank')),
        Expanded(child: _HeaderCell(label: 'Last Class')),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DesignConstants.h2),
        Container(
          height: DesignConstants.spacingTiny,
          color: DesignConstants.text2nd,
        ),
      ],
    );
  }
}
