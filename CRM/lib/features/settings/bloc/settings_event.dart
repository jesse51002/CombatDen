import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Events for the settings screen.
sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

/// The user picked a theme mode in the appearance control. Applies it
/// optimistically and persists it to the caller's `gym_employees` row.
class SettingsThemeModeChanged extends SettingsEvent {
  final ThemeMode mode;

  const SettingsThemeModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

/// The user confirmed a gym timezone change. NOT optimistic (unlike the
/// theme): the repo saves first; only on success does `selectedGym` update.
class SettingsTimezoneChanged extends SettingsEvent {
  final String timezone;

  const SettingsTimezoneChanged(this.timezone);

  @override
  List<Object?> get props => [timezone];
}

/// The user saved the Gym profile (name + logo). NOT optimistic: the repo
/// saves first; only on success does `selectedGym` update and the saved count
/// bump. [logoUrl] carries the current logo (null = none / cleared) so the
/// single PUT keeps patch semantics when only the name changed.
class GymProfileSaveRequested extends SettingsEvent {
  final String gymName;
  final String? logoUrl;

  const GymProfileSaveRequested({required this.gymName, required this.logoUrl});

  @override
  List<Object?> get props => [gymName, logoUrl];
}

/// Dismiss the inline error after a failed save was surfaced.
class SettingsErrorCleared extends SettingsEvent {
  const SettingsErrorCleared();
}
