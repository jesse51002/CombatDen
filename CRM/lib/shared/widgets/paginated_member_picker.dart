import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';

/// One row in a [PaginatedMemberPicker].
///
/// A plain display shape (id + name + optional avatar) so
/// the picker never depends on a members-list model — the
/// member-detail dialogs (a later workflow) map their own
/// row model onto this and supply a [MemberPageFetcher].
class MemberPickerEntry {
  /// Stable id used for selection (e.g. the CRM user id).
  final String id;
  final String name;
  final String? avatarUrl;

  const MemberPickerEntry({
    required this.id,
    required this.name,
    this.avatarUrl,
  });
}

/// Fetches one page of members. [query] is the trimmed
/// search text (empty for "all"); [startIndex] is the
/// zero-based offset of the page to load. Returns the rows
/// for that page; an empty/short page signals the end.
typedef MemberPageFetcher = Future<List<MemberPickerEntry>>
    Function(String query, int startIndex);

typedef MemberPickerItemBuilder = Widget Function(
  BuildContext context,
  MemberPickerEntry entry,
  bool selected,
  VoidCallback onTap,
);

/// Searchable, paginated list of gym members — the shared
/// scaffold behind any "pick a member" surface. Search
/// debounces keystrokes and resets the list; scrolling near
/// the end fetches the next page. The data source is
/// injected via [fetchPage], so this widget stays free of
/// any backend coupling and is reusable across features.
class PaginatedMemberPicker extends StatefulWidget {
  /// Loads a page of members for the current query.
  final MemberPageFetcher fetchPage;

  /// Page size — the picker treats a page shorter than this
  /// as the last page.
  final int pageSize;

  final String? selectedId;
  final ValueChanged<MemberPickerEntry> onSelected;

  /// Fixed height for the list area. Ignored when [expand].
  final double maxHeight;

  /// When true the list expands to fill available vertical
  /// space instead of using [maxHeight]. Use inside a
  /// bounded parent (e.g. a sidebar).
  final bool expand;

  /// Override the default tile with a custom row builder.
  final MemberPickerItemBuilder? itemBuilder;

  final String searchLabel;
  final String searchHint;
  final String emptyLabel;

  const PaginatedMemberPicker({
    super.key,
    required this.fetchPage,
    required this.onSelected,
    this.pageSize = 20,
    this.selectedId,
    this.maxHeight = 320,
    this.expand = false,
    this.itemBuilder,
    this.searchLabel = 'Search members',
    this.searchHint = 'Name',
    this.emptyLabel = 'No members found.',
  });

  @override
  State<PaginatedMemberPicker> createState() =>
      _PaginatedMemberPickerState();
}

class _PaginatedMemberPickerState
    extends State<PaginatedMemberPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<MemberPickerEntry> _rows = [];
  int _startIndex = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasReachedEnd = false;
  String? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
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

  String get _query => _search.text.trim();

  Future<void> _fetchFresh() async {
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await widget.fetchPage(_query, 0);
      if (seq != _requestSeq || !mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(page);
        _startIndex = 0;
        _hasReachedEnd = page.length < widget.pageSize;
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
    if (_isLoading || _isLoadingMore || _hasReachedEnd) {
      return;
    }
    final seq = _requestSeq;
    final nextIndex = _startIndex + widget.pageSize;
    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.fetchPage(_query, nextIndex);
      if (seq != _requestSeq || !mounted) return;
      setState(() {
        _rows.addAll(page);
        _startIndex = nextIndex;
        _hasReachedEnd = page.length < widget.pageSize;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _buildList();
    final listSlot = widget.expand
        ? Expanded(child: list)
        : SizedBox(height: widget.maxHeight, child: list);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        CustomTextField(
          controller: _search,
          label: widget.searchLabel,
          hintText: widget.searchHint,
        ),
        listSlot,
      ],
    );
  }

  Widget _buildList() {
    if (_error != null) {
      return Text(
        _error!,
        style: DesignConstants.pSmall.copyWith(
          color: DesignConstants.badRed,
        ),
      );
    }
    if (_isLoading && _rows.isEmpty) {
      return const Center(child: AppSpinner());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          widget.emptyLabel,
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      itemCount: _rows.length + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(
        height: DesignConstants.spacingSmall,
      ),
      itemBuilder: (context, i) {
        if (i >= _rows.length) {
          return const Padding(
            padding: EdgeInsets.all(
              DesignConstants.spacingMedium,
            ),
            child: Center(child: AppSpinner()),
          );
        }
        final row = _rows[i];
        final selected = row.id == widget.selectedId;
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
          entry: row,
          selected: selected,
          onTap: onTap,
        );
      },
    );
  }
}

class _PickerTile extends StatelessWidget {
  final MemberPickerEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.entry,
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
              ? DesignConstants.primaryColor10
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
              radius: DesignConstants.iconSizeMedium,
              backgroundColor: DesignConstants.card,
              backgroundImage: entry.avatarUrl != null
                  ? NetworkImage(entry.avatarUrl!)
                  : null,
              child: entry.avatarUrl == null
                  ? Icon(
                      Symbols.person_sharp,
                      size: DesignConstants.iconSizeSmall,
                      color: DesignConstants.text3rd,
                      weight: DesignConstants.iconWeight,
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                entry.name,
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
