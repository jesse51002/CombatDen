import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'date_range_filter.g.dart';

/// Filter by date range (membership start date).
@JsonSerializable(
  fieldRename: FieldRename.snake,
)
class DateRangeFilter extends Equatable {
  final String? startDate;
  final String? endDate;

  const DateRangeFilter({
    this.startDate,
    this.endDate,
  });

  factory DateRangeFilter.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$DateRangeFilterFromJson(json);

  Map<String, dynamic> toJson() =>
      _$DateRangeFilterToJson(this);

  @override
  List<Object?> get props => [startDate, endDate];
}
