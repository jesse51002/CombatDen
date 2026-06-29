import 'package:equatable/equatable.dart';

/// Events for the gym presets Settings section.
sealed class PresetsEvent extends Equatable {
  const PresetsEvent();

  @override
  List<Object?> get props => [];
}

/// Load the template catalog when the section mounts.
class PresetsTemplatesRequested extends PresetsEvent {
  const PresetsTemplatesRequested();
}

/// The admin tapped a template card — record it as the pending selection.
class PresetsTemplateSelected extends PresetsEvent {
  final String videoGymId;

  const PresetsTemplateSelected(this.videoGymId);

  @override
  List<Object?> get props => [videoGymId];
}

/// The admin confirmed "Apply preset" for the currently-selected template.
class PresetsImportRequested extends PresetsEvent {
  const PresetsImportRequested();
}

/// Dismiss an error so the UI can retry.
class PresetsErrorCleared extends PresetsEvent {
  const PresetsErrorCleared();
}
