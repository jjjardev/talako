# TalaKo — Offline Credit Management for Small Stores

> **Track debts. Never lose a notebook again.** — Offline-first, no internet, no account.

[![Version](https://img.shields.io/badge/version-2.13.0%2B1-teal)](https://github.com/jjjardev/talako/releases/tag/v2.13.0)
[![Schema](https://img.shields.io/badge/schema-v6-blue)](https://github.com/jjjardev/talako/blob/main/lib/database/database_helper.dart)
[![Tests](https://img.shields.io/badge/tests-32%20passed-brightgreen)](https://github.com/jjjardev/talako/actions)
[![License](https://img.shields.io/badge/license-Apache%202.0-lightgrey)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%205.0%2B-green)]()

**TalaKo** is an **offline-first** Android app for small store owners who sell on credit. No internet needed. No account required. Your data stays on your phone.

[📥 Download Latest APK (v2.13.0)](https://github.com/jjjardev/talako/releases/tag/v2.13.0) • [📖 Full Documentation](DOCUMENTATION.md) • [📋 Changelog](DOCUMENTATION.md#15-changelog-summary) • [💡 Pitch Guide](PITCH.md)

---

## 📑 Table of Contents

- [✨ Features](#-features)
- [🚀 How to Use](#-how-to-use)
- [👥 Target Users](#-target-users)
- [🛠 Technical Overview](#-technical-overview)
- [📁 Project Structure](#-project-structure)
- [🔨 Building from Source](#-building-from-source)

---

## ✨ Features

| Area | Highlights |
|------|------------|
| **🧾 Credit Book** | Swipe right → `Fully paid` with **Undo** · Oldest-first, full item breakdown (`name · qty × price · subtotal`) · Red `14+ days` / Orange `7+ days` / Grey recent · Overdue warning chip · Search by name · Group by customer toggle |
| **➕ Credit Recording** | `+` with multiple items · Autocomplete for customers & items (recent first) · Quantity steppers + inline price, auto total · `Undo` Snackbar after save |
| **💳 Payments** | Numpad (2-decimal, backspace) · Partial payments · Receipt-based (whole transaction) · Full-payment detection + `Undo` to reverse |
| **📦 Stock Watch (Shelf)** | **Macro only — no counting, ever.** `Well Stocked → Running Low → Out of Stock` **tap to cycle** ( `Cold / Archive` is **long-press only**, hidden from Shopping) · Cards show **price** (if Retail/Both), **status `• today / • Nd ago`**, usage icon · Filter chips **with live counts** `All (n) Retail (n) Ingredients (n) Low/Out (n) Cold (n)` · **A–Z / Urgent** sort (choice persists, A–Z strip always visible) · **Long-press → Quick Actions** (set status, `Restocked`, `Archive`) → **Edit details** (rename, price, notes, `Retail / Ingredient / Both` — renaming never rewrites past receipts) · `Tap to cycle` hint + **Undo** |
| **🛒 Shopping List** | Auto-built from `Running Low / Out of Stock` (Out first, then Low) · **Check off** as bought (→ `Well Stocked`) or **`Restock all (n)`** in one tap · **Share** via system sheet — `SHOPPING LIST — MMM dd, yyyy (n items)` per-line `- Name — ₱ price (label)` (count-only, no qty) |
| **🙋 Owner Tools** | `Owner Took Stock` quick log (never sales/debt) · `Personal Use Log` + **Monthly Store Report** (sales, collected, owner use, spoilage, top sellers) · Out-of-stock nudge (`Back in stock` Snackbar after selling OOS) |
| **💾 Backup & Restore** | **JSON** (human-readable) + **Raw .db** (binary) export via share sheet · Import both with confirmation · WAL checkpoint before raw export · Legacy `Sari` v1 `credits` import |
| **⚙️ Settings** | Dark/Light (persisted) · `Settled Debts` · `Monthly Report` · All backup ops · `Onboarding` (6 pages: Welcome, Credit Book, Recording, Stock Watch, Shopping List, Payments & Undo — `Skip` + `Next/Get Started`, stored `onboarding_version=3`) |

<details>
<summary>More details</summary>

- **Credit Book** tiles show overdue color, item table, `Paid: ₱ x of ₱ y` + remaining, green `Pay` button → `PaySheet`.
- **Grouped mode** aggregates per customer (receipt count, oldest date, `paid/total/remaining`), tap to `CustomerDetail` drill-down with per-receipt `Pay` + `Mark all as paid` bulk settle (exact-restore Undo).
- **Stock status** `Cold / Dead` = discontinued/archived — long-press → `Archive (Hidden from Shopping)` — use for items you no longer sell.
- **Shelf add** `+` FAB → `Add Item` (name, price if Retail/Both, usage, **initial Shelf status** `Well/Low/Out` chooser).

</details>

---

## 🚀 How to Use

| Step | Action | Tip |
|------|--------|-----|
| **1. Install** | Download `app-release.apk` from [Releases](https://github.com/jjjardev/talako/releases) → Install | Allow *Install unknown apps* once |
| **2. First launch** | Swipe the 6-page onboarding → `Skip` or `Get Started` | Covers Credit Book, Stock, Shopping, Payments |
| **3. Add items to Shelf** | `Stock` tab → `+` → name, price, `Retail / Ingredient / Both`, initial `Well/Low/Out` | Sort `Urgent` to see `Out` first |
| **4. Add a credit** | `Credit Book` → `+` → customer + items (qty × price) → `Save` → `Undo` if needed | Autocomplete merges recent + catalog names |
| **5. Track debts** | Credit Book shows **overdue total** (`red`) + tiles `Today / Nd ago — MMM dd, yyyy h:mm a (Overdue!)` | Search or toggle **Group by customer** |
| **6. Record payments** | Tap green `Pay` → numpad → `Confirm` → `Undo` | Swipe right → `Fully paid` also has `Undo` |
| **7. Daily Shelf scan** | Every morning: **Tap** cards to cycle `Well→Low→Out→Well` (see `• today` stamp), **long-press** for `Archive` | Badge `Shopping (7)` tells you how many to buy |
| **8. Shop** | `Stock → Shopping` → `Share List` or `Restock all (n)` after market | Shared text includes price per line, no qty |
| **9. Back up** | `Settings` → `Export Backup (JSON)` or `Export Raw Database` → share to Messenger/Drive | Do weekly — fully offline |

> **No internet?** All steps work offline. Backups are plain files you control.

---

## 👥 Target Users

Any micro-business extending credit where a paper notebook is the current system:

- **Sari-sari store owners** (core) — who sell on credit to regulars
- **Any micro-business** — any item & price works: rice retailers (`Rice 1kg`), water stations (`Refill`), tricycle operators (boundary), hardware, etc.
- **Carinderia-style counters** can use Shelf for paninda tracking, but **no profit-per-plate / dish capital features** (removed in `v2.12.0` — Stock is now Shelf + Shopping only)

> If you can type an item name and price, TalaKo works for you.

---

## 🛠 Technical Overview

| Detail | Value |
|--------|-------|
| **Platform** | Android (offline-first) |
| **Framework** | Flutter 3.x (Dart `^3.11.5`) |
| **Database** | SQLite (`sqflite`), **schema v6** (`migrations v1→v6`) |
| **State** | `Provider` (`ChangeNotifier`) — `CustomersProvider`, `TransactionsProvider`, `InventoryProvider`, `ThemeProvider` |
| **APK size** | **~52 MB** (measured `v2.13.0` `assembleRelease`) |
| **Min SDK** | Android 5.0 (API 21) |
| **Internet** | **Not required** — no `INTERNET` permission |
| **Tests** | **32** automated (`database` 9 · `inventory` 12 · `money` 4 · `format` 4 · `snackbars` 3) |
| **License** | Apache 2.0 |

---

## 📁 Project Structure

<details>
<summary>Show tree</summary>

```text
lib/
├── main.dart                      # App entry + prefs preload, providers, routing
├── database/database_helper.dart  # SQLite singleton (schema v6, migrations v1→v6, backup)
├── models/
│   ├── customer.dart
│   ├── customer_summary.dart
│   ├── item.dart                  # price, usageType, stockStatus, notes, lastStatusUpdated/lastRestocked
│   ├── spoilage_entry.dart
│   ├── stock_enums.dart           # UsageType (Retail/Ingredient/Both), StockStatus (Well/Low/Out/Cold) + next()
│   ├── transaction.dart
│   └── transaction_item.dart      # item_name (denormalized), qty, price, subtotal
├── providers/
│   ├── customers_provider.dart    # Minimal: getOrCreate + summaries (legacy)
│   ├── inventory_provider.dart    # Shelf/Shopping, filteredItems/shoppingList, cycle/restock, spoilage, reports
│   ├── theme_provider.dart
│   └── transactions_provider.dart # Book state, item stitching, grouped view, _refreshAfterMutation
├── screens/
│   ├── main_shell.dart            # Bottom nav (Credit Book / Stock / Settings) + segment FAB
│   ├── collections_screen.dart    # Credit Book dashboard (swipe Fully paid, grouped/individual, overdue)
│   ├── stock_home_screen.dart     # Stock host (Shelf | Shopping) — 2 segments + Shopping badge
│   ├── stock_watch_screen.dart    # Shelf grid + A-Z strip + cards (price/stamp) + editor + quick actions
│   ├── shopping_list_screen.dart  # Auto-built list + Restock all + Share (count-only)
│   ├── add_item_sheet.dart        # Add Item (name, price, usage, initial Shelf status)
│   ├── add_credit_sheet.dart      # Multi-item credit entry (autocomplete, OOS nudge)
│   ├── pay_sheet.dart             # Numpad payment sheet
│   ├── customer_detail_screen.dart# Per-customer drill-down + Mark all as paid
│   ├── settled_debts_screen.dart  # Fully-paid history
│   ├── owner_use_sheet.dart       # Owner Took Stock quick log
│   ├── personal_use_log_screen.dart# Owner consumption history
│   ├── settings_screen.dart       # Theme, Settled Debts, Monthly Report, Backup/Restore (JSON + raw .db)
│   └── onboarding_screen.dart     # 6-page first-launch tutorial (onboarding_version=3)
├── widgets/
│   └── alphabet_strip.dart        # A-Z quick-jump strip (tap, not drag)
└── utils/
    ├── money.dart                 # roundMoney, moneyEquals, isFullPayment, clampMoney
    ├── currency_format.dart       # ₱ fil_PH
    ├── date_format.dart           # MMM dd, yyyy
    ├── pay_flow.dart              # Shared pay-with-Undo
    ├── snackbars.dart             # Auto-dismiss watchdog
    └── app_logger.dart

test/
├── database_test.dart             # Receipts, payments, backup round-trip, legacy Sari v1
├── inventory_test.dart            # Migration v3, stock cycle, filtering, isolation, reports
├── money_test.dart
├── format_test.dart
└── snackbars_test.dart
```

</details>

---

## 🔨 Building from Source

```bash
flutter pub get
flutter test        # 32 tests
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk` (~52 MB)

---

*Built with Flutter. Powered by sqflite. Inspired by sari-sari store owners everywhere.*
