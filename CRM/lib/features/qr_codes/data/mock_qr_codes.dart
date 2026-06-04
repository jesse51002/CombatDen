/// Hardcoded QR codes for the prototype QR Codes screen.
///
/// Each entry maps a short admin-facing label to the asset that the gym
/// would print/display. When the app graduates to real data, these become
/// rows fetched from the backend (likely keyed by gym + purpose) and the
/// `imageAsset` becomes a generated/served URL.
class QrCode {
  final String id;
  final String title;
  final String description;
  final String imageAsset;

  const QrCode({
    required this.id,
    required this.title,
    required this.description,
    required this.imageAsset,
  });
}

const List<QrCode> kMockQrCodes = <QrCode>[
  QrCode(
    id: 'sign_up',
    title: 'Sign Up QR Code',
    description: 'New members scan to start the sign-up flow.',
    imageAsset: 'assets/images/qr_code_sign_up.png',
  ),
  QrCode(
    id: 'check_in',
    title: 'Check In QR Code',
    description: 'Existing members scan to check in for class.',
    imageAsset: 'assets/images/qr_code_sign_up.png',
  ),
];
