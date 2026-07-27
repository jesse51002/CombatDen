import 'package:equatable/equatable.dart';

/// The (empty) state of [VideoClickBloc].
///
/// The click reporter is a pure sink — nothing on screen reads it and it never
/// emits — so its state carries no fields. It exists because a `Bloc` needs
/// one, and keeping the reporter a bloc is what keeps the layering honest:
/// widget → bloc → repository → ApiClient, never a widget reaching the network.
class VideoClickBlocState extends Equatable {
  const VideoClickBlocState();

  @override
  List<Object?> get props => const [];
}
