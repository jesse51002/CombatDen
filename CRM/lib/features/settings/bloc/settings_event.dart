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

/// Dismiss the inline error after a failed save was surfaced.
class SettingsErrorCleared extends SettingsEvent {
  const SettingsErrorCleared();
}
