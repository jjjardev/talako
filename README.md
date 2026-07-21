# TalaKo — Sari-Sari Store Price Reference & Credit Manager

**Track prices. Manage utang. Never lose a notebook again.**

TalaKo is an **offline-first** Android app that helps sari-sari store owners solve their two most expensive problems: forgetting prices and losing track of customer credits ("utang"). No internet needed. No account required. Just install and use.

[Download Latest Release](https://github.com/jjjardev/talako/releases) • [Full Documentation](DOCUMENTATION.md)

---

## Why TalaKo?

| Problem | Before | After |
|---------|--------|-------|
| **Guessing prices** | Owner memorizes ~200 items; undercharges ₱3–5 per transaction | Type 3 letters → instant price lookup |
| **Tracking utang** | Notebook + mental math; arithmetic errors cost ₱500–5,000/month | Instant balance, automatic overdue alert |
| **Lost data** | One wet notebook = months of receivables lost | Digital backup in two formats |
| **Slow customer lookup** | Flipping through pages for 2–5 minutes | Search by name, autocomplete |

---

## Features

**First-launch Onboarding**
- 4-page tutorial explains the app's purpose and main screens
- Only appears once; accessible again only if app data is cleared

**Price Reference**
- Searchable, sortable catalog of store items
- Quick lookup in 2 seconds
- Add, edit, delete items with swipe

**Credit (Utang) Management**
- Autocomplete customer and item names
- Auto-fill price from existing items
- Quantity `[-]` `[+]` buttons
- Same-customer mode for rapid multi-item entry
- Partial and full payment with swipe actions
- Pay All button for bulk settlement
- 14-day overdue detection (red highlight + warning icon)

**Backup & Restore**
- **JSON export** — human-readable, shareable via Messenger/email
- **Raw .db export** — exact binary copy
- **Import both formats** with confirmation dialogs

**Settings**
- Dark/Light theme toggle (persisted)
- All backup operations in one place
- View fully paid ("settled") credits

---

## Screenshots (Conceptual)

```
┌─────────────┐   ┌─────────────┐   ┌───────────────────────┐
│ Price Ref   │   │ Credits     │   │ Add Credit            │
├─────────────┤   ├─────────────┤   ├───────────────────────┤
│ Search...   │   │ Search...   │   │ Customer: [Maria___]  │
│             │   │             │   │ Item:     [Coke 1.5L ]│
│ Coke 1.5L   │   │ ⚠ Maria S. │   │ Price:    [₱45.00   ]│
│ ₱45.00     │   │   ₱1,234     │   │ Qty: [-] [2] [+]     │
│ Shampoo sachet│ │ ✓ Juan D.   │   │ Total: ₱90.00        │
│ ₱7.00      │   │   ₱500       │   │ [──── Add Credit ────]│
│             │   │             │   │ Added: 3     [ Done ]│
└─────────────┘   └─────────────┘   └───────────────────────┘
```

---

## How to Use

1. **Install** — download `app-release.apk` and install on your Android phone
2. **First launch** — a 4-page onboarding explains the app's screens. Swipe through or tap Skip.
3. **Add items** — tap the (+) icon on the Prices tab, enter name and price
4. **Add a credit** — tap the (+) FAB, type customer name and item, set quantity
5. **Track payments** — tap a customer to see their balance, swipe to pay
6. **Back up your data** — go to Settings, export backup (do this regularly!)

---

## Target User

TalaKo is built for:
- **Sari-sari store owners** who sell on credit to regular customers
- **Tricycle operators** tracking daily boundary payments from drivers
- **Rice retailers** tracking kilo-based utang
- **Water refilling stations** tracking customer deposits and refills
- **Any micro-business** that extends credit and needs a simple digital ledger

---

## Technical Overview

| Detail | Value |
|--------|-------|
| **Platform** | Android (offline-first) |
| **Framework** | Flutter 3.x (Dart) |
| **Database** | SQLite (sqflite) |
| **State management** | Provider (ChangeNotifier) |
| **APK size** | 49 MB |
| **Min SDK** | Android 5.0 (API 21) |
| **Internet** | Not required |
| **Backup formats** | JSON + raw .db |

---

## Project Structure

```
lib/
├── main.dart                      # App entry point + theme + conditional routing (onboarding vs shell)
├── screens/main_shell.dart        # Bottom nav shell (Prices / Credits tabs, FAB)
├── database/database_helper.dart  # SQLite operations (singleton)
├── models/                        # Data models (Item, Customer, CreditEntry, CustomerSummary)
├── providers/                     # State management (ItemsProvider, CustomersProvider, ThemeProvider)
├── screens/                       # 9 screens (Price, Credit, AddCredit, CustomerDetail, Onboarding, etc.)
├── widgets/                       # Reusable widgets (CustomerTile, CreditTile, ItemTile)
└── utils/                         # Formatters (currency, date — cached)
```

See [DOCUMENTATION.md](DOCUMENTATION.md) for the complete technical specification.

---

## Building from Source

```bash
# Prerequisites: Flutter SDK + JDK 17
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

---

*Built with Flutter. Powered by sqflite. Inspired by the 1.3 million sari-sari store owners of the Philippines.*
