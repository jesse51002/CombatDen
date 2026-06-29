import 'package:equatable/equatable.dart';

import 'package:crm/features/presets/data/models/preset_models.dart';

/// Loading state of the template catalog.
enum PresetsCatalogStatus { initial, loading, loaded, error }

/// Import operation state.
enum PresetsImportStatus { idle, importing, success, error }

/// State for the gym presets Settings section.
class PresetsState extends Equatable {
  /// Template catalog load status.
  final PresetsCatalogStatus catalogStatus;

  /// The loaded templates (empty until [catalogStatus] is [loaded]).
  final List<TemplateCard> templates;

  /// The video_gym_id the admin has selected in the picker (null = nothing
  /// chosen yet).
  final String? selectedVideoGymId;

  /// Import operation status.
  final PresetsImportStatus importStatus;

  /// Set after a successful import.
  final PresetImportResult? importResult;

  /// Error message (catalog load or import).
  final String? error;

  const PresetsState({
    this.catalogStatus = PresetsCatalogStatus.initial,
    this.templates = const [],
    this.selectedVideoGymId,
    this.importStatus = PresetsImportStatus.idle,
    this.importResult,
    this.error,
  });

  PresetsState copyWith({
    PresetsCatalogStatus? catalogStatus,
    List<TemplateCard>? templates,
    String? selectedVideoGymId,
    bool clearSelectedVideoGymId = false,
    PresetsImportStatus? importStatus,
    PresetImportResult? importResult,
    bool clearImportResult = false,
    String? error,
    bool clearError = false,
  }) => PresetsState(
    catalogStatus: catalogStatus ?? this.catalogStatus,
    templates: templates ?? this.templates,
    selectedVideoGymId: clearSelectedVideoGymId
        ? null
        : selectedVideoGymId ?? this.selectedVideoGymId,
    importStatus: importStatus ?? this.importStatus,
    importResult: clearImportResult
        ? null
        : importResult ?? this.importResult,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [
    catalogStatus,
    templates,
    selectedVideoGymId,
    importStatus,
    importResult,
    error,
  ];
}
