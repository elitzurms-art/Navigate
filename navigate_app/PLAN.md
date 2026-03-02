# תוכנית: שיפורי ניווט מאבטח (guard mode)

## סקירה

6 שינויים בניווט מאבטח — שינויי UI (מרקרים), תיקון אלגוריתם, ושינוי התנהגותי מרכזי.

---

## שלב 1: מרקרים — F לסיום, S לנקודת חילוף (10 קבצים)

### 1A: שינוי אות נקודת סיום S → F

**כל הקבצים הבאים:** שינוי `'${cp.sequenceNumber}S'` → `'${cp.sequenceNumber}F'` + עדכון legend "סיום (S)" → "סיום (F)"

| קובץ | שורות |
|---|---|
| `routes_verification_screen.dart` | 770, 928 (label), 503 (legend) |
| `approval_screen.dart` | ~1382 (label) |
| `investigation_screen.dart` | ~1950 (label), ~3756 (legend) |
| `navigation_management_screen.dart` | ~2389, ~2822 (label) |
| `routes_edit_screen.dart` | ~391 (label) |
| `routes_manual_app_screen.dart` | ~449 (label) |
| `approval_view.dart` | ~474 (label), ~734 (legend) |
| `review_view.dart` | ~548 (label), ~741 (legend) |
| `navigator_map_screen.dart` | ~327 (label) |

### 1B: מרקר נקודת חילוף — לבן + S

בכל המסכים שמציגים מרקרים על המפה, להוסיף בדיקה `isSwapPoint` **לפני** בדיקת `isEnd`:

```dart
// חישוב swapPointIds מכל הצירים
final swapPointIds = navigation.routes.values
    .where((r) => r.swapPointId != null)
    .map((r) => r.swapPointId!)
    .toSet();

// בלולאת הנקודות:
final isSwapPoint = swapPointIds.contains(cp.id);

if (isSwapPoint) {
  markerColor = Colors.white;
  label = '${cp.sequenceNumber}S';
  borderColor = Colors.grey[700]!;  // גבול כהה על רקע לבן
} else if (isStart) { ... }
else if (isEnd) { ... }
```

**חשוב**: swap point = לבן עם S, **לפני** בדיקת end point כדי שלא יסומן כ-F.

---

## שלב 2: תיקון אלגוריתם — swap point לא נקודה של מנווט

**קובץ**: `routes_distribution_service.dart`, פונקציה `_expandForComposition()`

### שינוי (שורות ~387-406):

אחרי מיון `orderedCps`, להוציא את swap point מהרשימה:

```dart
// הוצאת swap point מרשימת נקודות לניקוד
if (swapId != null) {
  orderedCps.remove(swapId);
}
```

כך swap point **לא יהיה** ב-`checkpointIds` של אף מנווט (לא ייספר בניקוד/דקירות), אבל **יישאר** ב-`sequence` (לצורך routing) וב-`startPointId`/`endPointId` (לצורך תצוגה).

---

## שלב 3: תיקון תצוגת swap point כנקודת סיום

**קובץ**: `routes_verification_screen.dart`

### בעיה:
`_endPointId` getter (שורה 272) מחפש `route.endPointId` מהציר הראשון שנמצא. בגלל ש-first_half route מגדיר `endPointId = swapId`, ה-getter מחזיר את swap point כנקודת הסיום.

### פתרון:
כאשר הניווט הוא מאבטח, `_endPointId` צריך להחזיר את נקודת הסיום **האמיתית** (של ה-second_half), לא את ה-swap point:

```dart
String? get _endPointId {
  // מאבטח: חיפוש end point של second_half
  if (widget.navigation.forceComposition.isGuard) {
    for (final route in _filteredRoutes.values) {
      if (route.segmentType == 'second_half' && route.endPointId != null) {
        return route.endPointId;
      }
    }
  }
  // ברירת מחדל
  for (final route in _filteredRoutes.values) {
    if (route.endPointId != null) return route.endPointId;
  }
  return widget.navigation.endPoint;
}
```

**אותו תיקון** בכל מסך שבונה `endIds` set מכל ה-routes:
- `approval_screen.dart` — סינון swap points מ-endIds
- `investigation_screen.dart` — אותו דבר
- `navigation_management_screen.dart` — אותו דבר (2 מקומות)
- `navigator_map_screen.dart` — אותו דבר

---

## שלב 4: שינוי התנהגותי — ניווט מאבטח = שני ניווטי בדד רצופים

### 4A: הפרדת guard מ-pair/squad בלוגיקת הקבוצה

**קובץ**: `navigation_settings.dart`
```dart
// getter חדש — guard לא נחשב "קבוצתי" לצורך representative/secondary
bool get isGroupedPairOrSquad => type == 'pair' || type == 'squad';
```

### 4B: active_view.dart — שינוי `_startNavigation()`

**שורה 1440**: שינוי `composition.isGrouped` → `composition.isGroupedPairOrSquad`

בגלל שבמאבטח אין representative/secondary:
- שני המנווטים הם primary (כל אחד בחצי שלו)
- לא מוצג דיאלוג "האם אתה הנציג?"
- `_isGroupSecondary` = false לשניהם

### 4C: active_view.dart — מנווט second_half ממתין ל-first_half

**ב-`_loadTrackState()` ו-`_buildWaitingView()`:**

כשהמנווט הוא guard + second_half:
1. בודק אם ה-first_half partner סיים (track.isActive == false)
2. אם לא — מציג "ממתין למנווט הראשון לסיים" + נעילת טלפון (security)
3. אם כן — מאפשר לחיצה על "התחלת ניווט"

**שדות חדשים ב-State:**
```dart
bool _isGuardSecondHalf = false;
bool _guardPartnerFinished = false;
StreamSubscription? _guardPartnerListener;
```

**זיהוי guard second_half:**
```dart
final route = _nav.routes[widget.currentUser.uid];
_isGuardSecondHalf = _nav.forceComposition.isGuard &&
    route?.segmentType == 'second_half';
```

**Firestore listener לסיום הראשון:**
```dart
if (_isGuardSecondHalf) {
  final partnerId = _nav.routes.entries
      .firstWhere((e) => e.value.segmentType == 'first_half')
      .key;
  _guardPartnerListener = FirebaseFirestore.instance
      .collection('navigation_tracks')
      .where('navigationId', isEqualTo: _nav.id)
      .where('navigatorUserId', isEqualTo: partnerId)
      .snapshots()
      .listen((snap) {
    if (snap.docs.isNotEmpty) {
      final data = snap.docs.first.data();
      final isActive = data['isActive'] as bool? ?? true;
      if (!isActive && mounted) {
        setState(() => _guardPartnerFinished = true);
      }
    }
  });
}
```

**UI — `_buildWaitingView()` הרחבה:**
```dart
if (_isGuardSecondHalf && !_guardPartnerFinished) {
  // מסך המתנה — "ממתין למנווט הראשון לסיים"
  // + נעילת טלפון (security) כבר פעילה
  return _buildGuardWaitingView();
}
// אחרת: כפתור "התחלת ניווט" רגיל
```

**נעילת טלפון בזמן המתנה:**

ב-`_loadTrackState()`, אם guard second_half ו-partner לא סיים → `_startSecurity()` מיידית (ללא יצירת track).

### 4D: active_view.dart — ביטול פסילה קבוצתית ל-guard

**שורה 503**: שינוי תנאי מ-`_nav.forceComposition.isGrouped` ל-`_nav.forceComposition.isGroupedPairOrSquad`

כך פסילה של מנווט אחד ב-guard **לא** פוסלת את השני.

### 4E: active_view.dart — GPS מלא לשני מנווטי guard

**שורות 311, 1504, 1514**: שינוי `if (!_isGroupSecondary)` ל-`if (!_isGroupSecondary || _nav.forceComposition.isGuard)`

כך שני מנווטי guard מקבלים GPS tracking מלא, health check, alert monitoring — כל אחד בחצי שלו.

### 4F: dispose — ניקוי listener

```dart
_guardPartnerListener?.cancel();
```

---

## סדר ביצוע

1. **שלב 1A** — שינוי S→F בכל המסכים (פשוט, search&replace)
2. **שלב 1B** — הוספת מרקר swap point לבן+S
3. **שלב 2** — תיקון אלגוריתם (swap point לא בcheckpointIds)
4. **שלב 3** — תיקון _endPointId בוידוא צירים + מסכים אחרים
5. **שלב 4A-4B** — הפרדת guard מ-pair/squad + ביטול representative dialog
6. **שלב 4C** — מסך המתנה ל-second_half + listener
7. **שלב 4D-4E** — ביטול פסילה קבוצתית + GPS מלא
8. **flutter analyze** — בדיקת שגיאות

---

## קבצים מושפעים (סיכום)

| קובץ | שלב |
|---|---|
| `navigation_settings.dart` | 4A |
| `routes_distribution_service.dart` | 2 |
| `active_view.dart` | 4B-4F |
| `routes_verification_screen.dart` | 1A, 1B, 3 |
| `approval_screen.dart` | 1A, 1B, 3 |
| `investigation_screen.dart` | 1A, 1B, 3 |
| `navigation_management_screen.dart` | 1A, 1B, 3 |
| `routes_edit_screen.dart` | 1A, 1B |
| `routes_manual_app_screen.dart` | 1A, 1B |
| `approval_view.dart` | 1A, 1B |
| `review_view.dart` | 1A, 1B |
| `navigator_map_screen.dart` | 1A, 1B, 3 |
