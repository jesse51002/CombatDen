import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_card.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/theme_tab/theme_search_bar.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/section_card.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:app_management/features/members/data/gyms_pager.dart';

// Web admin: bigger viewport than the phone picker, so 50 per page keeps
// the side scroll snug and gives the scroll-to-active code a single
// pre-loaded list to seek through.
const int _kWebPageSize = 50;
// Each compact theme card + separator. Used to map item index → scroll
// offset for the scroll-to-active animation. Keep in sync with
// `theme_card.dart` if its padding/thumb-height changes.
const double _kRowStride = 72;
const Duration _kScrollDuration = Duration(milliseconds: 350);

/// Side-pane theme picker shown next to the phone-frame preview.
///
/// Eager-loads every page so the search + scroll-to-active never miss
/// an item, then listens to [ThemeRuntime.changes] and scrolls
/// the list so the active card is on-screen after the library pick.
class ThemeGrid extends StatefulWidget {
  const ThemeGrid({super.key, required this.onBackToLibrary});

  final VoidCallback onBackToLibrary;

  @override
  State<ThemeGrid> createState() => _ThemeGridState();
}

class _ThemeGridState extends State<ThemeGrid> {
  final GymsPager _pager = GymsPager(pageSize: _kWebPageSize);
  final ScrollController _scroll = ScrollController();
  String? _lastScrolledTo;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_pullUntilDone);
    ThemeRuntime.changes.addListener(_onActiveChanged);
    // First paint: scroll to whatever's already active.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onActiveChanged());
  }

  void _pullUntilDone() {
    if (!mounted) return;
    if (!_pager.isLoading && _pager.hasMore) {
      _pager.loadMore();
    } else if (!_pager.hasMore) {
      // List is fully loaded — make sure the active card is visible.
      _onActiveChanged();
    }
  }

  void _onActiveChanged() {
    if (!mounted || !_scroll.hasClients) return;
    final active = ThemeRuntime.activeDesignId;
    if (active == null || active == _lastScrolledTo) return;
    final i = _pager.items.indexWhere((s) => s.id == active);
    if (i < 0) return; // not loaded yet — will retry on next page tick.
    _lastScrolledTo = active;
    final target = (i * _kRowStride).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: _kScrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    ThemeRuntime.changes.removeListener(_onActiveChanged);
    _pager.removeListener(_pullUntilDone);
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('App Theme', style: DesignConstants.h2),
        ThemeSearchBar(onChanged: _pager.setQuery),
        AppOutlineButton(
          text: '← Back to library',
          fullWidth: true,
          onPressed: widget.onBackToLibrary,
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _pager,
            builder: (context, _) =>
                _ThemeListView(pager: _pager, scroll: _scroll),
          ),
        ),
      ],
    );
  }
}

/// The scrollable theme list itself, plus its loading / empty / error
/// states. Wraps in `ListenableBuilder(ThemeRuntime.changes)`
/// so the active-card border flips when the live theme switches.
class _ThemeListView extends StatelessWidget {
  const _ThemeListView({required this.pager, required this.scroll});

  final GymsPager pager;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (!pager.hasLoadedFirstPage && pager.isLoading) {
      return const _CatalogMessage.loading();
    }
    if (pager.items.isEmpty) {
      if (pager.errored) {
        return const _CatalogMessage(
          'Could not reach the customization service. Start it and '
          'reopen this tab to load the themes.',
        );
      }
      return _CatalogMessage(
        pager.query.isEmpty
            ? 'No themes generated yet.'
            : 'No themes match "${pager.query}".',
      );
    }
    return ListenableBuilder(
      listenable: ThemeRuntime.changes,
      builder: (context, _) {
        final active = ThemeRuntime.activeDesignId;
        return ListView.separated(
          controller: scroll,
          itemCount: pager.items.length,
          // ListView.separated has no `spacing:`; the separator builder
          // is the only way to gap its items, so SizedBox here is
          // intentional, not a spacing-rule violation.
          separatorBuilder: (_, _) => const SizedBox(
            height: DesignConstants.spacingMedium,
          ),
          itemBuilder: (context, i) {
            final style = pager.items[i];
            return ThemeCard(style: style, isActive: style.id == active);
          },
        );
      },
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  final String? message;

  const _CatalogMessage(this.message);
  const _CatalogMessage.loading() : message = null;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(
        child: message == null
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignConstants.primaryColor,
                ),
              )
            : Text(
                message!,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
