# Specific Member Detail — Implementation Specification (v2)

## SCREEN: Specific Member Detail

**DEVICE CONTEXT:** Desktop/Web application (primary), responsive to iPad (stacks two-column layout). Landscape orientation on desktop, portrait on tablet.

---

## WIDGET TREE

```
└── Scaffold (dark theme)
    ├── Left Sidebar (fixed, vertical navigation, collapsible to 50% opacity)
    │   ├── Logo ("COMBAT DEN")
    │   ├── NavItem: "Add New Member" (icon: person_add, highlighted orange)
    │   ├── NavItem: "Dashboard" (icon: calendar_today)
    │   ├── NavItem: "Members" (icon: people)
    │   ├── NavItem: "Growth" (icon: trending_up)
    │   ├── NavItem: "Schedule" (icon: event)
    │   ├── NavItem: "Memberships" (icon: loyalty)
    │   ├── NavItem: "Member App" (icon: bolt)
    │   ├── NavItem: "Employees" (icon: badge)
    │   ├── NavItem: "Sign up QR Codes" (icon: qr_code)
    │   └── NavItem: "Settings" (icon: settings)
    ├── Main Content Area (scrollable, vertical — full page scroll)
    │   ├── Back Button Row
    │   ├── Profile Header Section
    │   │   ├── CircleAvatar (member photo)
    │   │   ├── Name Text ("Justin Stemmons")
    │   │   ├── Membership Summary Row
    │   │   │   ├── Text ("Paying for 4 Memberships")
    │   │   │   └── Badge ("Paid")
    │   │   ├── Action Buttons Row
    │   │   │   ├── OutlinedButton ("Check In")
    │   │   │   ├── OutlinedButton ("Charge Card")
    │   │   │   └── OutlinedButton ("Edit")
    │   │   ├── Linked Accounts Section (TOP-LEVEL, not inside a card)
    │   │   │   ├── Section Title ("Linked Accounts")
    │   │   │   ├── LinkedAccountChip Row
    │   │   │   │   ├── LinkedAccountChip: "Stacy Stemmons" (tappable)
    │   │   │   │   ├── LinkedAccountChip: "Mia Stemmons" (tappable)
    │   │   │   │   └── LinkedAccountChip: "Bob Stemmons" (tappable)
    │   │   │   └── OutlinedButton ("Manage Linked accounts", full width)
    │   ├── Two-Column Layout (Row on desktop, Column on iPad)
    │   │   ├── Left Column
    │   │   │   ├── Card: Personal Information
    │   │   │   │   ├── Section Title
    │   │   │   │   ├── Info Row: Number (tappable link)
    │   │   │   │   ├── Info Row: Email (tappable link)
    │   │   │   │   ├── Info Row: Address
    │   │   │   │   ├── Subsection: Emergency Contact
    │   │   │   │   │   ├── Info Row: Name
    │   │   │   │   │   ├── Info Row: Number (tappable link)
    │   │   │   │   │   └── Info Row: Email (tappable link)
    │   │   │   │   └── OutlinedButton ("View Waiver")
    │   │   │   └── Card: Rank & Retention
    │   │   │       ├── Section Title
    │   │   │       ├── Rank Display Row
    │   │   │       │   ├── Rank Badge Image (belt/medal)
    │   │   │       │   ├── Stat: "10 classes / Classes in Rank"
    │   │   │       │   └── Stat: "In 5 classes / Recommend Promo" (informational only)
    │   │   │       ├── Rank Label ("Silver (Amateur)")
    │   │   │       ├── OutlinedButton ("Promote")
    │   │   │       ├── Subsection: Retention
    │   │   │       │   ├── Stat Row 1
    │   │   │       │   │   ├── Stat: "5 days ago / Last Class" (color from RetentionThreshold util)
    │   │   │       │   │   └── Stat: "5 weeks / Class Streak" (color from RetentionThreshold util)
    │   │   │       │   └── Stat Row 2
    │   │   │       │       ├── Stat: "3400 points / Points Balance"
    │   │   │       │       └── Stat: "14 videos / Videos Watched"
    │   │   │       └── Subsection: Recently Redeemed Rewards
    │   │   │           └── Horizontal Row of RewardCards (3 items, NOT tappable)
    │   │   └── Right Column
    │   │       ├── Membership Carousel (paginated)
    │   │       │   ├── Header Row
    │   │       │   │   ├── Left Arrow (chevron_left, tappable)
    │   │       │   │   ├── Column (center)
    │   │       │   │   │   ├── Membership Name ("Unlimited Classes")
    │   │       │   │   │   └── Page Indicator ("(1 / 3 Memberships)")
    │   │       │   │   └── Right Arrow (chevron_right, tappable)
    │   │       │   ├── Info Row: Status ("Active" green)
    │   │       │   ├── Info Row: Cost (formula + strikethrough + bold total)
    │   │       │   ├── Info Row: Last Paid
    │   │       │   ├── Info Row: Next Due
    │   │       │   ├── Info Row: Start Date
    │   │       │   ├── Subsection: Paying Membership For
    │   │       │   │   ├── Container with member chips
    │   │       │   │   │   ├── MemberChip: "Stacy Stemmons" (avatar + name)
    │   │       │   │   │   └── MemberChip: "Mia Stemmons" (avatar + name)
    │   │       │   │   └── OutlinedButton ("Manage Their Membership")
    │   │       │   └── Subsection: Discounts
    │   │       │       ├── DiscountCard (Winter Discount)
    │   │       │       └── OutlinedButton ("Manage Discounts")
    │   │       ├── Section: Payment History
    │   │       │   ├── Table Header Row (Name, Date, Invoice)
    │   │       │   └── Table Body (scrollable within fixed-height container)
    │   │       │       └── Table Rows (N rows, each with Invoice button)
    │   │       └── Action Buttons Row
    │   │           ├── OutlinedButton ("Freeze Membership")
    │   │           └── OutlinedButton ("Cancel Membership")
    └── Right Sidebar (ALWAYS visible, fixed, member quick-list)
        ├── Search Field (filters in real-time)
        └── MemberListItem × N (avatar + name, scrollable)
```

---

## STRUCTURAL CHANGES FROM v1

> **Key architectural difference:** Linked Accounts are now a top-level concept tied to the **account**, not to individual memberships. Each linked account can have different memberships. The Membership card is now a **paginated carousel** showing one membership at a time, and includes a "Paying Membership For" subsection specifying which linked members this particular membership covers.

1. **Linked Accounts** moved from inside the Membership card → top-level in the Profile Header section
2. **Membership label** changed from specific plan name → summary "Paying for N Memberships" (aggregate count)
3. **Membership card** is now a **carousel/paginator** with left/right arrows and a page indicator (e.g., "1 / 3 Memberships")
4. **"Paying Membership For"** replaces the old "Linked Accounts" subsection inside the Membership card — shows which specific members this membership pays for
5. **"Manage Their Membership"** replaces "Manage Linked accounts" button inside the membership card
6. Linked account chips now show **full names** (e.g., "Stacy Stemmons") instead of relationship labels ("Wife Account")

---

## COMPONENT SPECIFICATIONS

### Left Sidebar / Navigation Rail

- **Type:** Container (fixed width, full height)
- **Background:** AppColors.surfaceDark
- **Width:** AppSizing.sidebarWidth (~80px, icon+label stacked)
- **Padding:** AppSpacing.sm vertical
- **Children:** Column of NavItem widgets
- **Active indicator:** "Add New Member" uses AppColors.accentOrange
- **Inactive items:** AppColors.textSecondary
- **Collapsible behavior:** Can be set to 50% opacity (not hidden, still visible but dimmed). This applies globally and is not screen-specific.

### NavItem (extract as reusable widget)

- **Type:** InkWell → Column(icon + text)
- **Icon size:** AppSizing.iconMedium
- **Text style:** AppTypography.labelSmall
- **Text color (active):** AppColors.accentOrange
- **Text color (inactive):** AppColors.textSecondary
- **Spacing icon→text:** AppSpacing.xs
- **Tap target:** full width of sidebar, AppSpacing.md vertical padding

### Back Button

- **Type:** TextButton / InkWell
- **Content:** Row(Icon(chevron_left) + Text("Back"))
- **Text style:** AppTypography.bodyMedium
- **Text color:** AppColors.textSecondary
- **Padding:** AppSpacing.md left, AppSpacing.sm top

### Profile Header Section

- **Type:** Column, crossAxisAlignment: center
- **Background:** inherits AppColors.background
- **Spacing between children:** AppSpacing.sm

### Profile Avatar

- **Type:** CircleAvatar / ClipOval
- **Size:** AppSizing.avatarXLarge (~120px)
- **Border:** AppColors.outline, thin
- **Image:** API-loaded member photo
- **Fit:** BoxFit.cover

### Member Name

- **Type:** Text
- **Content:** "Justin Stemmons"
- **Style:** AppTypography.headlineMedium
- **Color:** AppColors.textPrimary (white)

### Membership Summary Row (CHANGED from v1)

- **Type:** Row (mainAxisAlignment: center)
- **Children:**
  - Text: "Paying for 4 Memberships"
    - Style: AppTypography.bodyMedium
    - Color: AppColors.accentOrange
    - **Dynamic:** "Paying for {N} Memberships" — count from API
  - Badge: "Paid"
    - Background: AppColors.accentOrange
    - Text color: AppColors.textOnAccent
    - Border radius: AppRadius.pill
    - Padding: horizontal AppSpacing.sm, vertical AppSpacing.xxs
    - Text style: AppTypography.labelSmall

### Action Buttons Row (Check In / Charge Card / Edit)

- **Type:** Row, mainAxisAlignment: center
- **Gap:** AppSpacing.md
- **Each button:**
  - Type: OutlinedButton
  - Border: AppColors.outline
  - Border radius: AppRadius.button
  - Text style: AppTypography.labelMedium
  - Text color: AppColors.textPrimary
  - Padding: horizontal AppSpacing.lg, vertical AppSpacing.sm
  - Min width: AppSizing.actionButtonMinWidth

### Linked Accounts Section (NEW POSITION — top-level in header)

> Previously nested inside the Membership card. Now sits in the Profile Header section, below the action buttons, spanning the full width of the main content area. This reflects the conceptual change: linked accounts are tied to the **account**, not to a specific membership.

- **Title:** "Linked Accounts"
  - Style: AppTypography.titleMedium
  - Color: AppColors.textPrimary
  - Alignment: center
  - Margin bottom: AppSpacing.sm

- **LinkedAccountChip Row:**
  - Type: Row (mainAxisAlignment: center) or Wrap for overflow
  - Gap: AppSpacing.md
  - Each chip:
    - Row(CircleAvatar + Text)
    - Avatar: AppSizing.avatarSmall, API-loaded photo, BoxFit.cover
    - Text: full member name (e.g., "Stacy Stemmons")
    - Style: AppTypography.bodySmall, AppColors.textPrimary
    - **TAPPABLE:** navigates to that linked member's detail page

- **"Manage Linked accounts" Button:**
  - Full-width OutlinedButton (spans main content width)
  - Border: AppColors.outline
  - Border radius: AppRadius.button
  - Text: "Manage Linked accounts"
  - Style: AppTypography.labelMedium, AppColors.textPrimary
  - Margin top: AppSpacing.sm

### Card: Personal Information

- **Type:** Container / Card
- **Background:** AppColors.cardBackground
- **Border radius:** AppRadius.card
- **Padding:** AppSpacing.cardPadding
- **Margin bottom:** AppSpacing.lg

#### Section Title: "Personal Information"

- **Style:** AppTypography.titleLarge
- **Color:** AppColors.textPrimary
- **Margin bottom:** AppSpacing.md

#### Info Row (Label: Value pattern) — extract as reusable widget

- **Type:** Row or RichText
- **Label** ("Number:", "Email:", "Address:"):
  - Style: AppTypography.bodyMedium
  - Color: AppColors.textSecondary
- **Value:**
  - Default: AppTypography.bodyMedium, AppColors.textPrimary
  - Linked (phone/email): AppColors.linkColor, underlined, tappable
- **Spacing label→value:** AppSpacing.sm
- **Row spacing (vertical):** AppSpacing.sm

#### Emergency Contact Subsection

- **Title:** "Emergency Contact"
  - Style: AppTypography.titleSmall, AppColors.textPrimary
  - Margin top: AppSpacing.lg, Margin bottom: AppSpacing.sm
- Same InfoRow pattern as above

#### View Waiver Button

- Full-width OutlinedButton
- Border: AppColors.outline, Border radius: AppRadius.button
- Text: "View Waiver", AppTypography.labelMedium, AppColors.textPrimary
- Margin top: AppSpacing.lg

### Membership Carousel (CHANGED — now paginated, replaces static Membership card)

> Each linked account can have different memberships. This card now cycles through all memberships this member is paying for. The carousel shows one membership at a time with navigation arrows.

- **Type:** Container / Card
- **Background:** AppColors.cardBackground
- **Border radius:** AppRadius.card
- **Padding:** AppSpacing.cardPadding

#### Carousel Header Row

- **Type:** Row (mainAxisAlignment: spaceBetween, crossAxisAlignment: center)
- **Left arrow:**
  - Icon: chevron_left
  - Color: AppColors.textPrimary
  - Size: AppSizing.iconMedium
  - Tappable: navigates to previous membership
  - Disabled state: AppColors.textTertiary (when on first item)
- **Center Column (crossAxisAlignment: center):**
  - Membership name: "Unlimited Classes"
    - Style: AppTypography.titleLarge
    - Color: AppColors.textPrimary
  - Page indicator: "(1 / 3 Memberships)"
    - Style: AppTypography.bodySmall
    - Color: AppColors.textSecondary
- **Right arrow:**
  - Icon: chevron_right
  - Color: AppColors.textPrimary
  - Size: AppSizing.iconMedium
  - Tappable: navigates to next membership
  - Disabled state: AppColors.textTertiary (when on last item)

#### Membership Info Rows (same pattern per page)

- **"Status:"** value "Active" → color: AppColors.successGreen
- **"Cost:"** value "($165.00 + $80 * 3) * 20% off = $320"
  - Formula portion: AppColors.textSecondary, AppTypography.bodySmall
  - Strikethrough on original price: TextDecoration.lineThrough
  - Bold total "$320": AppTypography.titleSmall, AppColors.textPrimary, fontWeight bold
- **"Last Paid:" / "Next Due:" / "Start Date:"**
  - Value: AppTypography.bodyMedium, fontWeight bold, AppColors.textPrimary

#### Paying Membership For Subsection (NEW — replaces old Linked Accounts inside card)

> Shows which specific linked members this particular membership covers. Different memberships in the carousel may show different members here.

- **Title:** "Paying Membership For"
  - Style: AppTypography.titleSmall, AppColors.textPrimary
  - Margin top: AppSpacing.md

- **Container:**
  - Background: AppColors.surfaceElevated
  - Border radius: AppRadius.card
  - Padding: AppSpacing.sm

- **Member chips** (inside container):
  - Layout: Wrap, gap AppSpacing.md
  - Each chip: Row(CircleAvatar + Text)
    - Avatar size: AppSizing.avatarSmall
    - Text: full name (e.g., "Stacy Stemmons", "Mia Stemmons")
    - Style: AppTypography.bodySmall, AppColors.textPrimary
    - These chips display who is covered — they may or may not be tappable (likely navigates to member)

- **"Manage Their Membership" Button:**
  - Full-width OutlinedButton
  - Text: "Manage Their Membership"
  - Style: AppTypography.labelMedium, AppColors.textPrimary
  - Border: AppColors.outline, Border radius: AppRadius.button
  - Context-aware: applies to the currently visible membership in the carousel

#### Discounts Subsection

- **Title:** "Discounts" — AppTypography.titleSmall (standalone label)
- **DiscountCard:**
  - Background: AppColors.surfaceElevated
  - Border radius: AppRadius.card
  - Padding: AppSpacing.sm
  - Row layout:
    - Left: Icon (calendar/gift, AppColors.accentGreen)
    - Center Column:
      - "Winter Discount": AppTypography.bodyMedium, AppColors.textPrimary
      - "11/01/2025 - 1/01/2026 (2 months)": AppTypography.bodySmall, AppColors.textSecondary
    - Right: Badge "20% off"
      - Border: AppColors.accentGreen, transparent background
      - Text: AppTypography.labelSmall, AppColors.accentGreen
      - Border radius: AppRadius.pill
- **Manage Discounts:** full-width OutlinedButton

### Card: Rank & Retention

- **Type:** Container / Card
- **Background:** AppColors.cardBackground
- **Border radius:** AppRadius.card
- **Padding:** AppSpacing.cardPadding

#### Rank Display

- Row layout:
  - Left: Rank badge image (~80px, mix of local asset + API loaded)
  - Right Column:
    - person icon + "10 classes" (bold) + "Classes in Rank" (secondary)
    - trending_up icon + "In 5 classes" (bold) + "Recommend Promo" (secondary) — **INFORMATIONAL ONLY**
- Below image: "Silver (Amateur)" — AppTypography.titleSmall, AppColors.textPrimary

#### Promote Button

- Full-width OutlinedButton, text "Promote"

#### Retention Subsection

- **Title:** "Retention" — AppTypography.titleSmall
- 2×2 grid of stat items

#### RetentionStatItem (extract as reusable widget)

- **Type:** Row(icon + Column(value, label))
- **Icon:** varies (clock, bolt, star, play_arrow) — mix of Material + custom SVGs
- **Value color:** determined by `RetentionThreshold` utility (see section below)
- **Label:** AppTypography.bodySmall, AppColors.textSecondary

#### Recently Redeemed Rewards

- **Title:** "Recently Redeemed Rewards" — AppTypography.titleSmall
- Horizontal Row of RewardCards

#### RewardCard (extract as reusable widget)

- Column(image + title + subtitle)
- Image: ClipRRect, AppRadius.image, ~AppSizing.thumbnailLarge, BoxFit.cover
- Title: AppTypography.bodySmall, AppColors.textPrimary, center
- Subtitle: AppTypography.labelSmall, AppColors.textSecondary, center
- Width: AppSizing.rewardCardWidth
- Gap between cards: AppSpacing.md
- **NOT tappable**

### Payment History Section

- **Title:** "Payment History" — AppTypography.titleSmall, AppColors.textPrimary

#### Payment History Table

- **Type:** Container with Column (header + scrollable body)
- **Background:** AppColors.cardBackground
- **Border radius:** AppRadius.card
- **Scrollable:** YES — fixed-height container with internal vertical scroll
- **Header row:**
  - Columns: "Name", "Date", "Invoice"
  - Style: AppTypography.labelMedium, AppColors.textSecondary
  - Bottom border: AppColors.divider
- **Data rows:**
  - Name: AppTypography.bodySmall, AppColors.textPrimary
  - Date: AppTypography.bodySmall, AppColors.textPrimary
  - Invoice: SmallOutlinedButton (pill-shaped)
    - Border: AppColors.outline, Border radius: AppRadius.pill
    - Text: "Invoice", AppTypography.labelSmall, AppColors.textPrimary
- **Row dividers:** AppColors.divider

### Freeze / Cancel Membership Buttons

- **Type:** Row, mainAxisAlignment: center
- **Gap:** AppSpacing.md
- Both OutlinedButtons with AppColors.outline border
- Text: AppTypography.labelMedium, AppColors.textPrimary
- Both trigger **modal confirmation dialog**

### Right Sidebar — Member Quick List

- **Visibility:** ALWAYS visible (never hidden)
- **Type:** Container (fixed width, full height)
- **Background:** AppColors.background
- **Width:** AppSizing.rightSidebarWidth (~200px)

#### Search Field

- **Type:** TextField
- **Background:** AppColors.inputBackground
- **Border radius:** AppRadius.input
- **Hint text:** "search..."
- **Hint style:** AppTypography.bodySmall, AppColors.textTertiary
- **Prefix icon:** Icons.search, AppColors.textTertiary
- **Filtering:** REAL-TIME

#### MemberListItem (extract as reusable widget)

- **Type:** Row(CircleAvatar + Text)
- **Avatar size:** AppSizing.avatarSmall (~36px)
- **Name:** AppTypography.bodySmall, AppColors.textPrimary
- **Spacing avatar→name:** AppSpacing.sm
- **Vertical spacing between items:** AppSpacing.xs
- **Tap behavior:** navigate to that member's detail page
- **List is scrollable** independently of main content

---

## RETENTION THRESHOLD UTILITY

**File:** `lib/utils/retention_thresholds.dart` (or similar util location)

This utility determines the color of retention stat values based on configurable threshold ranges. Used across multiple screens.

```
RetentionThreshold Utility:
├── Constants (defined in app constants file):
│   ├── Last Class thresholds (days since last class)
│   │   ├── GREEN range: [defined in constants]
│   │   ├── YELLOW range: [defined in constants]
│   │   └── RED range: [defined in constants]
│   ├── Class Streak thresholds (weeks)
│   │   ├── GREEN range: [defined in constants]
│   │   ├── YELLOW range: [defined in constants]
│   │   └── RED range: [defined in constants]
│   └── (extensible for other retention metrics)
├── Colors mapped from constants file:
│   ├── GREEN → AppColors.retentionGreen
│   ├── YELLOW → AppColors.retentionYellow
│   └── RED → AppColors.retentionRed
└── Usage: RetentionThreshold.getColor(metric, value) → Color
```

---

## SPACING RELATIONSHIPS

- Sidebar width (left): AppSizing.sidebarWidth
- Main content horizontal padding: AppSpacing.screenHorizontal
- Gap between left column and right column: AppSpacing.lg
- Card internal padding: AppSpacing.cardPadding
- Gap between cards (vertical): AppSpacing.lg
- Gap between info rows: AppSpacing.sm
- Section title to first content: AppSpacing.md
- Subsection title margin-top: AppSpacing.lg
- Profile avatar to name: AppSpacing.sm
- Name to membership summary: AppSpacing.xs
- Membership summary to action buttons: AppSpacing.md
- Action buttons to Linked Accounts title: AppSpacing.md
- Linked Accounts section to two-column layout: AppSpacing.lg
- Action buttons gap: AppSpacing.md
- Right sidebar item spacing: AppSpacing.xs vertical
- Carousel arrow to title: AppSpacing.sm

---

## DESIGN TOKEN EXPECTATIONS

### Colors

| Token | Usage |
|---|---|
| AppColors.background | Page background (very dark) |
| AppColors.surfaceDark | Left sidebar background |
| AppColors.cardBackground | Card surfaces |
| AppColors.surfaceElevated | Paying Membership For container, discount container |
| AppColors.textPrimary | White text |
| AppColors.textSecondary | Grey labels |
| AppColors.textTertiary | Placeholder text, inactive nav, disabled arrows |
| AppColors.accentOrange | Membership summary, active nav, bolt icon |
| AppColors.accentGreen | Discount badge border/text |
| AppColors.successGreen | Active status text |
| AppColors.linkColor | Phone/email links (blue, underlined) |
| AppColors.outline | Button/card borders |
| AppColors.divider | Table row separators |
| AppColors.textOnAccent | White text on colored badges |
| AppColors.inputBackground | Search field bg |
| AppColors.retentionGreen | Retention stat — healthy range |
| AppColors.retentionYellow | Retention stat — warning range |
| AppColors.retentionRed | Retention stat — at-risk range |

### Typography

| Token | Usage |
|---|---|
| AppTypography.headlineMedium | Member name |
| AppTypography.titleLarge | Card section titles, membership carousel name |
| AppTypography.titleMedium | Linked Accounts top-level title |
| AppTypography.titleSmall | Subsection titles |
| AppTypography.bodyMedium | Info row labels and values, membership summary |
| AppTypography.bodySmall | Secondary info, table data, carousel page indicator |
| AppTypography.labelMedium | Button text |
| AppTypography.labelSmall | Nav labels, badges, small tags |

### Spacing

| Token | Approx Value |
|---|---|
| AppSpacing.xxs | ~2-4 |
| AppSpacing.xs | ~4-6 |
| AppSpacing.sm | ~8-10 |
| AppSpacing.md | ~16 |
| AppSpacing.lg | ~24 |
| AppSpacing.xl | ~32 |
| AppSpacing.screenHorizontal | Screen-level horizontal padding |
| AppSpacing.cardPadding | Internal card padding |

### Radius

| Token | Usage |
|---|---|
| AppRadius.card | Card containers |
| AppRadius.pill | Badges, invoice buttons |
| AppRadius.button | Action buttons |
| AppRadius.image | Reward images |
| AppRadius.input | Search field |

### Sizing

| Token | Usage |
|---|---|
| AppSizing.sidebarWidth | Left nav width |
| AppSizing.rightSidebarWidth | Right member list width |
| AppSizing.avatarXLarge | Profile photo |
| AppSizing.avatarSmall | Linked account chips, sidebar list, paying-for chips |
| AppSizing.iconSmall | Small decorative icons |
| AppSizing.iconMedium | Nav icons, carousel arrows |
| AppSizing.thumbnailLarge | Reward card images |
| AppSizing.rankBadgeSize | Rank medal/belt image |
| AppSizing.actionButtonMinWidth | Action button min width |
| AppSizing.rewardCardWidth | Reward card width |

---

## INTERACTIVE ELEMENTS

| Element | Behavior |
|---|---|
| Back button | Navigate to previous screen (Members list) |
| Check In | Trigger check-in flow / confirmation dialog |
| Charge Card | Open payment dialog |
| Edit | Navigate to member edit form |
| Phone numbers | Launch tel: link |
| Email addresses | Launch mailto: link |
| **Linked account chips (header)** | **Navigate to that linked member's detail page** |
| **Manage Linked accounts (header)** | **Navigate to linked accounts management** |
| **Membership carousel arrows** | **Page through memberships (left/right)** |
| **Manage Their Membership** | **Opens Freeze/Cancel Modal with Freeze tab pre-selected (default)** |
| View Waiver | Open waiver document / navigate to waiver screen |
| Promote | Open rank promotion dialog/flow |
| Manage Discounts | Navigate to discounts management |
| Invoice buttons (×N) | Download or view invoice PDF |
| Freeze Membership | **Opens Freeze/Cancel Modal with Freeze tab pre-selected** (account-level) |
| Cancel Membership | **Opens Freeze/Cancel Modal with Cancel tab pre-selected** (membership-level) |
| Right sidebar member items | Navigate to that member's detail page |
| Search field | **Real-time filtering** of right sidebar member list |
| Left nav items | Navigate to respective sections |
| Reward cards | **NOT tappable** |
| "Recommend Promo" | **Informational only, NOT tappable** |

---

## ASSETS NEEDED

| Asset | Source | Type |
|---|---|---|
| Member profile photo | API loaded | Mix (custom + standard) |
| Rank badge/medal image | Local asset or API (per rank) | Mix |
| Linked account avatars (header chips) | API loaded | Standard |
| Paying-for member avatars (membership card) | API loaded | Standard |
| Reward images | API loaded (rewards catalog) | Standard |
| App logo "COMBAT DEN" | Local asset | Custom SVG/PNG |
| Nav icons | **Mix** of Flutter Material Icons + custom SVGs | Both |
| Retention stat icons | **Mix** of Material + custom SVGs | Both |
| Discount icon | Custom or Material (calendar/gift) | Mix |
| Carousel arrows | Material Icons (chevron_left, chevron_right) | Standard |

---

## CONDITIONAL LOGIC

| Element | Condition |
|---|---|
| "Paid" badge | Shows only when membership payment is current |
| Membership summary text | Dynamic: "Paying for {N} Memberships" — count from API |
| Status value per membership | "Active" (green), "Inactive", "Frozen", "Cancelled" — color changes per membership |
| Linked Accounts section | Shows only if linked accounts exist; chip count varies |
| Carousel arrows | Disabled (dimmed) when at first/last membership |
| Carousel page indicator | Dynamic: "({current} / {total} Memberships)" |
| Paying Membership For | Shows per-membership; different memberships may cover different members |
| Discounts section | Shows only if active discounts exist (may vary per membership) |
| Promo recommendation | Shows only when close to promotion threshold |
| Invoice buttons | One per payment record |
| Reward cards | Show only if rewards have been redeemed |
| Freeze/Cancel buttons | Both open Freeze/Cancel Modal; Freeze = account-level, Cancel = membership-level |
| Cost formula | Dynamic based on membership type, add-ons, discounts |
| Right sidebar list | Populated from API, filtered by search input in real-time |
| Retention stat colors | Dynamic via RetentionThreshold utility (green/yellow/red) |

---

## STATE VARIATIONS

### Loading
Shimmer placeholders for: profile photo (circle shimmer), text lines (rectangular shimmers), linked account chips (pill shimmers), membership carousel (full card shimmer), cards (full card-sized shimmer blocks). Right sidebar shows shimmer list items independently.

### Empty
- No linked accounts → hide Linked Accounts section entirely or show "No linked accounts" with an add button
- No memberships → hide carousel or show "No memberships" empty state
- Only 1 membership → **hide carousel arrows and page indicator**; show just the membership name as a static title
- No payment history → "No payments yet" message in table area
- No "Paying Membership For" members → hide subsection or show "No members assigned"
- No rewards → hide "Recently Redeemed Rewards" subsection or show "No rewards redeemed yet"

### Error
- Member data fails to load → centered error state with retry button in main content area
- Payment history fails → inline error within that section with retry
- Right sidebar loads independently

---

## COMPONENT EXTRACTION

| Widget Name | Contents | Reason |
|---|---|---|
| SidebarNavItem | Icon + label, active/inactive states | Reused ~10 times |
| InfoRow | Label + value, optional link styling | Reused ~10+ times |
| SectionCard | Card wrapper with title | Reused for multiple major cards |
| OutlinedActionButton | Full-width outlined button | Reused ~7 times |
| LinkedAccountChip | Avatar + full name (tappable) | Reused in header per linked account |
| MemberChip | Avatar + full name (display) | Reused in Paying Membership For per member |
| **MembershipCarousel** | Paginated membership card with arrows + page indicator | Complex, encapsulates carousel state |
| RetentionStatItem | Icon + value + label, color from threshold util | Reused 4 times |
| RewardCard | Image + title + subtitle column | Reused per reward |
| PaymentHistoryRow | Name + date + invoice button | Reused per payment |
| MemberListItem | Avatar + name (sidebar) | Reused 12+ times |
| SmallOutlinedButton | Pill-shaped button (Invoice style) | Reused in table |
| StatWithIcon | Icon + primary text + secondary text | Reused in rank section |
| ConfirmationModal | **Freeze/Cancel Management Modal** — segment selector + Freeze/Cancel views | Opened from 3 buttons (Freeze, Cancel, Manage Their Membership) |
| **RetentionThresholdUtil** | Threshold color resolver | Shared util, used across screens |

---

## TEXT OVERFLOW RULES

| Element | Max Lines | Overflow |
|---|---|---|
| Member name | 1 | Ellipsis |
| Membership summary ("Paying for N...") | 1 | Ellipsis |
| Carousel membership name | 1 | Ellipsis |
| Carousel page indicator | 1 | Ellipsis |
| Address value | 2 | Ellipsis |
| Email values | 1 | Ellipsis |
| Linked account chip names | 1 | Ellipsis |
| Paying-for member names | 1 | Ellipsis |
| Payment name column | 1 | Ellipsis |
| Reward card title | 2 | Ellipsis, center aligned |
| Right sidebar names | 1 | Ellipsis |
| Cost formula text | 1 | Ellipsis (or allow wrap) |
| Discount date range | 1 | Ellipsis |

---

## SCROLL BEHAVIOR

- **Main content:** Full vertical scroll — user can scroll through everything. ClampingScrollPhysics (web) or BouncingScrollPhysics (mobile/tablet).
- **Pull to refresh:** Yes, on main content area (refresh member data)
- **Sticky headers:** No
- **Payment History table:** Scrollable within a **fixed-height container** (internal vertical scroll)
- **Right sidebar member list:** Independent vertical scroll, always visible
- **Left sidebar:** Fixed, no scroll
- **Rewards row:** Horizontal scroll if more items than visible
- **Membership carousel:** Supports **both arrow buttons and swipe gestures** on touch devices (discrete pages)
- **Cost formula:** Always visible

---

## IMAGE LOADING

| Image | Placeholder | Error Fallback | Fit |
|---|---|---|---|
| Profile avatar | Grey circle + person icon | Same person icon | BoxFit.cover |
| Rank badge | Shimmer rectangle | Default rank icon | BoxFit.contain |
| Linked account avatars (header) | Grey circle + person icon | Initials avatar | BoxFit.cover |
| Paying-for member avatars | Grey circle + person icon | Initials avatar | BoxFit.cover |
| Reward card images | Shimmer rectangle | Grey container + image icon | BoxFit.cover |
| Right sidebar avatars | Grey circle | Initials avatar | BoxFit.cover |

---

## ACCESSIBILITY

| Element | Note |
|---|---|
| Profile avatar | semanticLabel = "Profile photo of [member name]" |
| Back button | semanticLabel = "Go back to members list" |
| Check In / Charge Card / Edit | Ensure 48px min tap target |
| Phone/email links | semanticLabel = "Call [number]" / "Email [address]" |
| Paid badge | semanticLabel = "Membership payment status: Paid" |
| Membership summary | semanticLabel = "Paying for [N] memberships" |
| Carousel left arrow | semanticLabel = "Previous membership" |
| Carousel right arrow | semanticLabel = "Next membership" |
| Carousel page indicator | semanticLabel = "Membership [X] of [Y]" |
| Active status | semanticLabel = "Membership status: Active" |
| Linked account chips | semanticLabel = "View [name]'s profile" |
| Invoice buttons | semanticLabel = "View invoice for [payment name] on [date]" |
| Nav items | semanticLabel = "[nav label] navigation" |
| Rank badge image | semanticLabel = "Current rank: Silver (Amateur)" |
| Right sidebar search | semanticLabel = "Search members" |
| Freeze/Cancel buttons | Ensure screen reader announces clearly (destructive) |
| Reading order | Left sidebar → main content (header → linked accounts → left col → right col) → right sidebar |

---

## RESPONSIVE BEHAVIOR

| Breakpoint | Layout |
|---|---|
| Desktop (wide) | Three-panel: left sidebar + two-column main content + right sidebar |
| iPad / Tablet | Three-panel but main content **stacks to single column** (left col above right col) |
| Left sidebar | Can be set to **50% opacity** (still visible, not collapsed/hidden) |
| Right sidebar | **Always visible** at all breakpoints |
| Linked Accounts section | Stays full-width centered in header at all breakpoints |
| Membership carousel | Full width of its column; arrows stay at edges |

---

## DATA MODEL NOTES

The structural changes imply the following data relationships:

```
Account (Justin Stemmons)
├── Linked Accounts: [Stacy, Mia, Bob]  ← account-level, not membership-level
├── Membership 1: "Unlimited Classes"
│   ├── Status, Cost, Dates...
│   └── Paying For: [Stacy, Mia]  ← which linked members this membership covers
├── Membership 2: [another plan]
│   └── Paying For: [Bob]
└── Membership 3: [another plan]
    └── Paying For: [Justin himself, etc.]
```

- **Linked Accounts** are fetched once at the account level
- **Memberships** are an array; the carousel iterates through them
- Each membership has its own `payingFor` list of member references
- The membership count in the header summary ("Paying for 4 Memberships") is the total across all linked accounts
- Payment History is **filtered per-membership on the backend** — frontend passes membership ID
- Discounts are **per-membership** — they change as the carousel paginates

---

## RESOLVED QUESTIONS (v2)

1. **Payment History:** Filtered per the currently visible membership in the carousel. **Filtering is done on the backend** — the frontend requests payment history by membership ID and the API returns only the relevant records.
2. **Discounts:** Apply per specific membership (shown inside the carousel, changes as you paginate).
3. **Freeze/Cancel:** Both open the **same modal popup** (the Freeze/Cancel Management Modal described below). Freeze operates at the **account level**. Cancel operates at the **membership level** (the one currently visible in the carousel).
4. **Carousel interaction:** Supports **both** arrow buttons and swipe gestures on touch devices.
5. **Single membership:** Yes — when only 1 membership exists, **simplify the header**: hide the left/right arrows and the page indicator, show just the membership name as a static title.
6. **"Manage Their Membership" button:** Opens the **same Freeze/Cancel Management Modal** described below.

---

## FREEZE / CANCEL MANAGEMENT MODAL (NEW)

> This modal is opened by "Freeze Membership", "Cancel Membership", or "Manage Their Membership". It is a single shared popup with a top-level tab/segment selector that switches between Freeze and Cancel views.

### Modal Structure

```
└── Modal Overlay (centered, dark scrim behind)
    └── Modal Container
        ├── Top Segment Selector (Freeze | Cancel)
        ├── Content Area (swaps based on selected segment)
        │   ├── [If Freeze selected] → Freeze Content
        │   └── [If Cancel selected] → Cancel Content
        └── Action Button(s) at bottom
```

### Modal Container

- **Type:** Dialog / BottomSheet (modal)
- **Background:** AppColors.cardBackground
- **Border radius:** AppRadius.card (top corners if bottom sheet, all corners if centered dialog)
- **Padding:** AppSpacing.cardPadding
- **Max width:** constrained (e.g., AppSizing.modalMaxWidth)
- **Scrim:** AppColors.scrimOverlay (semi-transparent dark behind modal)

### Top Segment Selector

- **Type:** Segmented control / Tab bar (two options)
- **Options:** "Freeze" | "Cancel"
- **Selected state:**
  - Background: AppColors.accentOrange (or AppColors.segmentSelected)
  - Text: AppColors.textOnAccent, AppTypography.labelMedium, bold
- **Unselected state:**
  - Background: transparent or AppColors.surfaceElevated
  - Text: AppColors.textSecondary, AppTypography.labelMedium
- **Border radius:** AppRadius.pill (each segment)
- **Container border radius:** AppRadius.pill (outer wrapper)
- **Default selection:** depends on which button opened the modal:
  - "Freeze Membership" button → opens with Freeze tab selected
  - "Cancel Membership" button → opens with Cancel tab selected
  - "Manage Their Membership" button → opens with Freeze tab selected (default)

### Freeze Content (shown when Freeze tab is selected)

- **Scope:** Account-level — freezing affects the entire account, all memberships
- **Content (to be defined):**
  - Explanation text: describes what freezing means (all memberships paused)
  - Freeze duration selector (if applicable)
  - Confirmation message
- **Action button:** "Freeze Account" (or similar)
  - Style: filled button, AppColors.accentOrange or AppColors.warningYellow
  - Full width at bottom of modal

### Cancel Content (shown when Cancel tab is selected)

- **Scope:** Membership-level — cancellation applies to the specific membership currently visible in the carousel
- **Content (to be defined):**
  - Membership name being cancelled (pulled from carousel context)
  - Explanation text: describes what cancellation means
  - Cancellation reason selector (if applicable)
  - Impact summary (e.g., "This will cancel coverage for Stacy and Mia")
  - Confirmation message
- **Action button:** "Cancel Membership" (or similar)
  - Style: filled button, AppColors.dangerRed (destructive action)
  - Full width at bottom of modal

### Modal Behavior

- **Close:** tap outside scrim, X button in top-right, or explicit cancel/back button
- **Transition:** switching between Freeze and Cancel tabs swaps content smoothly (crossfade or slide)
- **Confirmation:** both actions should have a final confirmation step or "Are you sure?" before executing
- **Loading state:** after confirm, show loading indicator on the action button; disable interaction
- **Success:** dismiss modal, refresh member data on the main screen
- **Error:** show inline error in the modal, keep modal open for retry

### Component Extraction

| Widget Name | Contents | Reason |
|---|---|---|
| **FreezeAndCancelModal** | Full modal with segment selector + both content views | Opened from 3 different buttons |
| SegmentSelector | Two-option tab bar (Freeze / Cancel) | Could be reused in other modals |
| FreezeContent | Freeze-specific form/confirmation | Encapsulated view |
| CancelContent | Cancel-specific form/confirmation | Encapsulated view |

---

## UPDATES TO OTHER SECTIONS (reflecting resolved questions)

### Updates to INTERACTIVE ELEMENTS table

| Element | Updated Behavior |
|---|---|
| Freeze Membership | Opens **Freeze/Cancel Management Modal** with Freeze tab pre-selected |
| Cancel Membership | Opens **Freeze/Cancel Management Modal** with Cancel tab pre-selected |
| Manage Their Membership | Opens **Freeze/Cancel Management Modal** with Freeze tab pre-selected (default) |
| Membership carousel | Supports **both arrow buttons and swipe** on touch devices |

### Updates to CONDITIONAL LOGIC table

| Element | Updated Condition |
|---|---|
| Payment History | **Filtered per currently visible membership** — backend filters by membership ID |
| Discounts | **Per-membership** — changes as carousel paginates |
| Single membership carousel | Arrows and page indicator **hidden**; shows static title only |
| Cancel content in modal | Reflects the specific membership currently visible in the carousel |
| Freeze content in modal | Account-level — same regardless of which membership is in the carousel |

### Updates to SCROLL BEHAVIOR

- **Membership carousel:** Supports both arrow buttons AND swipe gestures on touch devices

### Updates to COMPONENT EXTRACTION table

| Widget Name | Contents | Reason |
|---|---|---|
| FreezeAndCancelModal | Segment selector + Freeze/Cancel views | Shared by 3 buttons, complex interaction |

### Updates to DESIGN TOKEN EXPECTATIONS — Colors

| Token | Usage |
|---|---|
| AppColors.scrimOverlay | Semi-transparent dark overlay behind modal |
| AppColors.segmentSelected | Selected segment background (may alias accentOrange) |
| AppColors.dangerRed | Destructive cancel button in modal |
| AppColors.warningYellow | Freeze action button (if differentiated from cancel) |

### Updates to DESIGN TOKEN EXPECTATIONS — Sizing

| Token | Usage |
|---|---|
| AppSizing.modalMaxWidth | Max width constraint for the modal |

---

## CHANGELOG

### v2.1 — Resolved open questions and added Freeze/Cancel modal

**Questions resolved:**
1. Payment History is **filtered per-membership, backend-side** — the frontend passes the membership ID, the API returns filtered results
2. Discounts are **per-membership** — they change as the carousel paginates
3. Freeze is **account-level**, Cancel is **membership-level** — both accessed through a shared modal
4. Carousel supports **both arrow buttons and swipe** on touch devices
5. Single membership **simplifies the header** — hides arrows and page indicator
6. "Manage Their Membership" opens the **same Freeze/Cancel modal**

**New component added:**
- **Freeze/Cancel Management Modal** — a shared popup with a segment selector at the top toggling between Freeze (account-level) and Cancel (membership-level) views. Opened by three buttons: "Freeze Membership", "Cancel Membership", and "Manage Their Membership". Each pre-selects the appropriate tab.

### v2.0 — Major structural redesign

**Linked Accounts moved to top-level header:**
- Previously nested inside the Membership card
- Now an account-level concept, displayed in the Profile Header section
- Shows full member names instead of relationship labels

**Membership card → paginated carousel:**
- Left/right arrows cycle through multiple memberships
- Page indicator shows current position (e.g., "1 / 3 Memberships")
- Each membership page has its own status, cost, dates, and paying-for members

**"Paying Membership For" replaces old linked accounts in card:**
- Per-membership subsection showing which linked members are covered
- Different memberships may cover different people

**Membership summary updated:**
- Header now shows "Paying for N Memberships" (aggregate) instead of specific plan name

### v1.0 — Initial specification

- Original spec based on first mockup
- Single static Membership card with linked accounts inside
- All open questions documented for clarification
