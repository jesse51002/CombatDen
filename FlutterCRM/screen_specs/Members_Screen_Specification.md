# Members Screen — Implementation Specification

---

## SCREEN: Members List

**DEVICE CONTEXT:** Desktop / Web application, landscape orientation, dark theme

---

## WIDGET TREE

```
└── Row (root)
    ├── SideNavigationRail (fixed width, vertically scrollable if items overflow)
    │   ├── Logo ("COMBAT DEN")
    │   ├── NavItem("Add New Member", icon: personAdd, highlighted: primaryColor)
    │   ├── NavItem("Dashboard", icon: dashboard)
    │   ├── NavItem("Members", icon: group, ACTIVE)
    │   ├── NavItem("Growth", icon: trendingUp)
    │   ├── NavItem("Schedule", icon: calendarToday)
    │   ├── NavItem("Memberships", icon: label)
    │   ├── NavItem("Member App", icon: bolt)
    │   ├── NavItem("Employees", icon: badgeOutlined)
    │   ├── NavItem("Sign up QR Codes", icon: qrCode)
    │   └── NavItem("Settings", icon: settings)
    └── Expanded (main content area — horizontally scrollable on narrow viewports)
        └── SingleChildScrollView (horizontal, enabled when viewport is too narrow)
            └── Column
                ├── PageHeader
                │   ├── Text("Members") — title
                │   └── Text("85 active members, 6 trial members, 3 frozen members") — subtitle
                ├── ToolbarRow
                │   ├── SearchField (icon + placeholder "search name....")
                │   ├── ViewSwitcher
                │   │   ├── ViewButton("All", SELECTED — default)
                │   │   ├── ViewButton("Promotions")
                │   │   ├── ViewButton("Trial")
                │   │   ├── ViewButton("Frozen")
                │   │   └── ViewButton("Cancelled")
                │   └── OutlinedButton("Add New Member", primaryColor border)
                ├── FilterBar
                │   ├── AddFilterButton("Add Filter +")  — always visible
                │   └── ActiveFilterChips (0..n, shown when filters are applied)
                │       └── FilterChip("Status: Frozen" ✕) — removable
                └── AppDataTable (columns + cells change based on active view + filters)
                    ├── [All view]:         Name, Contact, Membership, Rank, Last Class
                    ├── [Promotions view]:  Name, Rank, Time In Rank, Classes Until Promotion, Manage
                    ├── [Trial view]:       Name, Days Remaining, Start Date, End Date
                    ├── [Frozen view]:      Name, Freeze Start, Duration, Freeze End, Price
                    └── [Cancelled view]:   Name, Cancel Date, Duration, Price
```

**Responsive note:** The layout does NOT change at different breakpoints — no collapsing nav or reflow. On narrow viewports, the main content area becomes horizontally scrollable. The SideNavigationRail also scrolls vertically if items exceed available height, and on very thin screens the entire Row scrolls horizontally.

---

## COMPONENT SPECIFICATIONS

### 1. SideNavigationRail

- **Type:** Container → SingleChildScrollView(vertical) → Column
- **Background:** `DesignConstants.cardBackground` (#1A1E22)
- **Width:** Fixed ~100px (add a constant if one doesn't exist, e.g., `sideNavWidth`)
- **Padding:** `DesignConstants.paddingSmall` (16) vertical top/bottom
- **Alignment:** CrossAxisAlignment.center
- **Scroll:** Vertically scrollable when nav items exceed available height. On very thin screens, the entire root Row scrolls horizontally.
- **Children:**
  - Logo: Text "COMBAT DEN" in bold uppercase, `DesignConstants.big2` (w600, 32px), color `DesignConstants.text`
  - Navigation items arranged vertically with `DesignConstants.spacingSmall` (4) gap

### 2. NavItem (Reusable Widget)

- **Type:** InkWell → Column(icon, label)
- **Icon size:** 24 (standard Flutter icon size)
- **Label:** `DesignConstants.pSmall` (w400, 11px)
- **Color (default):** `DesignConstants.text3rd` (text at 50% opacity)
- **Color (active — "Members"):** `DesignConstants.text` (#F4F3EE)
- **Color (highlighted — "Add New Member"):** `DesignConstants.primaryColor` (#FF6C2D)
- **Padding:** `DesignConstants.spacingMedium` (8) vertical
- **Tap target:** Minimum 48px (Flutter accessibility minimum)

### 3. PageHeader

- **Type:** Column (crossAxisAlignment: start)
- **Padding:** `DesignConstants.screenHorizontalPadding` (16) left, `DesignConstants.spacingBig` (32) top
- **Title:** Text "Members"
  - Style: `DesignConstants.h1` (w700, 24px, Jura)
  - Color: `DesignConstants.text`
- **Subtitle:** Text "{active} active members, {trial} trial members, {frozen} frozen members"
  - Style: `DesignConstants.h2Regular` (w400, 16px)
  - Color: `DesignConstants.text2nd` (text at 75% opacity)
  - **Counts come from `total_counts` in the API response — always totals, not affected by view or filters**
- **Gap between title and subtitle:** `DesignConstants.spacingSmall` (4)

### 4. ToolbarRow

- **Type:** Row (mainAxisAlignment: spaceBetween, crossAxisAlignment: center)
- **Padding:** `DesignConstants.screenHorizontalPadding` (16) horizontal, `DesignConstants.spacingBig` (32) top, `DesignConstants.spacingLarge` (16) bottom
- **Children:** SearchField, ViewSwitcher, AddNewMemberButton

### 5. SearchField

- **Type:** TextField inside Container
- **Background:** `DesignConstants.card` (text at 10% opacity)
- **Border Radius:** `DesignConstants.radiusSmall` (16)
- **Border:** 1px `DesignConstants.buttonStroke` (#2A2E32)
- **Prefix Icon:** Icons.search, color: `DesignConstants.text3rd`
- **Placeholder Text:** "search name...."
  - Style: `DesignConstants.h3` (w600, 13px) — with color override to `DesignConstants.text3rd`
  - **Behavior:** Client-side filtering against the already-loaded member list. No API calls on keystroke.
- **Width:** ~35% of content area
- **Padding:** `DesignConstants.spacingLarge` (16) horizontal, `DesignConstants.spacingMedium` (8) vertical

### 6. ViewSwitcher (Reusable Widget)

These are **view buttons**, not just filters. Selecting a view changes both the visible data subset AND the columns/cell widgets rendered in the AppDataTable.

- **Type:** ChoiceChip / InkWell → Container
- **Border Radius:** `DesignConstants.radiusBig` (32)
- **Border:** 1px `DesignConstants.buttonStroke` (#2A2E32)
- **Background (default):** Transparent
- **Background (selected):** `DesignConstants.card` (text at 10% opacity)
- **Text Style:** `DesignConstants.p` (w400, 12px)
- **Text Color (default):** `DesignConstants.text2nd`
- **Text Color (selected):** `DesignConstants.text`
- **Padding:** `DesignConstants.spacingLarge` (16) horizontal, `DesignConstants.spacingMedium` (8) vertical
- **Gap between buttons:** `DesignConstants.spacingMedium` (8)
- **Values:** "All" (default), "Promotions", "Trial", "Frozen", "Cancelled"
- **Behavior:** Selecting a view:
  1. Filters the member list to the relevant subset (All shows everyone)
  2. Swaps the AppDataTable column definitions and cell widgets to match the view
  3. Search still works client-side within the active view's filtered data

### 7. AddNewMemberButton

- **Type:** OutlinedButton
- **Border:** `DesignConstants.primaryColor` (#FF6C2D), width `DesignConstants.buttonBorderSize` (3)
- **Border Radius:** `DesignConstants.radiusBig` (32)
- **Background:** Transparent
- **Text:** "Add New Member"
  - Style: `DesignConstants.h3` (w600, 13px)
  - Color: `DesignConstants.primaryColor`
- **Padding:** `DesignConstants.paddingSmall` (16) horizontal, `DesignConstants.spacingMedium` (8) vertical

### 8. FilterBar

The FilterBar sits between the toolbar and the table. It allows users to add granular filters that further narrow the data within the active view.

#### Layout

- **Type:** Wrap widget, centered horizontally
- **Alignment:** WrapAlignment.center
- **Padding:** `DesignConstants.spacingMedium` (8) vertical
- **Gap between items:** `DesignConstants.spacingMedium` (8)
- **Overflow:** Wraps to multiple lines when many filters are active (no horizontal scroll)

#### AddFilterButton

- **Type:** OutlinedButton (always visible, even when filters are active)
- **Text:** "Add Filter +"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`
- **Border:** 1px `DesignConstants.buttonStroke` (#2A2E32)
- **Border Radius:** `DesignConstants.radiusBig` (32)
- **Background:** Transparent
- **Padding:** `DesignConstants.spacingLarge` (16) horizontal, `DesignConstants.spacingMedium` (8) vertical
- **Tap:** Opens a PopupMenuButton with available filter categories

#### Filter Popup Menu

When "Add Filter +" is tapped, a PopupMenuButton appears with four filter categories:

| Filter Category | Input Type | Persists Across View Switches? |
|---|---|---|
| **Date** | Date range picker | ✅ Yes |
| **Membership Status** | Single-select: Trial, Active, Frozen, Cancelled | ❌ No — resets to match the view |
| **Payment Status** | Single-select or multi-select: Paid, Missed | ❌ No — resets to match the view |
| **Rank** | Multi-select from database rank list | ✅ Yes |

When switching views, **Date** and **Rank** filters persist. **Membership Status** and **Payment Status** filters reset to whatever the target view requires (e.g., switching to Frozen view auto-sets "Membership Status: Frozen").

#### ActiveFilterChip (shown when a filter is applied)

- **Type:** Container (pill shape) with remove button
- **Border Radius:** `DesignConstants.radiusBig` (32)
- **Background:** `DesignConstants.card` (text at 10% opacity)
- **Border:** 1px `DesignConstants.buttonStroke`
- **Text:** Filter description, e.g., "Status: Frozen", "Rank: Gold", "Date: Jan–Mar 2025"
  - Style: `DesignConstants.pSmall` (w400, 11px)
  - Color: `DesignConstants.text`
- **Remove icon:** Small `Icons.close` at trailing edge
  - Size: 14px
  - Color: `DesignConstants.text3rd`
  - Tap: Removes this filter, re-evaluates smart view switching
- **Padding:** `DesignConstants.spacingLarge` (16) left, `DesignConstants.spacingMedium` (8) right (tighter on right to fit close icon), `DesignConstants.spacingSmall` (4) vertical
- **No max limit** on number of active filters
- **All filter chips are regular chips** — including auto-added status chips. No special locked/dimmed appearance.

#### Smart View Switching Logic

The logic is simple:

**Rule: If there is exactly ONE membership status filter, switch to that view. Otherwise, use the default (All) view. Don't try to infer.**

Concretely:

1. User adds **Membership Status: Trial** (and no other status filters) → switch to **Trial view**
2. User adds **Membership Status: Frozen** (and no other status filters) → switch to **Frozen view**
3. User adds **Membership Status: Cancelled** (and no other status filters) → switch to **Cancelled view**
4. User has **multiple status filters** (e.g., Trial + Frozen) → stay on **All view**
5. User has **no status filter** → stay on **All view**
6. User **removes** a status filter chip that was the only status filter → view switches back (e.g., removing "Status: Frozen" while on Frozen view → switch to All view)
7. Non-status filters (Date, Rank, Payment Status) **never** trigger a view switch

**View → Filter direction:**
1. When user manually taps a ViewSwitcher button (e.g., Frozen) → auto-add "Status: Frozen" filter chip + reset Payment Status filter + keep Date and Rank filters
2. When user taps All → clear status filter chip + clear Payment Status filter + keep Date and Rank filters
3. When user taps Promotions → clear status filter chip + clear Payment Status filter + keep Date and Rank filters

**That's it.** Edge cases will be handled as they come up — keep it simple for now.

### 9. AppDataTable (Reusable Widget — used across many screens)

This is a **generic, reusable table widget** that will be used on the Members screen and many other screens in the app.

#### API / Constructor

```
AppDataTableColumn(
  label: String,                     // header text
  minWidth: double?,                 // minimum column width in logical pixels
  maxWidth: double?,                 // maximum column width in logical pixels
  fill: bool,                       // if true, column expands to fill remaining space
)

AppDataTableRow(
  cells: List<Widget>,               // one widget per column — must match columns.length
  onTap: Function()?,                // row-level tap handler
)

AppDataTable(
  columns: List<AppDataTableColumn>, // column definitions
  rows: List<AppDataTableRow>,       // row data
  rowDividerColor: Color,            // defaults to DesignConstants.divider
  headerTextStyle: TextStyle,        // defaults to DesignConstants.pSmall
  headerTextColor: Color,            // defaults to DesignConstants.text3rd
  infiniteScroll: bool,              // enable scroll-to-load-more
  onLoadMore: Function()?,           // called when scroll nears bottom
  stickyHeader: bool,               // pin header row while scrolling (default: true)
)
```

#### Column Width Logic

Each column has three optional width properties: `minWidth`, `maxWidth`, and `fill`.

- **`fill: true`** — Column takes up all remaining horizontal space after non-fill columns are sized. If multiple columns have `fill: true`, they split remaining space equally.
- **`fill: false` (default)** — Column is sized to its `minWidth`. If no `minWidth`, it sizes to content.
- **`minWidth`** — Column will never be narrower than this value.
- **`maxWidth`** — Column will never be wider than this value.
- Columns with `fill: true` still respect `minWidth` and `maxWidth` constraints.

#### Behavior Rules

1. **Column count:** Defined by `columns.length`. Every row's `cells.length` must match.
2. **Header row:** Renders each column's `label` string. Styled with `headerTextStyle` and `headerTextColor`. Headers are NOT tappable (no sorting). Sticky by default.
3. **Row layout (vertical rhythm):**
   ```
   content (30px)
   ↕ DesignConstants.spacingLarge (16px)
   ── divider ──
   ↕ DesignConstants.spacingLarge (16px)
   content (30px)
   ↕ DesignConstants.spacingLarge (16px)
   ── divider ──
   ↕ DesignConstants.spacingLarge (16px)
   content (30px)
   ... repeats
   ```
   - **Content height** is a fixed `DesignConstants.tableRowHeight` (30px).
   - **16px padding** (`DesignConstants.spacingLarge`) between the content and the divider on both sides.
   - Total per row slot = 30 + 16 + 2 (divider) + 16 = **64px**.
4. **Horizontal padding:** Normalized — `DesignConstants.screenHorizontalPadding` (16) applied uniformly to the table's left and right edges. Not configurable per-row.
5. **Widget sizing within cells:**
   - **Non-text widgets** (images, badges, icons, containers): **stretch to fill the 30px content height**. Use SizedBox.expand or constrain height to `DesignConstants.tableRowHeight`.
   - **Text widgets**: Use whatever size is specified by their TextStyle constant. **No auto-sizing.** Text is vertically centered within the 30px content area.
6. **Row divider:** 2px thick line between rows using `DesignConstants.divider`. Sits centered between two 16px padding zones — it does NOT eat into the content height.
7. **Row tap:** If `onTap` is provided on AppDataTableRow, the row is wrapped in InkWell. Individual cell widgets can have their own gesture detectors that stop propagation (e.g., the copy icon).
8. **Infinite scroll:** When `infiniteScroll: true`, uses a ScrollController that calls `onLoadMore` at ~80% scroll. `onLoadMore` increments `start_index` and makes an API call with the current `view`, `filters`, `start_index`, and `count`. Appends response rows to the existing list.
9. **Scroll physics:** ClampingScrollPhysics.

---

### 10. View Configurations

Each view button swaps the AppDataTable's column definitions and cell widgets **(frontend)**, and triggers a new API call with the updated `view` enum **(backend handles filtering, sorting, formatting)**. All views share `stickyHeader: true`, `infiniteScroll: true`, and row tap → navigate to member detail.

---

#### 10a. "All" View (Default)

**Backend:** Returns all members, pre-sorted by status priority (Trial → Active → Frozen → Cancelled), then date joined ascending. Pre-formatted fields: contact, membership status text, rank, last class time-ago.
**Frontend:** Renders with these columns and cells:

```
columns: [
  AppDataTableColumn(label: "Name",       minWidth: 150, fill: true),
  AppDataTableColumn(label: "Contact",    minWidth: 200, fill: true),
  AppDataTableColumn(label: "Membership", minWidth: 220, fill: true),
  AppDataTableColumn(label: "Rank",       minWidth: 120),
  AppDataTableColumn(label: "Last Class", minWidth: 120),
]
cells: [NameCell, ContactCell, MembershipBadge, RankBadge, LastClassIndicator]
```

---

#### 10b. "Promotions" View

**Backend:** Returns all members, pre-sorted by classes remaining ascending. Pre-formatted fields: rank, time in rank, classes until promotion.
**Frontend:** Renders with these columns and cells:

```
columns: [
  AppDataTableColumn(label: "Name",                      minWidth: 150, fill: true),
  AppDataTableColumn(label: "Rank",                      minWidth: 120),
  AppDataTableColumn(label: "Time In Rank",              minWidth: 120),
  AppDataTableColumn(label: "Classes Until Promotion",   minWidth: 180),
  AppDataTableColumn(label: "",                          minWidth: 100),  // Manage button column (no label)
]
cells: [NameCell, RankBadge, TimeInRankCell, ClassesUntilPromotionCell, ManageRankButton]
```

---

#### 10c. "Trial" View

**Backend:** Returns only trial members, pre-sorted by days remaining descending. Pre-formatted fields: days remaining, trial start date, trial end date.
**Frontend:** Renders with these columns and cells:

```
columns: [
  AppDataTableColumn(label: "Name",              minWidth: 150, fill: true),
  AppDataTableColumn(label: "Days Remaining",    minWidth: 140),
  AppDataTableColumn(label: "Trial Start Date",  minWidth: 140),
  AppDataTableColumn(label: "Trial End Date",    minWidth: 140),
]
cells: [NameCell, TrialDaysRemainingCell, TrialStartDateCell, TrialEndDateCell]
```

---

#### 10d. "Frozen" View

**Backend:** Returns only frozen members, pre-sorted by days frozen ascending. Pre-formatted fields: freeze start date, freeze duration, freeze end date, membership price.
**Frontend:** Renders with these columns and cells:

```
columns: [
  AppDataTableColumn(label: "Name",             minWidth: 150, fill: true),
  AppDataTableColumn(label: "Freeze Start",     minWidth: 140),
  AppDataTableColumn(label: "Freeze Duration",  minWidth: 140),
  AppDataTableColumn(label: "Freeze End",       minWidth: 140),
  AppDataTableColumn(label: "Price",            minWidth: 120),
]
cells: [NameCell, FreezeStartDateCell, FreezeDurationCell, FreezeEndDateCell, MembershipPriceCell]
```

---

#### 10e. "Cancelled" View

**Backend:** Returns only cancelled members, pre-sorted by days since cancelled ascending. Pre-formatted fields: cancel date, membership duration, membership price.
**Frontend:** Renders with these columns and cells:

```
columns: [
  AppDataTableColumn(label: "Name",                minWidth: 150, fill: true),
  AppDataTableColumn(label: "Cancel Date",         minWidth: 140),
  AppDataTableColumn(label: "Membership Duration", minWidth: 160),
  AppDataTableColumn(label: "Price",               minWidth: 120),
]
cells: [NameCell, CancelDateCell, MembershipDurationCell, MembershipPriceCell]
```

---

### 11. Shared Cell Widgets (used across multiple views)

#### NameCell

- **Type:** Row (crossAxisAlignment: center)
- **Used in:** All views
- **Children:**
  - CircleAvatar
    - **Fills the 30px row height** (no separate size constant — constrained by `DesignConstants.tableRowHeight`)
    - ClipOval with BoxFit.cover
    - Image: NetworkImage (member profile photo from API)
  - SizedBox(width: `DesignConstants.spacingMedium` — 8)
  - Text(memberName)
    - Style: `DesignConstants.h3` (w600, 13px)
    - Color: `DesignConstants.text`

#### RankBadge

- **Type:** Row (crossAxisAlignment: center)
- **Used in:** All view, Promotions view
- **Children:**
  - Rank icon/image: loaded from database rank specification (icon URL or asset key per rank)
    - Size: 20px
    - Image: NetworkImage or mapped local asset based on rank data from DB
  - SizedBox(width: `DesignConstants.spacingSmall` — 4)
  - Text(rankLabel) — e.g., "Silver", "Gold", "Bronze" (labels come from DB)
    - Style: `DesignConstants.p` (w400, 12px)
    - Color: `DesignConstants.text2nd`
- **Rank data is database-driven:** Do not hardcode rank tiers. Fetch available ranks from API/DB.

#### MembershipPriceCell

- **Type:** Text
- **Used in:** Frozen view, Cancelled view
- **Content:** e.g., "$165/month"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

---

### 12. "All" View Cell Widgets

#### ContactCell

- **Type:** Row (crossAxisAlignment: center)
- **Children:**
  - Text(email) — e.g., "lillymthree@gmail.com"
    - Style: `DesignConstants.p` (w400, 12px)
    - Color: `DesignConstants.text2nd`
  - SizedBox(width: `DesignConstants.spacingSmall` — 4)
  - IconButton(Icons.content_copy)
    - Size: 16px icon inside 32px tap target
    - Color: `DesignConstants.text3rd`
    - Tooltip: "Copy email"
    - **Always visible** (not hover-dependent)
    - **Gesture:** Stops propagation — copies email to clipboard, shows snackbar, does NOT trigger row navigation.

#### MembershipBadge

- **Type:** Container (pill shape)
- **Border Radius:** `DesignConstants.radiusBig` (32)
- **Padding:** `DesignConstants.spacingLarge` (16) horizontal, `DesignConstants.spacingSmall` (4) vertical
- **Text Style:** `DesignConstants.pSmall` (w400, 11px)
- **Variants:**

| Status | Background | Text Color | Example Text |
|---|---|---|---|
| Trial | `DesignConstants.greenDark` | `DesignConstants.goodGreen` | "Trial Week (Until 1/23)" |
| Paid/Active | `DesignConstants.greenDark` | `DesignConstants.goodGreen` | "Paid on 1/18 ($165/month)" |
| Missed | `DesignConstants.redDark` | `DesignConstants.badRed` | "Missed on 1/18 ($165/month)" |
| Frozen | `DesignConstants.blueDark` | `DesignConstants.text3rd` | "Frozen (Until 1/28)" |
| Cancelled | `DesignConstants.yellowDark` | `DesignConstants.okYellow` | "Cancelled (On 1/18)" |

> **Note:** "Trail Week" in the mockup is a typo — correct text is "Trial Week".

#### LastClassIndicator

- **Type:** Row (crossAxisAlignment: center)
- **Children:**
  - StatusDot (Container, BoxDecoration circle, 8px)
    - Color:
      - `DesignConstants.goodGreen`: days ≤ `AppConstants.lastClassThresholdRecent`
      - `DesignConstants.okYellow`: days ≤ `AppConstants.lastClassThresholdModerate`
      - `DesignConstants.badRed`: days > `AppConstants.lastClassThresholdModerate`
    - Create `AppConstants.lastClassThresholdRecent` / `lastClassThresholdModerate` if they don't exist (suggested: 5 / 14)
  - SizedBox(width: `DesignConstants.spacingSmall` — 4)
  - Text(timeAgo) — e.g., "3 days ago"
    - Style: `DesignConstants.p` (w400, 12px)
    - Color: matches dot color

---

### 13. "Promotions" View Cell Widgets

#### TimeInRankCell

- **Type:** Text
- **Content:** Duration since current rank was assigned. Format: "X days" if < 30 days, otherwise "X months", e.g., "18 days", "3 months"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

#### ClassesUntilPromotionCell

- **Type:** Text
- **Content:** Number of classes remaining before eligible for promotion recommendation, e.g., "12 classes", "3 classes"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: Low numbers (≤3) → `DesignConstants.goodGreen`, otherwise `DesignConstants.text`

#### ManageRankButton

- **Type:** Small OutlinedButton or TextButton
- **Text:** "Manage"
  - Style: `DesignConstants.pSmall` (w400, 11px)
  - Color: `DesignConstants.primaryColor`
- **Border:** 1px `DesignConstants.primaryColor25` (primary at 25%)
- **Border Radius:** `DesignConstants.radiusBig` (32)
- **Gesture:** Stops propagation — navigates to the member detail screen (same as row tap for now; placeholder for future rank management flow).

---

### 14. "Trial" View Cell Widgets

#### TrialDaysRemainingCell

- **Type:** Text
- **Content:** Number of days remaining in trial, e.g., "5 days", "1 day"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text`

#### TrialStartDateCell

- **Type:** Text
- **Content:** Date trial began, e.g., "Jan, 16. 2025"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

#### TrialEndDateCell

- **Type:** Text
- **Content:** Date trial ends, e.g., "Jan, 23. 2025"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

---

### 15. "Frozen" View Cell Widgets

#### FreezeStartDateCell

- **Type:** Text
- **Content:** Date freeze started, e.g., "Jan, 10. 2025"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

#### FreezeDurationCell

- **Type:** Text
- **Content:** How long the freeze has been / will be active. Format: "X days" if < 30 days, otherwise "X months", e.g., "18 days", "2 months"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

#### FreezeEndDateCell

- **Type:** Text
- **Content:** Date freeze ends, e.g., "Jan, 28. 2025"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

---

### 16. "Cancelled" View Cell Widgets

#### CancelDateCell

- **Type:** Text
- **Content:** Date membership was cancelled, e.g., "Jan, 18. 2025"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

#### MembershipDurationCell

- **Type:** Text
- **Content:** How long they were a member. Format: "X days" if < 30 days, otherwise "X months", e.g., "22 days", "8 months"
  - Style: `DesignConstants.p` (w400, 12px)
  - Color: `DesignConstants.text2nd`

---

## BACKEND / FRONTEND RESPONSIBILITIES

### API Contract

The backend provides a single endpoint that the frontend calls whenever the view, filters, or pagination changes.

**Request parameters:**
| Parameter | Type | Description |
|---|---|---|
| `gym_id` | String | The gym/organization ID |
| `view` | Enum (all, promotions, trial, frozen, cancelled) | Which view is active |
| `filters` | List of filter objects | Active filters (date range, membership status, payment status, rank) |
| `start_index` | Int | Pagination offset for infinite scroll |
| `count` | Int | Number of rows to fetch per page |

**Response:**
| Field | Type | Description |
|---|---|---|
| `view` | Enum | Echoed back (confirms which view was resolved) |
| `filters` | List | Echoed back (confirms applied filters) |
| `data` | List of row objects | Pre-sorted, pre-filtered, pre-formatted rows matching the view's column schema |
| `total_counts` | Object | `{ active: int, trial: int, frozen: int }` — always total counts, not filtered counts |

### What the Backend Handles

| Responsibility | Details |
|---|---|
| **Data filtering** | Applies view-based subset (e.g., only frozen members for Frozen view) + any additional filters (date, status, payment, rank) |
| **Sort order** | Returns rows pre-sorted per view (All: status priority then date joined; Promotions: classes remaining asc; Trial: days remaining desc; Frozen: days frozen asc; Cancelled: days cancelled asc) |
| **Data formatting** | All values come pre-formatted as display strings — dates as "Jan, 18. 2025", durations as "X days" or "X months", prices as "$165/month", etc. |
| **Pagination** | Handles `start_index` + `count` to return the correct page of results |
| **Aggregation** | Computes subtitle total counts (active, trial, frozen) across the full dataset regardless of view/filters |
| **Row schema per view** | Returns different fields per row depending on the view (e.g., All view rows have contact/membership/rank/lastClass; Trial view rows have daysRemaining/startDate/endDate) |

### What the Frontend Handles

| Responsibility | Details |
|---|---|
| **Rendering** | Takes whatever the backend returns and renders it into the correct cell widgets for the active view |
| **Column/cell mapping** | Selects which AppDataTable column definitions and cell widgets to use based on the `view` enum in the response |
| **Name search** | Client-side filtering by name against the currently loaded rows. No API call — just filters the in-memory list |
| **View switching UI** | Manages ViewSwitcher state; sends new API call with updated `view` param on switch |
| **Filter bar UI** | Manages filter chips; sends new API call with updated `filters` on add/remove |
| **Smart view switching** | Evaluates filter state to auto-switch views (exactly 1 membership status filter → switch to that view; otherwise All). This is purely frontend logic. |
| **Filter persistence logic** | On view switch: keeps Date and Rank filters, resets Membership Status and Payment Status. Purely frontend logic. |
| **Infinite scroll trigger** | Detects scroll position (~80%), increments `start_index`, calls API for next page, appends results |
| **Subtitle display** | Reads `total_counts` from response, always shows totals regardless of view/filters |
| **Conditional cell styling** | StatusDot color (goodGreen/okYellow/badRed based on thresholds), ClassesUntilPromotion color (goodGreen if ≤3), MembershipBadge variant colors — all determined frontend-side from data values |
| **All UI states** | Loading shimmer, empty states, error states, search-no-results — all frontend |

### Data Flow

```
User action (switch view / add filter / scroll / search)
    │
    ├── [Name search only] → Filter in-memory list, no API call
    │
    └── [View/filter/scroll change] → API call:
            POST /members
            {
              gym_id: "...",
              view: "frozen",
              filters: [{ type: "rank", value: ["Gold"] }],
              start_index: 0,
              count: 20
            }
            │
            └── Response:
                {
                  view: "frozen",
                  filters: [{ type: "rank", value: ["Gold"] }],
                  total_counts: { active: 85, trial: 6, frozen: 3 },
                  data: [
                    { name: "Sylvia Crivia", avatar_url: "...", freeze_start: "Jan, 10. 2025", ... },
                    ...
                  ]
                }
                │
                └── Frontend renders:
                    - Subtitle from total_counts
                    - AppDataTable with Frozen view columns
                    - Each row mapped to: [NameCell, FreezeStartDateCell, ...]
```

---

## SPACING RELATIONSHIPS

- **Page top padding (above title):** `DesignConstants.spacingBig` (32)
- **Title to subtitle gap:** `DesignConstants.spacingSmall` (4)
- **Subtitle to toolbar gap:** `DesignConstants.spacingBig` (32)
- **Toolbar to FilterBar gap:** `DesignConstants.spacingMedium` (8)
- **FilterBar to AppDataTable gap:** `DesignConstants.spacingLarge` (16)
- **Table header to first row gap:** `DesignConstants.spacingMedium` (8) — handled internally by AppDataTable
- **Row content height:** Fixed `DesignConstants.tableRowHeight` (30) — handled internally by AppDataTable
- **Row padding (content↔divider):** `DesignConstants.spacingLarge` (16) above and below the divider — handled internally by AppDataTable
- **Horizontal page margin (content area):** `DesignConstants.screenHorizontalPadding` (16) left/right
- **SideNav to content area gap:** None (flush edge)
- **Between view buttons:** `DesignConstants.spacingMedium` (8)
- **View button group to Add button:** Flexible spacer (push to right)

---

## DESIGN TOKEN MAPPING

All tokens used in this spec mapped to `DesignConstants`:

### Colors Used
| Purpose | Constant | Value |
|---|---|---|
| Page background | `backgroundColor` | #121619 |
| Side nav / card background | `cardBackground` | #1A1E22 |
| Primary text | `text` | #F4F3EE |
| Secondary text | `text2nd` | text @ 75% |
| Tertiary text / placeholders / icons | `text3rd` | text @ 50% |
| Primary accent (orange) | `primaryColor` | #FF6C2D |
| Input/card surfaces | `card` | text @ 10% |
| Borders / strokes | `buttonStroke` | #2A2E32 |
| Divider line (2px) | `divider` | alias for `text3rd` (text @ 50%) |
| Good / recent status | `goodGreen` | #74F394 |
| Ok / moderate status | `okYellow` | #CCCE44 |
| Bad / stale / missed status | `badRed` | #F94A4D |
| Trial/Paid badge bg | `greenDark` | #0E7A29 @ 25% |
| Missed badge bg | `redDark` | #6D2C22 @ 25% |
| Frozen badge bg | `blueDark` | #425E67 @ 25% |
| Cancelled badge bg | `yellowDark` | #83852F @ 25% |

### Typography Used
| Purpose | Constant | Specs |
|---|---|---|
| Logo | `big2` | Jura, w600, 32px |
| Page title "Members" | `h1` | Jura, w700, 24px |
| Subtitle stats line | `h2Regular` | Jura, w400, 16px |
| Member names, button text, search input | `h3` | Jura, w600, 13px |
| Emails, rank labels, time-ago, view buttons | `p` | Jura, w400, 12px |
| Column headers, badge text, nav labels | `pSmall` | Jura, w400, 11px |

### Spacing Used
| Purpose | Constant | Value |
|---|---|---|
| Tiny gap | `spacingTiny` | 2px |
| Small gap (between icon+text) | `spacingSmall` | 4px |
| Medium gap (between elements) | `spacingMedium` | 8px |
| Large gap (section spacing) | `spacingLarge` | 16px |
| Big gap (major sections) | `spacingBig` | 32px |
| Screen horizontal padding | `screenHorizontalPadding` | 16px |
| Padding (big) | `paddingBig` | 32px |
| Padding (small) | `paddingSmall` | 16px |

### Radius Used
| Purpose | Constant | Value |
|---|---|---|
| Pill shapes (chips, badges, buttons) | `radiusBig` | 32px |
| Input fields, cards | `radiusSmall` | 16px |

### Constants to ADD (not in DesignConstants yet)
| Constant | Suggested Value | Purpose |
|---|---|---|
| `AppConstants.lastClassThresholdRecent` | 5 (int) | Max days for green status dot |
| `AppConstants.lastClassThresholdModerate` | 14 (int) | Max days for amber status dot; above → red |
| `DesignConstants.divider` | `DesignConstants.text3rd` (alias) | Divider color — aliased to text3rd for semantic clarity |
| `DesignConstants.sideNavWidth` | 100.0 (double) | Fixed width of side navigation rail |
| `DesignConstants.tableRowHeight` | 30.0 (double) | Fixed content height for AppDataTable rows |

---

## INTERACTIVE ELEMENTS

| Element | Expected Behavior |
|---|---|
| NavItem (any) | Navigate to corresponding screen; update active state highlight |
| "Add New Member" (nav) | Navigate to Add New Member form/screen |
| "Add New Member" (button) | Navigate to Add New Member form/screen (same destination) |
| SearchField | Client-side name filter against in-memory rows. **No API call.** This is the only filter that doesn't hit the backend. |
| ViewSwitcher ("All") | Switch to All view; clear Membership Status and Payment Status filters; keep Date and Rank; **triggers API call** |
| ViewSwitcher ("Promotions") | Switch to Promotions view; clear Membership Status and Payment Status filters; keep Date and Rank; **triggers API call** |
| ViewSwitcher ("Trial") | Switch to Trial view; auto-add "Status: Trial" filter chip; reset Payment Status; keep Date and Rank; **triggers API call** |
| ViewSwitcher ("Frozen") | Switch to Frozen view; auto-add "Status: Frozen" filter chip; reset Payment Status; keep Date and Rank; **triggers API call** |
| ViewSwitcher ("Cancelled") | Switch to Cancelled view; auto-add "Status: Cancelled" filter chip; reset Payment Status; keep Date and Rank; **triggers API call** |
| AddFilterButton ("Add Filter +") | Opens PopupMenuButton with four categories: Date, Membership Status, Payment Status, Rank. Configuring a value **triggers API call** with updated filters. |
| ActiveFilterChip (remove ✕) | Removes the filter, **triggers API call**. If removing a membership status filter leaves exactly 0 or 2+ status filters → smart switch re-evaluates (likely returns to All view). |
| Copy icon (All view) | Copy email to clipboard; show snackbar. Stops propagation — does NOT navigate. |
| ManageRankButton (Promotions view) | Navigates to member detail screen (same as row tap for now). Stops propagation. |
| AppDataTable row (entire row) | Navigate to member detail/profile screen via `onTap`. Buttons with stop propagation (copy icon, manage rank) override this. |

---

## ASSETS NEEDED

| Asset | Source |
|---|---|
| Logo "COMBAT DEN" | Local text or local SVG/PNG logo asset |
| Nav icons (10 items) | Flutter Material Icons or custom icon font |
| Member profile photos | API-loaded (NetworkImage via member object) |
| Rank icons | Database-driven: rank specifications (names, icon URLs/asset keys) stored in DB. Mockup shows Silver, Gold, Bronze as examples — do not hardcode. |
| Copy icon | Flutter Material: `Icons.content_copy` |
| Search icon | Flutter Material: `Icons.search` |

---

## CONDITIONAL LOGIC

### Frontend Logic

| Element | Condition |
|---|---|
| Active view | **FE** — Determined by ViewSwitcher tap OR smart filter-view sync (exactly 1 membership status filter → switch to that view, otherwise All). |
| AppDataTable columns + cells | **FE** — Swapped entirely based on active view (see View Configurations above). |
| Name search | **FE** — Client-side filter against in-memory rows. No API call. |
| Filter categories | **FE** — Four categories always available: Date, Membership Status, Payment Status, Rank. |
| Filter persistence on view switch | **FE** — Date and Rank persist. Membership Status and Payment Status reset to match the target view. |
| Smart view switch | **FE** — Exactly 1 membership status filter → switch to that view. Multiple or none → All view. |
| MembershipBadge variant colors | **FE** — Selects background/text color based on `membershipStatus` value from API data. |
| StatusDot color | **FE** — Compares `daysSinceLastClass` from API against `AppConstants.lastClassThresholdRecent` / `lastClassThresholdModerate` to pick goodGreen / okYellow / badRed. |
| ClassesUntilPromotionCell color | **FE** — ≤3 classes → `DesignConstants.goodGreen`, otherwise `DesignConstants.text`. |
| Copy icon visibility | **FE** — Always visible, only present in All view. |
| Subtitle stats | **FE** — Reads `total_counts` from API response. Always shows totals regardless of view/filters. |
| Infinite scroll trigger | **FE** — Detects ~80% scroll, increments `start_index`, calls API for next page. |

### Backend Logic

| Element | Condition |
|---|---|
| Data subset / filtering | **BE** — Applies view-based subset + filter parameters. Frontend never filters data (except name search). |
| Sort order | **BE** — Returns rows pre-sorted per view. Frontend renders in received order, never re-sorts. |
| Data formatting | **BE** — All display values come pre-formatted (dates as "Jan, 18. 2025", durations as "X days"/"X months", prices as "$165/month"). |
| Pagination | **BE** — Handles `start_index` + `count`. Returns the correct page slice. |
| Total counts | **BE** — Computes subtitle counts (active, trial, frozen) across full dataset, unaffected by view/filters. |
| Rank data | **BE** — Rank specs (names, icons, tiers) stored in database, returned with each row. |
| MembershipBadge text content | **BE** — Pre-formatted string including date and price (e.g., "Paid on 1/18 ($165/month)"). |

---

## STATE VARIATIONS

### Loading State
- Page title and subtitle: show skeleton/shimmer placeholders (2 text blocks)
- Toolbar: search field visible but disabled; view buttons visible but disabled; "Add New Member" button visible
- FilterBar: "Add Filter +" button visible but disabled
- Table headers: visible (matching active view's columns)
- Table body: show 6–8 shimmer skeleton rows matching active view's column layout

### Empty State
- Title and subtitle still visible with "0 active members, 0 trial members, 0 frozen members"
- Table area: centered illustration + text "No members yet" + prominent "Add New Member" CTA button
- Search field remains visible

### Error State
- Title and subtitle area: may show cached counts or "—"
- Table area: centered error icon + text "Failed to load members" + "Retry" button
- Toolbar remains interactive

### View-Specific Empty State
- When a view has no matching members (e.g., no frozen members): show "No [frozen/trial/cancelled] members" message in table area
- When search within a view returns no results: show "No members match your search" message
- Other UI elements (toolbar, header) remain unchanged

---

## COMPONENT EXTRACTION

| Widget Name | Contents | Reason |
|---|---|---|
| `AppDataTable` | Generic table: columns, header, row rendering, infinite scroll, sticky header, row tap | **Reused across many screens.** Core reusable table component. |
| `SideNavigationRail` | Logo + list of NavItems | Used on every screen in the app |
| `NavItem` | Icon + label + active/highlight state | Repeated 10 times in nav |
| `ViewSwitcher` | Row of view buttons with single-select logic, triggers column/data swap + filter sync | Reusable view-switching control; may appear on other list screens |
| `FilterBar` | "Add Filter +" button + active filter chips (Wrap layout) | Reusable — any list screen could use filter bar with different filter categories |
| `ActiveFilterChip` | Pill with label + remove ✕ button | Reusable within FilterBar; generic removable chip |
| `NameCell` | Avatar + member name | Used in ALL 5 views — the one shared cell across every view |
| `RankBadge` | Rank icon + rank label | Used in All view + Promotions view; reused elsewhere |
| `MembershipBadge` | Pill container + status-colored text | All view; 5 style variants; reused on member detail screen |
| `LastClassIndicator` | Status dot + time-ago text | All view; color logic encapsulated |
| `ContactCell` | Email text + copy button with stop propagation | All view only |
| `ManageRankButton` | Small button that navigates to member detail; stops propagation | Promotions view only; placeholder for future rank management |
| `MembershipPriceCell` | Price text | Frozen view + Cancelled view |
| `SearchField` | Styled TextField with search icon | Reusable on other search screens |

---

## TEXT OVERFLOW RULES

| Element | Max Lines | Overflow | Constraints |
|---|---|---|---|
| Member name (NameCell) | 1 | Ellipsis | Max width constrained by column |
| Email address (ContactCell) | 1 | Ellipsis | Max width constrained by column |
| Membership badge text | 1 | Ellipsis (clip within badge) | Badge has max width; text should not wrap |
| Rank label | 1 | Ellipsis | Short text; unlikely to overflow |
| Last class text | 1 | Ellipsis | Short text; unlikely to overflow |
| Time in rank | 1 | Ellipsis | Short text |
| Classes until promotion | 1 | Ellipsis | Short text |
| All date cells (trial/freeze/cancel) | 1 | Ellipsis | Formatted date string; unlikely to overflow |
| Duration cells (freeze/membership) | 1 | Ellipsis | Short text |
| Price cell | 1 | Ellipsis | Short text |
| Page title | 1 | None (fixed text) | N/A |
| Page subtitle | 1 | Ellipsis | Could wrap on very narrow viewports |
| Nav item label | 2 | Ellipsis | Narrow width; "Sign up QR Codes" wraps to 2 lines |

---

## SCROLL BEHAVIOR

- **Pull to refresh:** No (desktop web app)
- **Sticky headers:** Yes — handled by AppDataTable's `stickyHeader: true`. The header row (columns change per active view) remains pinned while rows scroll.
- **Infinite scroll:** Yes — handled by AppDataTable's `infiniteScroll: true`. At ~80% scroll, calls `onLoadMore` which makes an API call with incremented `start_index`. Appends new rows to existing list. No page controls.
- **Scroll physics:** ClampingScrollPhysics (desktop — no bounce) — set internally by AppDataTable
- **Scrollable region:** Only the table body rows; the page header and toolbar are outside AppDataTable and remain fixed above

---

## IMAGE LOADING

| Image Element | Placeholder | Error Fallback | Fit |
|---|---|---|---|
| Member profile photo (CircleAvatar) | Shimmer circle or `DesignConstants.card` fill | Default person icon (`Icons.person`) in circle, color `DesignConstants.text3rd` | BoxFit.cover (clipped to circle) |
| Rank icon | Shimmer or transparent | Generic placeholder icon or text-only fallback | BoxFit.contain |

---

## ACCESSIBILITY

| Element | Semantic Label / Note |
|---|---|
| SideNavigationRail | `Semantics(label: "Main navigation")` |
| Each NavItem | `Semantics(label: "[Nav label]", button: true, selected: isActive)` |
| SearchField | `TextField semanticLabel: "Search members by name"` |
| Each ViewSwitcher button | `Semantics(label: "[View name] view", selected: isActive, button: true)` |
| AddNewMemberButton | `Semantics(label: "Add new member", button: true)` |
| AddFilterButton | `Semantics(label: "Add filter", button: true)` |
| Each ActiveFilterChip | `Semantics(label: "[Filter description], remove filter", button: true)` — the remove ✕ should be its own semantic action |
| Table row (All view) | `Semantics(label: "[Name], [email], membership [status], rank [rank], last class [time]")` |
| Table row (other views) | Semantics label should include all visible column values for the active view |
| Copy icon button | `Semantics(label: "Copy email address for [name]", button: true)` |
| ManageRankButton | `Semantics(label: "Manage rank for [name]", button: true)` |
| MembershipBadge | Include full text in semantics (e.g., "Paid on 1/18, $165 per month") |
| StatusDot | Not separately labeled — covered by row semantics |
| Column headers | `Semantics(header: true)` on each header text |
| Reading order | Natural left-to-right, top-to-bottom; nav rail reads first, then main content |

---

## RESOLVED QUESTIONS (from design review)

| # | Question | Resolution |
|---|---|---|
| 1 | "Trail Week" vs "Trial Week" | **Typo.** Correct text is "Trial Week". Fixed in spec. |
| 2 | Copy icon interaction | **Always visible** on all platforms. Not hover-dependent. |
| 3 | Last Class color thresholds | **Define as Flutter constants** (`AppConstants.lastClassThresholdRecent`, `AppConstants.lastClassThresholdModerate`). Create them if they don't exist. |
| 4 | Row tap behavior | **Entire row navigates to member detail screen**, except the copy icon in the Contact cell which copies the email to clipboard (stops event propagation). |
| 5 | Additional rank tiers | **Rank specifications are stored in the database.** Do not hardcode rank tiers — fetch dynamically. |
| 6 | Pagination vs infinite scroll | **Infinite scroll.** Use ScrollController with threshold trigger to load more. |
| 7 | Sort functionality | **No sorting on column headers.** The "All" view has a fixed sort: Trial → Active → Frozen → Cancelled, then by date joined ascending. Filtering/view switching is handled via ViewSwitcher. |
| 8 | Responsive breakpoints | **Layout does not change.** On narrow viewports, the main content area scrolls horizontally. No nav collapse or layout reflow. |
| 9 | Bulk actions | **No.** No row selection or multi-select. |
| 10 | Member count accuracy | **Total counts** computed from the full loaded dataset (not just visible rows). |
| 11 | Search behavior | **Client-side** — filters the already-loaded member list. No API calls on keystroke. |
| 12 | Side nav scroll | **Vertically scrollable** when items overflow. Also scrolls horizontally with the whole layout on very thin screens. |
| 13 | "Missed" status meaning | **Missed payment.** Use existing codebase color constants (`DesignConstants.redDark` bg, `DesignConstants.badRed` text). |

---

## RESOLVED QUESTIONS — View & Filter Design Review

| # | Question | Resolution |
|---|---|---|
| 1 | ClassesUntilPromotionCell color | ≤3 classes → `DesignConstants.goodGreen`. Otherwise `DesignConstants.text` (white). |
| 2 | ManageRankButton destination | **Navigates to member detail screen** (same as row tap). Placeholder for future rank management. |
| 3 | Promotions view sort order | **Classes remaining ascending** (closest to promotion first). |
| 4 | Trial/Frozen/Cancelled sort orders | Trial: **days remaining descending**. Frozen: **days frozen ascending**. Cancelled: **days since cancelled ascending**. |
| 5 | TrialDaysRemainingCell threshold | **No color threshold.** Always white (`DesignConstants.text`). |
| 6 | Date format | **"MMM, dd. yyyy"** — e.g., "Jan, 18. 2025". |
| 7 | Duration format | **"X days"** if < 30 days. **"X months"** if in the months range. |
| 8 | Price format | **"$165/month"** — no space. |
| 9 | Subtitle counts vs active view | **Always show totals.** Not affected by view or filters. |
| 10 | Filter dropdown UI | **PopupMenuButton.** |
| 11 | Filter categories | Four categories: **Date**, **Membership Status**, **Payment Status**, **Rank**. Same categories in all views. |
| 12 | Filter persistence across views | **Date and Rank persist.** Membership Status and Payment Status reset to match the target view. |
| 13 | Auto-added status chip appearance | **Regular filter chip.** No special locked/dimmed appearance. Removing it triggers smart view switch (likely returns to All). |
| 14 | Maximum filters | **No cap.** Unlimited. |
| 15 | Filter bar collapse | **Wrap** to multiple lines. No horizontal scroll. |
