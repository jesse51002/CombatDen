import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

typedef MemberPickerItemBuilder = Widget Function(
  BuildContext context,
  MemberRow row,
  bool selected,
  VoidCallback onTap,
);

/// Searchable, paginated list of gym members. Backed by
/// `/api/v1/members/crm_members_list`. Search debounces
/// keystrokes and resets the list; scrolling near the end
/// fetches the next page.
class PaginatedMemberPicker extends StatefulWidget {
  final String gymId;
  final String? selectedCrmUserId;
  final ValueChanged<MemberRow> onSelected;

  /// Fixed height for the list area. Ignored when
  /// [expand] is true.
  final double maxHeight;

  /// When true, the list expands to fill available
  /// vertical space instead of using [maxHeight]. Use
  /// inside a bounded parent like a sidebar.
  final bool expand;

  /// Override the default tile with a custom builder
  /// (e.g., the sidebar uses [MemberListItem]).
  final MemberPickerItemBuilder? itemBuilder;

  const PaginatedMemberPicker({
    super.key,
    required this.gymId,
    required this.onSelected,
    this.selectedCrmUserId,
    this.maxHeight = 320,
    this.expand = false,
    this.itemBuilder,
  });

  @override
  State<PaginatedMemberPicker> createState() =>
      _PaginatedMemberPickerState();
}

class _PaginatedMemberPickerState
    extends State<PaginatedMemberPicker> {
  late final MembersListRepository _repo;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<MemberRow> _rows = [];
  int _startIndex = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasReachedEnd = false;
  String? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _repo = MembersListRepository(apiClient: ApiClient());
    _scroll.addListener(_onScroll);
    _search.addListener(_onSearchTyped);
    _fetchFresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearchTyped() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      _fetchFresh,
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      _fetchNextPage();
    }
  }

  Future<void> _fetchFresh() async {
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await _repo.getMembersList(
        CrmMembersListRequest(
          gymId: widget.gymId,
          prevView: MembersListView.all,
          requestedView: MembersListView.all,
          filters: MembersListFilters(
            name: _search.text.trim().isEmpty
                ? null
                : _search.text.trim(),
          ),
        ),
      );
      if (seq != _requestSeq || !mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(response.data);
        _startIndex = 0;
        _hasReachedEnd = response.data.length <
            AppConstants.defaultPageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (seq != _requestSeq || !mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoading ||
        _isLoadingMore ||
        _hasReachedEnd) {
      return;
    }
    final seq = _requestSeq;
    final nextIndex =
        _startIndex + AppConstants.defaultPageSize;
    setState(() => _isLoadingMore = true);
    try {
      final response = await _repo.getMembersList(
        CrmMembersListRequest(
          gymId: widget.gymId,
          prevView: MembersListView.all,
          requestedView: MembersListView.all,
          startIndex: nextIndex,
          filters: MembersListFilters(
            name: _search.text.trim().isEmpty
                ? null
                : _search.text.trim(),
          ),
        ),
      );
      if (seq != _requestSeq || !mounted) return;
      setState(() {
        _rows.addAll(response.data);
        _startIndex = nextIndex;
        _hasReachedEnd = response.data.length <
            AppConstants.defaultPageSize;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rows;
    final Widget list;
    if (_error != null) {
      list = Text(
        _error!,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.badRed,
        ),
      );
    } else if (_isLoading && _rows.isEmpty) {
      list = const Center(
        child: CircularProgressIndicator(),
      );
    } else if (visible.isEmpty) {
      list = Center(
        child: Text(
          'No members found.',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      );
    } else {
      list = ListView.separated(
        controller: _scroll,
        itemCount: visible.length +
            (_isLoadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(
          height: DesignConstants.spacingSmall,
        ),
        itemBuilder: (_, i) {
          if (i >= visible.length) {
            return const Padding(
              padding: EdgeInsets.all(
                DesignConstants.spacingMedium,
              ),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          final row = visible[i];
          final selected = row.crmUserId ==
              widget.selectedCrmUserId;
          void onTap() => widget.onSelected(row);
          if (widget.itemBuilder != null) {
            return widget.itemBuilder!(
              context,
              row,
              selected,
              onTap,
            );
          }
          return _PickerTile(
            row: row,
            selected: selected,
            onTap: onTap,
          );
        },
      );
    }
    final listSlot = widget.expand
        ? Expanded(child: list)
        : SizedBox(height: widget.maxHeight, child: list);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        CustomTextField(
          controller: _search,
          label: 'Search members',
          hintText: 'Name',
        ),
        listSlot,
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  final MemberRow row;
  final bool selected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor
                  .withValues(alpha: 0.12)
              : DesignConstants.backgroundColor,
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
          ),
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: DesignConstants.card,
              backgroundImage: row.avatarUrl != null
                  ? NetworkImage(row.avatarUrl!)
                  : null,
              child: row.avatarUrl == null
                  ? Icon(
                      Symbols.person_sharp,
                      size: 18,
                      color: DesignConstants.text3rd,
                      weight:
                          DesignConstants.iconWeight,
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                row.name,
                style: DesignConstants.p,
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
