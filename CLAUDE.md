# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a monorepo with two packages:
- **`navigate_app/`** — Main Flutter application for military navigation training (maps, GPS, participants, routes, scoring). See `navigate_app/CLAUDE.md` for detailed app architecture and conventions.
- **`gps_plus/`** — Local Flutter plugin providing cell-tower-based GPS fallback via trilateration.

## Build & Run Commands

All commands run from `navigate_app/`:

```bash
# Generate Drift (SQLite ORM) code after schema changes
dart run build_runner build --delete-conflicting-outputs

# Static analysis
flutter analyze

# Run the app
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart
```

## Architecture Overview

**Clean Architecture** with four layers:
1. **Domain** (`lib/domain/entities/`) — 18 entity classes, all use Equatable + `toMap()`/`fromMap()`/`copyWith()`
2. **Data** (`lib/data/`) — Drift local DB (17 tables, schema v17) + Firebase remote + 14 repositories
3. **Services** (`lib/services/`) — 12 business logic services (auth, GPS tracking, scoring, route distribution, sync)
4. **Presentation** (`lib/presentation/`) — Screens organized by feature domain

**Dual data layer**: Offline-first with bidirectional sync between Drift (SQLite) and Cloud Firestore via `SyncManager`. Local operations always succeed; sync happens when network is available.

**Key entity relationships**: Unit (hierarchical, absorbed former Framework class) → NavigationTree (with SubFrameworks) → Navigation (flows through 8 statuses: preparation → ready → learning → system_check → waiting → active → approval → review)

## Critical Import Patterns

```dart
import 'package:drift/drift.dart' hide Query;           // Drift+Firestore Query conflict
import 'package:firebase_auth/firebase_auth.dart' hide User;  // Firebase+app User conflict
```

## Language & UI

The app UI is entirely in Hebrew (RTL). Screen names, comments, and documentation are in Hebrew. Firebase project: `navigate-native`.

## Version Constraints

- `connectivity_plus` v5.0.2 returns single `ConnectivityResult`, NOT `List`
- `flutter_map` v6.1.0 has no `isDotted` on Polyline
- `Icons.signal_cellular_1_bar` does not exist — use `Icons.signal_cellular_alt_1_bar`
