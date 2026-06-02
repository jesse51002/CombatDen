import 'package:flutter/material.dart';

import 'package:theme_flutter/showcase/home/class_list_item.dart';
import 'package:theme_flutter/showcase/home/home_class.dart';
import 'package:theme_flutter/showcase/showcase_tokens.dart';

/// Clone of MobileApp's `DayClassGroup`: a day label over its class rows.
class DayClassGroup extends StatelessWidget {
  const DayClassGroup({
    super.key,
    required this.day,
    this.showBookings = true,
  });

  final ShowcaseDay day;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ShowcaseTokens.spacingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: ShowcaseTokens.spacingLarge,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ShowcaseTokens.screenHorizontalPadding,
            ),
            child: Text(
              day.label.toUpperCase(),
              style: ShowcaseTokens.h2Bold,
            ),
          ),
          ...day.classes.map(
            (c) => ClassListItem(classData: c, showBookings: showBookings),
          ),
        ],
      ),
    );
  }
}
