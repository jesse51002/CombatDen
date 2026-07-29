import 'package:flutter/material.dart';
import 'package:mobile_app/features/class_booking/data/class_info.dart';
import 'package:mobile_app/features/class_booking/data/class_repository.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_body.dart';
import 'package:mobile_app/features/home/presentation/layouts/home_layout_data.dart';

/// One page of home: loads the gym's classes and hands them to whichever
/// arrangement the tenant's `home_format` selects.
///
/// [booked] is the state split between home's two pages, not a layout
/// choice — the booked page carries the upcoming-sessions card, the
/// schedule title, and the per-class booked marks. One body for both
/// because the two differed by that flag alone, and every layout format
/// would otherwise have to be authored twice.
class HomeBody extends StatefulWidget {
  const HomeBody({super.key, required this.booked});

  final bool booked;

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody>
    with AutomaticKeepAliveClientMixin {
  List<ClassInfo>? _classes;
  bool _classesError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ClassRepository.instance.classes().then(
      (c) {
        if (mounted) setState(() => _classes = c);
      },
      onError: (_) {
        if (mounted) setState(() => _classesError = true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return HomeLayoutBody(
      data: HomeLayoutData(
        classes: _classes,
        hasError: _classesError,
        booked: widget.booked,
      ),
    );
  }
}
