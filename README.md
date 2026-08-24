# TalaKo — Offline Credit Management for Small Stores

**Track debts. Sell dishes with one tap. Never lose a notebook again.**

TalaKo is an **offline-first** Android app for small store owners who sell on credit — and for carinderias that want to know their profit per plate. No internet needed. No account required.

[Download Latest Release](https://github.com/jjjardev/talako/releases) • [Full Documentation](DOCUMENTATION.md)

---

## Features

**Credit Book**
- All active debts sorted oldest-first, with full item breakdown (name, qty x unit price, subtotal)
- Color-coded tiles: red = overdue (14+ days), orange = 7+ days, grey = recent
- Overdue warning with total amount in the summary bar
- Search by customer name
- Toggle to group all receipts of the same customer into one aggregated tile

**Credit Recording**
- Tap + to add a new credit with multiple items — including dishes 🍽️
- Autocomplete for customer names, items and dishes
- Quantity steppers, inline price entry, auto-calculated total
- Undo: SnackBar appears after saving — tap Undo to delete the transaction

**Payment Management**
- Numpad keypad for entering payment amounts
- Supports partial payments
- Receipt-based: payments apply to the whole transaction, not individual items
- Undo after paying — reverses the payment instantly

**Menu Inventory** *(for carinderias & food counters)*
- Each dish carries its **Capital** (what the whole dish costs to cook) and **Price per serving** — a recovery bar shows how much of the capital you've earned back
- **One tap = one sale recorded**, with per-tap Undo and a day-reset button for misclicks
- Today strip: total output in pesos, plates served — across cash taps AND dishes sold on credit
- Sold-Nx-today chip, best-seller 🏆 badge, thin-margin warning below 20%
- End-of-Day recap: yesterday's sales per dish, plus leftover handling — reheat tomorrow, reuse as ingredient, or log as waste

**Stock Watch (Shelf)**
- Macro stock statuses: Well Stocked → Running Low → Out of Stock → Cold — tap to cycle. No counting, ever
- Auto badges from sales history: 🔥 Hot · 🌡️ Cooling · 🧊 Cold · 🏷️ New
- A-to-Z quick-jump strip; filter chips; long-press any item for notes, price and usage type (Retail / Ingredient / Both — ingredients don't need a selling price)

**Shopping List**
- Builds itself from Running Low / Out of Stock items, most urgent first
- Check items off as bought (resets to Well Stocked)
- Share via SMS/Messenger so family can do the market run

**Owner Tools**
- "Owner Took Stock" quick log (never counts as sales or debt)
- Personal Use Log + Monthly Store Report (sales, spoilage, top sellers)

**Backup & Restore**
- JSON export — human-readable, shareable via Messenger/email
- Raw .db export — exact binary copy
- Import both formats with confirmation

**Settings**
- Dark/Light theme toggle (persisted)
- View fully paid (settled) debts
- All backup operations in one place

---

## How to Use

1. **Install** — download `app-release.apk` and install on your Android phone
2. **First launch** — a short onboarding explains the app. Swipe through or tap Skip.
3. **Add a credit** — tap the + FAB on the Credit Book, type customer name and items, set quantity and price
4. **Track debts** — the Credit Book shows all active debts with item breakdowns
5. **Record payments** — tap the green Pay button on any tile, enter amount on the numpad
6. **Set up your menu** — Stock tab → Menu → New Dish: add cost and price, then tap a card to record each sale
7. **Shelf scan** — every morning, tap items that changed status; the Shopping List builds itself
8. **Back up regularly** — go to Settings, export a backup

---

## Target Users

- **Sari-sari store owners** who sell on credit to regular customers
- **Carinderia owners** tracking dish sales, capital vs price, and daily profit
- **Tricycle operators** tracking daily boundary payments from drivers
- **Rice retailers** tracking kilo-based credit
- **Water refilling stations** tracking customer deposits and refills
- **Any micro-business** that extends credit and needs a simple digital ledger

---

## Technical Overview

| Detail | Value |
|--------|-------|
| **Platform** | Android (offline-first) |
| **Framework** | Flutter 3.x (Dart) |
| **Database** | SQLite (sqflite), schema v6 |
| **State management** | Provider (ChangeNotifier) |
| **APK size** | ~52 MB |
| **Min SDK** | Android 5.0 (API 21) |
| **Internet** | Not required |
| **Tests** | 40+ automated tests (database, margins, end-of-day, UI logic) |
| **License** | Apache 2.0 |

---

## Project Structure

```
lib/
├── main.dart                      # App entry + providers + routing
├── database/database_helper.dart  # SQLite singleton (schema v6, migrations v1→v6)
├── models/                        # Item, Dish, Transaction, Customer, enums
├── providers/                     # Transactions, Customers, Inventory, Theme
├── screens/
│   ├── main_shell.dart            # Bottom nav (Credit Book / Stock / Settings)
│   ├── collections_screen.dart    # Credit Book dashboard
│   ├── stock_home_screen.dart     # Shelf | Kitchen(Menu) | Shopping List
│   ├── kitchen_screen.dart        # Menu grid + ingredients
│   └── ...                        # PaySheet, AddCredit, Settings, Onboarding
├── widgets/alphabet_strip.dart    # A-Z quick-jump index
└── utils/                         # Money, currency/date formatters, snackbars
```

---

## Building from Source

```bash
flutter pub get
flutter test        # run the test suite
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

---

*Built with Flutter. Powered by sqflite. Inspired by sari-sari store owners everywhere.*
