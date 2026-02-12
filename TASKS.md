# Navigate - Tasks

## Completed

### Bidirectional Add-Only Sync for Areas & Layers
- [x] SyncManager: areas sync direction `pullOnly` -> `bidirectional`
- [x] SyncManager: `_isAreaLayerPath()` helper for area layer subcollection detection
- [x] SyncManager: delete blocking in `_processSingleItem` for areas & area layers
- [x] CheckpointRepository: push path fix `layers_nz` -> `areas/{areaId}/layers_nz`
- [x] SafetyPointRepository: push path fix `layers_nb` -> `areas/{areaId}/layers_nb`
- [x] BoundaryRepository: push path fix `layers_gg` -> `areas/{areaId}/layers_gg`
- [x] ClusterRepository: push path fix `layers_ba` -> `areas/{areaId}/layers_ba`
- [x] All 5 layer/area repositories: `delete()` -> no-op (add-only)
- [x] UI: remove delete buttons from areas_list_screen
- [x] UI: remove delete buttons from checkpoints_list_screen
- [x] UI: remove delete buttons from boundaries_list_screen
- [x] UI: remove delete buttons from safety_points_list_screen
- [x] UI: remove delete buttons from clusters_list_screen
- [x] APK build successful (70.9MB)

### Framework Entity & Related Fixes (user)
- [x] Fix `Framework` type references in unit_admin_frameworks_screen
- [x] Fix `frameworkId` getter on HatInfo, Navigation
- [x] Fix `frameworks` getter on NavigationTree
- [x] APK rebuild successful

### תיקון באג סנכרון מחיקות (2026-02-12)
**בעיה:** מחיקות יחידות לא סונכרנו — אחרי התקנה מחדש הן חזרו מ-Firestore.
**סיבה:** פעולות מחיקה נכנסו לתור בעדיפות `SyncPriority.normal` (לא מפעיל סנכרון מיידי). אם המשתמש מתקין מחדש לפני שהסנכרון הזמני (כל 5 דקות) הספיק לרוץ — תור הסנכרון אבד והמחיקה לא הגיעה ל-Firestore.
**תיקון:** הוספת `priority: SyncPriority.high` לכל פעולות המחיקה:
- [x] `unit_repository.dart` — `delete()`, `deleteWithCascade()` (×5 קריאות), `removeMember()`
- [x] `navigation_repository.dart` — `delete()`
- [x] `navigation_tree_repository.dart` — `delete()`
- [x] `navigator_tree_repository.dart` — `delete()`
- [x] `nav_layer_repository.dart` — `deleteCheckpoint()`

### תיקון באג חלוקת נקודות לצירים (2026-02-12)
**בעיה:** חלוקה אוטומטית של צירים הציגה 0 נקודות למרות שהאזור הכיל עשרות.
**סיבה:** מסכי חלוקת צירים טענו נקודות מטבלת Checkpoints הגלובלית (`getByArea()`) במקום מ-NavCheckpoints (עותקים ניווטיים שכבר סוננו לפי גבול גזרה בעת יצירת הניווט).
**תיקון:** שינוי 3 מסכים לטעון NavCheckpoints דרך `NavLayerRepository`:
- [x] `routes_automatic_setup_screen.dart`
- [x] `routes_verification_screen.dart`
- [x] `routes_edit_screen.dart`

---

## Pending

### Sync & Data
- [ ] Verify bidirectional sync end-to-end: create area locally -> check it appears in Firestore
- [ ] Verify layer push: create checkpoint -> check SyncQueue has `areas/{areaId}/layers_nz` path
- [ ] Verify pull still works: `_pullAreaLayers()` unchanged
- [ ] Test conflict detection for areas (bidirectional with version checking)
- [ ] Clean up legacy flat collection references (`layersNzCollection`, etc.) if no longer needed

### Testing
- [ ] Add tests for `_isAreaLayerPath()` helper
- [ ] Add tests for delete blocking in SyncManager
- [ ] Expand test coverage beyond `widget_test.dart`

### Code Quality
- [ ] Remove unused `_authService` field in `areas_list_screen.dart`
- [ ] Fix pre-existing errors in `scripts/create_test_checkpoints.dart`
- [ ] Fix pre-existing error in `test/widget_test.dart` (`MyApp` not found)
- [ ] Address `avoid_print` warnings (replace with proper logging)

### Future Considerations
- [ ] Add soft-delete mechanism if delete functionality is needed later (mark as archived instead of removing)
- [ ] Admin-only delete override (allow admin role to delete areas/layers)
- [ ] Firestore security rules update to enforce add-only on areas/layers collections
