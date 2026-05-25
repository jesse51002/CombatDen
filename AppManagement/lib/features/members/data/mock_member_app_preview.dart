/// Hardcoded gym-branding data for the Member App configurator screen.
///
/// The screen lets a gym admin configure how their member-facing mobile
/// app looks (theme), what videos surface, and the loyalty program.
/// Theme, video, and loyalty data live in their own `mock_*.dart` files;
/// this file holds only the gym identity shared across all three tabs.
library;

class MemberAppPreviewData {
  final String gymName;
  final String gymLogoAsset;

  const MemberAppPreviewData({
    required this.gymName,
    required this.gymLogoAsset,
  });
}

const MemberAppPreviewData kMockMemberAppPreview = MemberAppPreviewData(
  gymName: 'Apex MMA',
  gymLogoAsset: 'assets/images/apex_mma_logo.png',
);
