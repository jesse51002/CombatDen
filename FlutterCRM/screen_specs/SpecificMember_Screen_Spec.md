# Specific Member Detail — Implementation Specification

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
    │   │   ├── Membership Label Row
    │   │   │   ├── Text ("Unlimited Classes Membership (Family)")
    │   │   │   └── Badge ("Paid")
    │   │   └── Action Buttons Row
    │   │       ├── OutlinedButton ("Check In")
    │   │       ├── OutlinedButton ("Charge Card")
    │   │       └── OutlinedButton ("Edit")
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
    │   │       ├── Card: Membership
    │   │       │   ├── Section Title
    │   │       │   ├── Info Row: Name
    │   │       │   ├── Info Row: Status ("Active" green)
    │   │       │   ├── Info Row: Cost (formula + strikethrough + bold total)
    │   │       │   ├── Info Row: Last Paid
    │   │       │   ├── Info Row: Next Due
    │   │       │   ├── Info Row: Start Date
    │   │       │   ├── Subsection: Linked Accounts
    │   │       │   │   ├── LinkedAccountChip: "Wife Account" (tappable → navigates to member)
    │   │       │   │   ├── LinkedAccountChip: "Daughter Account" (tappable → navigates to member)
    │   │       │   │   ├── LinkedAccountChip: "Son Account" (tappable → navigates to member)
    │   │       │   │   └── OutlinedButton ("Manage Linked accounts")
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

### Membership Label Row

- **Type:** Row (mainAxisAlignment: center)
- **Children:**
  - Text: "Unlimited Classes Membership (Family)"
    - Style: AppTypography.bodyMedium
    - Color: AppColors.accentOrange
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

### Card: Membership

- **Type:** Container / Card
- **Background:** AppColors.cardBackground
- **Border radius:** AppRadius.card
- **Padding:** AppSpacing.cardPadding

#### Info Rows

- **"Status:"** value "Active" → color: AppColors.successGreen
- **"Cost:"** value "(§165.00 + $80 * 3) * 20% off = $320"
  - Formula portion: AppColors.textSecondary, AppTypography.bodySmall
  - Strikethrough on original price: TextDecoration.lineThrough
  - Bold total "$320": AppTypography.titleSmall, AppColors.textPrimary, fontWeight bold
- **"Last Paid:" / "Next Due:" / "Start Date:"**
  - Value: AppTypography.bodyMedium, fontWeight bold, AppColors.textPrimary

#### Linked Accounts Subsection

- **Title:** "Linked Accounts" — AppTypography.titleSmall
- **Container:**
  - Background: AppColors.surfaceElevated
  - Border radius: AppRadius.card
  - Padding: AppSpacing.sm
- **LinkedAccountChip** (extract as reusable widget):
  - Row(CircleAvatar + Text)
  - Avatar size: AppSizing.avatarSmall
  - Text: AppTypography.bodySmall, AppColors.textPrimary
  - Layout: Wrap, gap AppSpacing.md
  - **TAPPABLE:** navigates to linked member's detail page
- **Manage Linked accounts:** full-width OutlinedButton

#### Discounts Subsection

- **Title:** "Discounts" — AppTypography.titleSmall (outside card, standalone label)
- **DiscountCard:**
  - Background: AppColors.surfaceElevated
  - Border radius: AppRadius.card
  - Padding: AppSpacing.sm
  - Row layout:
    - Left: Icon (calendar/gift, AppColors.accentGreen) — mix of Material + custom SVG
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
  - Left: Rank badge image (~80px, mix of local asset + API loaded depending on rank)
  - Right Column:
    - person icon + "10 classes" (bold) + "Classes in Rank" (secondary)
    - trending_up icon + "In 5 classes" (bold) + "Recommend Promo" (secondary) — **INFORMATIONAL ONLY, not tappable**
- Below image: "Silver (Amateur)" — AppTypography.titleSmall, AppColors.textPrimary

#### Promote Button

- Full-width OutlinedButton, text "Promote"

#### Retention Subsection

- **Title:** "Retention" — AppTypography.titleSmall
- 2×2 grid of stat items

#### RetentionStatItem (extract as reusable widget)

- **Type:** Row(icon + Column(value, label))
- **Icon:** varies (clock, bolt, star, play_arrow) — mix of Material icons and custom SVGs
- **Value color:** determined by `RetentionThreshold` utility (see below)
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
- Both are OutlinedButtons with AppColors.outline border
- Text: AppTypography.labelMedium, AppColors.textPrimary
- **"Cancel Membership"** triggers a **modal confirmation dialog** before proceeding

### Right Sidebar — Member Quick List

- **Type:** Container (fixed width, full height)
- **Visibility:** ALWAYS visible (never hidden)
- **Background:** AppColors.background
- **Width:** AppSizing.rightSidebarWidth (~200px)

#### Search Field

- **Type:** TextField
- **Background:** AppColors.inputBackground
- **Border radius:** AppRadius.input
- **Hint text:** "search..."
- **Hint style:** AppTypography.bodySmall, AppColors.textTertiary
- **Prefix icon:** Icons.search, AppColors.textTertiary
- **Padding:** AppSpacing.sm
- **Filtering:** REAL-TIME (filters member list as user types, no submit needed)

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

This utility determines the color of retention stat values based on configurable threshold ranges. It is used in multiple places across the app, not just this screen.

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

**Implementation notes:**
- Threshold range constants live in the app's constants file (not hardcoded in the util)
- The util function takes a metric type and numeric value, returns the appropriate color
- Reusable across any screen that displays retention data
- Colors (green, yellow, red) are defined in the app constants/colors file

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
- Name to membership label: AppSpacing.xs
- Membership label to action buttons: AppSpacing.md
- Action buttons gap: AppSpacing.md
- Right sidebar item spacing: AppSpacing.xs vertical

---

## DESIGN TOKEN EXPECTATIONS

### Colors

| Token | Usage |
|---|---|
| AppColors.background | Page background (very dark) |
| AppColors.surfaceDark | Left sidebar background |
| AppColors.cardBackground | Card surfaces |
| AppColors.surfaceElevated | Linked accounts container, discount container |
| AppColors.textPrimary | White text |
| AppColors.textSecondary | Grey labels |
| AppColors.textTertiary | Placeholder text, inactive nav |
| AppColors.accentOrange | Membership label, active nav, bolt icon |
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
| AppTypography.titleLarge | Card section titles |
| AppTypography.titleSmall | Subsection titles |
| AppTypography.bodyMedium | Info row labels and values |
| AppTypography.bodySmall | Secondary info, table data |
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
| AppSizing.avatarSmall | Linked accounts, sidebar list |
| AppSizing.iconSmall | Small decorative icons |
| AppSizing.iconMedium | Nav icons |
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
| View Waiver | Open waiver document / navigate to waiver screen |
| Promote | Open rank promotion dialog/flow |
| Linked account chips | **Navigate to that linked member's detail page** |
| Manage Linked accounts | Navigate to linked accounts management |
| Manage Discounts | Navigate to discounts management |
| Invoice buttons (×N) | Download or view invoice PDF |
| Freeze Membership | **Open modal confirmation dialog** |
| Cancel Membership | **Open modal confirmation dialog** (destructive action) |
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
| Linked account avatars | API loaded | Standard |
| Reward images | API loaded (rewards catalog) | Standard |
| App logo "COMBAT DEN" | Local asset | Custom SVG/PNG |
| Nav icons | **Mix** of Flutter Material Icons + custom SVGs | Both |
| Retention stat icons | **Mix** of Material + custom SVGs | Both |
| Discount icon | Custom or Material (calendar/gift) | Mix |

---

## CONDITIONAL LOGIC

| Element | Condition |
|---|---|
| "Paid" badge | Shows only when membership payment is current |
| Status value | "Active" (green), "Inactive", "Frozen", "Cancelled" — color changes |
| Linked Accounts section | Shows only if linked accounts exist |
| Discounts section | Shows only if active discounts exist |
| Promo recommendation | Shows only when close to promotion threshold |
| Invoice buttons | One per payment record |
| Reward cards | Show only if rewards have been redeemed |
| Freeze/Cancel buttons | May be conditionally enabled based on membership status |
| Cost formula | Dynamic based on membership type, add-ons, discounts |
| Right sidebar list | Populated from API, filtered by search input in real-time |
| Retention stat colors | Dynamic via RetentionThreshold utility (green/yellow/red) |

---

## STATE VARIATIONS

### Loading
Shimmer placeholders for: profile photo (circle shimmer), text lines (rectangular shimmers), cards (full card-sized shimmer blocks). Right sidebar shows shimmer list items independently.

### Empty
- No payment history → "No payments yet" message in table area
- No linked accounts → hide subsection or show "No linked accounts" with add button
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
| SectionCard | Card wrapper with title | Reused for 3 major cards |
| OutlinedActionButton | Full-width outlined button | Reused ~6 times |
| LinkedAccountChip | Avatar + name chip (tappable) | Reused per linked account |
| RetentionStatItem | Icon + value + label, color from threshold util | Reused 4 times |
| RewardCard | Image + title + subtitle column | Reused per reward |
| PaymentHistoryRow | Name + date + invoice button | Reused per payment |
| MemberListItem | Avatar + name (sidebar) | Reused 12+ times |
| SmallOutlinedButton | Pill-shaped button (Invoice style) | Reused in table |
| StatWithIcon | Icon + primary text + secondary text | Reused in rank section |
| ConfirmationModal | Modal dialog for destructive actions | Reused for Freeze + Cancel |

---

## TEXT OVERFLOW RULES

| Element | Max Lines | Overflow |
|---|---|---|
| Member name | 1 | Ellipsis |
| Membership label | 1 | Ellipsis (wrap on narrow) |
| Address value | 2 | Ellipsis |
| Email values | 1 | Ellipsis |
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
- **Rewards row:** Horizontal scroll if more items than visible (currently 3 fit)
- **Pagination:** Not applicable — all content scrollable inline
- **Cost formula:** Always visible (not expandable/collapsible)

---

## IMAGE LOADING

| Image | Placeholder | Error Fallback | Fit |
|---|---|---|---|
| Profile avatar | Grey circle + person icon | Same person icon | BoxFit.cover |
| Rank badge | Shimmer rectangle | Default rank icon | BoxFit.contain |
| Linked account avatars | Grey circle + person icon | Initials avatar | BoxFit.cover |
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
| Active status | semanticLabel = "Membership status: Active" |
| Invoice buttons | semanticLabel = "View invoice for [payment name] on [date]" |
| Nav items | semanticLabel = "[nav label] navigation" |
| Rank badge image | semanticLabel = "Current rank: Silver (Amateur)" |
| Right sidebar search | semanticLabel = "Search members" |
| Freeze/Cancel buttons | Ensure screen reader announces clearly (destructive) |
| Reading order | Left sidebar → main content (top→bottom, left col→right col) → right sidebar |

---

## RESPONSIVE BEHAVIOR

| Breakpoint | Layout |
|---|---|
| Desktop (wide) | Three-panel: left sidebar + two-column main content + right sidebar |
| iPad / Tablet | Three-panel but main content **stacks to single column** (left col content above right col content) |
| Left sidebar | Can be set to **50% opacity** (still visible, not collapsed/hidden) |
| Right sidebar | **Always visible** at all breakpoints |

---

## RESOLVED DECISIONS

These were originally open questions, now confirmed:

1. **Right sidebar:** Always visible, never hidden
2. **Two-column layout on iPad:** Stacks to single column
3. **Payment History table:** Scrollable within fixed-height container
4. **Linked account chips:** Tappable — navigate to that member's detail page
5. **Freeze/Cancel Membership:** Opens modal confirmation dialog
6. **Cancel Membership styling:** Standard outlined style (no special destructive/red treatment confirmed)
7. **Reward cards:** NOT tappable
8. **Search field filtering:** Real-time as user types
9. **Left sidebar collapse:** Set to 50% opacity (not hidden)
10. **Main content scroll:** Full page scroll — user can scroll through everything
11. **Cost formula:** Always visible
12. **Icon set:** Mix of Material icons and custom SVGs
13. **"Recommend Promo":** Informational only, not tappable
14. **Retention colors:** Green/Yellow/Red via a shared utility file with constants for each threshold range. Colors defined in the constants file. Reusable across multiple screens.
