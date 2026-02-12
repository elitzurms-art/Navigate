# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

Monorepo with two packages:
- **`navigate_app/`** — Main Flutter app (military navigation management: maps, GPS, participants, routes, scoring)
- **`gps_plus/`** — Local Flutter plugin for GPS functionality (referenced via `path: ../gps_plus` in pubspec)

All Flutter commands must run from `navigate_app/`.

## Build Commands

```bash
# Run the app
cd navigate_app && flutter run

# Static analysis (strict lint rules via flutter_lints)
cd navigate_app && flutter analyze

# Regenerate Drift (SQLite ORM) code after schema changes
cd navigate_app && dart run build_runner build --delete-conflicting-outputs

# Run tests
cd navigate_app && flutter test

# Run a single test file
cd navigate_app && flutter test test/widget_test.dart
```

## Architecture — Clean Architecture (Flutter)

```
navigate_app/lib/
├── core/           # Constants, theme (Material 3 + Rubik), utils (geometry, UTM converter), map config
├── domain/entities/ # 18 business entities — all use Equatable + toMap()/fromMap()/copyWith()
├── data/
│   ├── datasources/local/app_database.dart  # Drift schema v17, 17 tables
│   ├── datasources/remote/firebase_service.dart
│   ├── repositories/    # 14 concrete repositories
│   └── sync/sync_manager.dart  # Offline-first bidirectional Drift↔Firestore sync
├── services/       # 12 service classes (auth, GPS, scoring, session, data loading, etc.)
├── presentation/
│   ├── screens/    # UI screens organized by feature
│   └── widgets/    # Shared widgets
└── main.dart       # Entry point: Firebase init → Auth → SyncManager → app launch
```

State management: **Provider v6.1.1**

## Key Entities & Conventions

- **User**: `uid` = מספר אישי (7-digit personal number, is the ID). `personalNumber` is a getter → `uid`. `fullName` computed from firstName + lastName. No `username` or `frameworkId` fields.
- **Unit**: Absorbed the old `Framework` class. Has `level`, `isNavigators`, `isGeneral`. `UnitRepository.delete()` cascades to child units, trees, and navigations.
- **NavigationTree**: Stores `subFrameworks` (List\<SubFramework\>) directly. `fromMap()` has backward compat for old `frameworks` key.
- **Navigation**: `selectedUnitId` (DB column still `frameworkId` for backward compat). 8 statuses: preparation → ready → learning → system_check → waiting → active → approval → review.
- **HatInfo**: Has `unitId/unitName` but NO `frameworkId/frameworkName`.

## Database (Drift v2.14.1)

- Schema version 17, defined in `data/datasources/local/app_database.dart`
- Table name `NavigationTrees` → accessor `navigationTrees` → generated class `NavigationTree` (singular)
- Settings stored as JSON text columns: learningSettingsJson, verificationSettingsJson, alertsJson, displaySettingsJson, reviewSettingsJson
- After any schema change, always run `dart run build_runner build --delete-conflicting-outputs`

## Firebase

- Project: `navigate-native` — Phone Auth + Anonymous Auth (for Firestore access), Cloud Firestore, Storage
- Collections: users, units, areas, navigator_trees, navigations, navigation_tracks, navigation_approval, sync_metadata
- Area layer subcollections: `areas/{areaId}/layers_nz`, `layers_nb`, `layers_gg`, `layers_ba`

## Sync (SyncManager)

- **Offline-first**: local ops always succeed, syncs when online
- Pull-only: Users, Areas. Bidirectional: Units, Trees, Navigations, Nav layers. Push-only: Tracks, Punches, Violations. Realtime: Alerts.
- Checks `_isAuthenticated` before all sync ops
- GPS batch sync every 2 min, periodic sync every 5 min
- `_didInitialSync` flag prevents duplicate initial sync

## Navigation Tree Repos — Two Exist

| Repo | Status |
|---|---|
| `NavigationTreeRepository` | **Active** — screens in `screens/navigation_trees/` |
| `NavigatorTreeRepository` | Legacy, stubbed — do not use |

Legacy tree screens in `screens/trees/` are NOT in the main app flow.

## User Roles

`navigator` (default), `commander`, `unit_admin`, `developer`, `admin`

Hat types: admin, commander, navigator, management, observer

## Known Gotchas

**Import conflicts** — these will cause compile errors if not handled:
```dart
import 'package:drift/drift.dart' hide Query;           // Firestore Query conflict
import 'package:firebase_auth/firebase_auth.dart' hide User;  // App User conflict
```

**Library version constraints:**
- `connectivity_plus` v5.0.2 returns single `ConnectivityResult`, NOT `List`
- `flutter_map` v6.1.0 has no `isDotted` on Polyline
- `Icons.signal_cellular_1_bar` does NOT exist → use `Icons.signal_cellular_alt_1_bar`

**Firestore Timestamps** can't be `jsonEncode`'d — use `_sanitizeForJson()` to convert to ISO strings.

**_currentNavigation pattern**: In screens that modify navigation (training_mode_screen, etc.), use `_currentNavigation` (mutable local copy) instead of `widget.navigation` (immutable). Update it after each save.

## Routing (main.dart)

| Route | Screen |
|---|---|
| `/` | LoginScreen |
| `/register` | RegisterScreen |
| `/mode-selection` | MainModeSelectionScreen |
| `/home` | HomeRouter → NavigatorHomeScreen (navigator) or HomeScreen (admin/commander) |
| `/unit-admin-frameworks` | UnitAdminFrameworksScreen |

## Dev Users (main.dart)

Developer uid: `6868383`. Test users: `1111111`–`4444444`.

## Language

The app UI is entirely in Hebrew (RTL). `flutter: generate: true` enables localization. Code comments and variable names are in English, but UI strings and entity display names are Hebrew.
