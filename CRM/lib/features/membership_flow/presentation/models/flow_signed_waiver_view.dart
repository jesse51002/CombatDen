import 'package:equatable/equatable.dart';

/// One document signed during this purchase, as the review renders it back.
///
/// It is the receipt for the thing that has no receipt: somebody who typed
/// their name into a legal document two screens ago sees it acknowledged
/// before handing over a card. The SIGNER is carried separately from the
/// document because they are often not the member it binds — a parent signs
/// for a child.
class FlowSignedWaiverView extends Equatable {
  /// The document's own name.
  final String name;

  /// The legal name typed on it.
  final String signerName;

  const FlowSignedWaiverView({
    required this.name,
    required this.signerName,
  });

  @override
  List<Object?> get props => [name, signerName];
}
