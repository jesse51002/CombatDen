import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/scanner/scan_frame_overlay.dart';
import 'package:mobile_app/features/qr_checkin/presentation/widgets/scanner/scanner_permission_view.dart';
import 'package:mobile_app/shared/widgets/buttons/app_close_button.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Step 1 of the QR check-in flow: a live camera scanner.
///
/// Per the ruled flow the payload is NOT parsed — ANY decoded barcode is
/// treated as a valid check-in code ("assume it works"). On the first
/// detection the flow advances to the pick-class step; the kiosk Phase G nonce
/// contract will replace the "any decode succeeds" behavior later.
class CheckinScannerScreen extends StatefulWidget {
  const CheckinScannerScreen({super.key});

  @override
  State<CheckinScannerScreen> createState() => _CheckinScannerScreenState();
}

class _CheckinScannerScreenState extends State<CheckinScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();

  /// One-shot guard: barcode streams fire repeatedly, but we advance exactly
  /// once (a second detection during the transition must be a no-op).
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    _handled = true;
    // Payload intentionally ignored — see the class doc.
    Navigator.of(context).pushReplacementNamed(AppRoutes.checkinPickClass);
  }

  void _retry() => unawaited(_controller.start());

  Widget _buildError(BuildContext context, MobileScannerException error) {
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ScannerPermissionView(
      title: denied ? 'Camera access needed' : 'Camera unavailable',
      message: denied
          ? 'Enable camera access in Settings, then try again to scan the '
              "gym's check-in code."
          : "We couldn't start the camera. Try again.",
      onRetry: _retry,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      child: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: _buildError,
              overlayBuilder: (context, _) => const ScanFrameOverlay(),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.all(DesignConstants.spacingSmall),
              // A scrim keeps the close affordance legible over a bright frame.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DesignConstants.backgroundColor.withValues(
                    alpha: 0.55,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const AppCloseButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
