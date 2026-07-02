import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/member_class_history.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/error_message.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';
import 'package:crm/shared/widgets/section_card.dart';

const int _kPageSize = 20;

/// Account-level class history in its own card, side by side with
/// [PaymentHistorySection]. Fetched on demand — read-only side read with
/// its own state, like the Waivers / Invoices / Payment History sections.
/// Two labelled blocks: **Upcoming** (the member's open reservations,
/// soonest first, always complete) and **History** (attended + no-show
/// occurrences, newest first, paginated — "Show more" loads the next
/// page). Reloads from page 1 whenever [refreshKey] changes.
class ClassHistorySection extends StatefulWidget {
  final String memberId;
  final String gymId;

  /// Bumped by the bloc on every member mutation (the member-detail
  /// `refreshToken`). A change reloads the card from page 1.
  final int refreshKey;

  const ClassHistorySection({
    super.key,
    required this.memberId,
    required this.gymId,
    required this.refreshKey,
  });

  @override
  State<ClassHistorySection> createState() =>
      _ClassHistorySectionState();
}

class _ClassHistorySectionState extends State<ClassHistorySection> {
  late final ScheduleRepository _repo;
  List<MemberClassHistoryRow> _upcoming = [];
  final List<MemberClassHistoryRow> _history = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;

  /// Bumped on every [_reload] so an in-flight page fetch from a
  /// superseded load discards its result instead of appending stale
  /// rows onto the freshly-reset list.
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _repo = ScheduleRepository(apiClient: ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant ClassHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      _reload();
    }
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    final gen = _loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.getMemberClassHistory(
        widget.memberId,
        widget.gymId,
        limit: _kPageSize,
        offset: _offset,
      );
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _upcoming = page.upcoming;
        _history.addAll(page.history);
        _offset += page.history.length;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Re-fetches page 1 in the BACKGROUND and swaps it in, WITHOUT
  /// clearing the visible lists first — mirrors
  /// `PaymentHistorySectionState._reload` so a refresh doesn't flash the
  /// card to a spinner/empty state. Bumping [_loadGen] orphans any
  /// in-flight [_load] (e.g. a "Show more") so it can't append onto the
  /// swapped page.
  Future<void> _reload() async {
    final gen = ++_loadGen;
    if (_error != null) setState(() => _error = null);
    try {
      final page = await _repo.getMemberClassHistory(
        widget.memberId,
        widget.gymId,
        limit: _kPageSize,
        offset: 0,
      );
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _upcoming = page.upcoming;
        _history
          ..clear()
          ..addAll(page.history);
        _offset = page.history.length;
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Class history', style: DesignConstants.h2),
          _content(context),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_upcoming.isEmpty && _history.isEmpty) {
      if (_loading) {
        return const Center(child: AppSpinner());
      }
      if (_error != null) {
        return ErrorMessage(message: _error!);
      }
      return const _Empty();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        if (_upcoming.isNotEmpty)
          _Block(
            title: 'Upcoming',
            rows: _upcoming.map(_row).toList(),
          ),
        if (_history.isNotEmpty)
          _Block(
            title: 'History',
            rows: _history.map(_row).toList(),
          ),
        if (_loading)
          const Center(child: AppSpinner())
        else if (_hasMore)
          AppOutlineButton(
            fullWidth: true,
            text: 'Show more',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: _load,
          ),
      ],
    );
  }

  AppDataTableRow _row(MemberClassHistoryRow row) {
    return AppDataTableRow(
      cells: [
        Text(
          row.className,
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          classDateTimeLabel(row.originalDate, row.originalTime),
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: InvoiceChip(
            label: row.status.displayLabel,
            tone: _toneFor(row.status),
          ),
        ),
      ],
    );
  }

  InvoiceChipTone _toneFor(MemberClassHistoryStatus status) {
    switch (status) {
      case MemberClassHistoryStatus.attended:
        return InvoiceChipTone.good;
      case MemberClassHistoryStatus.noShow:
        return InvoiceChipTone.bad;
      case MemberClassHistoryStatus.reserved:
        return InvoiceChipTone.brand;
      case MemberClassHistoryStatus.unknown:
        return InvoiceChipTone.neutral;
    }
  }
}

/// One labelled block ("Upcoming" / "History") inside the card: a small
/// muted heading over its own [AppDataTable].
class _Block extends StatelessWidget {
  final String title;
  final List<AppDataTableRow> rows;

  const _Block({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          title,
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        AppDataTable(
          shrinkWrap: true,
          showBackground: true,
          columns: const [
            AppDataTableColumn(label: 'Class', fill: true),
            AppDataTableColumn(label: 'When', minWidth: 150),
            AppDataTableColumn(label: 'Status', minWidth: 90),
          ],
          rows: rows,
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        DesignConstants.paddingBig,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Center(
        child: Text(
          'No class history yet',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
