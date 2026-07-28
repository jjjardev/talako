# TalaKo — Offline Credit Management for Small Stores

**Track debts. Accept payments. Never lose a notebook again.**

TalaKo is an **offline-first** Android app for small store owners who sell on credit. No internet needed. No account required.

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
- Tap + to add a new credit with multiple items
- New items insert at the top; the whole form scrolls when keyboard is open
- Autocomplete for customer names and item names
- Quantity steppers and inline price entry
- Total auto-calculated
- Undo: SnackBar appears after saving — tap Undo to delete the transaction

**Payment Management**
- Numpad keypad for entering payment amounts
- Supports partial payments
- Receipt-based: payments apply to the whole transaction, not individual items
- Undo: SnackBar appears after paying — tap Undo to reverse the payment

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
2. **First launch** — a 4-page onboarding explains the app. Swipe through or tap Skip.
3. **Add a credit** — tap the + FAB, type customer name and items, set quantity and price
4. **Track debts** — the Credit Book shows all active debts with item breakdowns
5. **Record payments** — tap the green Pay button on any tile, enter amount on the numpad
6. **Back up regularly** — go to Settings, export a backup

---

## Target Users

- **Sari-sari store owners** who sell on credit to regular customers
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
| **Database** | SQLite (sqflite) |
| **State management** | Provider (ChangeNotifier) |
| **APK size** | ~50 MB |
| **Min SDK** | Android 5.0 (API 21) |
| **Internet** | Not required |
| **Backup formats** | JSON + raw .db |
| **License** | Apache 2.0 |

---

## Project Structure

```
lib/
├── main.dart                      # App entry + theme + routing
├── screens/main_shell.dart        # Bottom nav (Credit Book / Settings)
├── database/database_helper.dart  # SQLite singleton
├── models/                        # Transaction, TransactionItem, Customer, Item
├── providers/                     # Transactions, Customers, Theme
├── screens/                       # CreditBook, AddCreditSheet, PaySheet, Settings, SettledDebts, Onboarding
└── utils/                         # Currency and date formatters
```

---

## Building from Source

```bash
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

---

*Built with Flutter. Powered by sqflite. Inspired by sari-sari store owners everywhere.*