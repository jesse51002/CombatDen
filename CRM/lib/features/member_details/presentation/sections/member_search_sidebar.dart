import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
import 'package:crm/features/member_details/bloc/member_detail_state.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:crm/shared/widgets/app_search_box.dart';

/// Right-side roster to jump between members. Search routes
/// through [MemberSearchChanged] (the bloc filters
/// `allMembers`); tapping a row navigates to that member. On
/// first load the list anchors so the current member sits
/// centered — mirroring the theme-tab picker.
class MemberSearchSidebar extends StatefulWidget {
  /// The id of the member currently being viewed, so it can
  /// be highlighted, skipped on tap, and centered on load.
  final String currentMemberId;
  final ValueChanged<String> onMemberTap;

  const MemberSearchSidebar({
    super.key,
    required this.currentMemberId,
    required this.onMemberTap,
  });

  @override
  State<MemberSearchSidebar> createState() =>
      _MemberSearchSidebarState();
}

class _MemberSearchSidebarState
    extends State<MemberSearchSidebar> {
  final ItemScrollController _itemScroll =
      ItemScrollController();
  bool _didCenter = false;

  /// One-shot: once the roster has loaded and the list is
  /// attached, center it on the current member. Retries as the
  /// roster streams in; never re-centers on search/filter.
  void _centerOnCurrentOnce(List<MemberSummary> members) {
    if (_didCenter) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_didCenter || !mounted || !_itemScroll.isAttached) {
        return;
      }
      final i = members.indexWhere(
        (m) => m.memberId == widget.currentMemberId,
      );
      if (i < 0) return;
      _didCenter = true;
      _itemScroll.jumpTo(index: i, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.quickListWidth,
      color: DesignConstants.surface,
      padding: const EdgeInsets.fromLTRB(
        DesignConstants.paddingSmall,
        DesignConstants.paddingBig,
        DesignConstants.paddingSmall,
        DesignConstants.paddingSmall,
      ),
      child: BlocBuilder<MemberDetailBloc, MemberDetailState>(
        builder: (context, state) {
          final members = state is MemberDetailLoaded
              ? state.filteredMembers
              : const <MemberSummary>[];
          if (members.isNotEmpty) {
            _centerOnCurrentOnce(members);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              AppSearchBox(
                hintText: 'Search members',
                onChanged: (q) => context
                    .read<MemberDetailBloc>()
                    .add(MemberSearchChanged(q)),
              ),
              Expanded(
                child: members.isEmpty
                    ? Center(
                        child: Text(
                          'No members',
                          style: DesignConstants.pSmall
                              .copyWith(
                            color: DesignConstants.text2nd,
                          ),
                        ),
                      )
                    : ScrollablePositionedList.builder(
                        itemScrollController: _itemScroll,
                        itemCount: members.length,
                        itemBuilder: (_, i) {
                          final m = members[i];
                          final isCurrent = m.memberId ==
                              widget.currentMemberId;
                          return _Row(
                            member: m,
                            isCurrent: isCurrent,
                            onTap: isCurrent
                                ? null
                                : () => widget.onMemberTap(
                                      m.memberId,
                                    ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final MemberSummary member;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _Row({
    required this.member,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            _Avatar(member: member),
            Expanded(
              child: Text(
                member.fullName,
                style: isCurrent
                    ? DesignConstants.p.copyWith(
                        color: DesignConstants.primaryColor,
                        fontWeight: FontWeight.w700,
                      )
                    : DesignConstants.p,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Member photo, falling back to the first-name initial.
class _Avatar extends StatelessWidget {
  final MemberSummary member;

  const _Avatar({required this.member});

  @override
  Widget build(BuildContext context) {
    final photo = member.photoUrl;
    return CircleAvatar(
      radius: DesignConstants.iconSizeSmall,
      backgroundColor: DesignConstants.backgroundColor,
      backgroundImage:
          photo != null ? NetworkImage(photo) : null,
      child: photo == null
          ? Text(
              member.firstName.isNotEmpty
                  ? member.firstName[0].toUpperCase()
                  : '?',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text,
              ),
            )
          : null,
    );
  }
}
