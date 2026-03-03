# Algorithm — חלוקת נקודות אוטומטית

## סקירה כללית

האלגוריתם מחלק נקודות ציון (checkpoints) בין מנווטים לתרגילי ניווט.
גישה: **Monte Carlo + Simulated Annealing** — בנייה אקראית + אופטימיזציה מקומית.

**קובץ**: `lib/services/routes_distribution_service.dart`

---

## שלבי האלגוריתם

### שלב 1: הכנה (`distributeAutomatically`, שורות 194-348)
1. **מציאת מנווטים** (`_findNavigators`, שורות 576-620) — רק בעלי תפקיד `navigator` (לא מפקדים)
   - לפי `selectedParticipantIds` → סינון role
   - לפי `selectedSubFrameworkIds` → userIds מתת-מסגרות (דילוג על isFixed)
   - fallback → כל המנווטים ביחידה
2. **סינון נקודות לפי גבול גזרה** (שורות 249-257) — רק point-type בתוך הפוליגון (`GeometryUtils.filterPointsInPolygon`)
3. **ולידציה** (שורות 265-270) — מנווטים ≥ 1, נקודות ≥ K (בניכוי start/end)
4. **יצירת קבוצות** (שורות 238-246) — אם הרכב הכוח ≠ solo → `autoGroupNavigators()`
5. **הכנת נתונים ל-Isolate** (שורות 272-333) — המרה ל-serializable maps, טיפול ב-swap point למאבטח

### שלב 2: הרצה ב-Isolate (`_isolateWorker`, שורות 686-796)

#### 2a. מטריצת מרחקים (`_buildDistanceMatrix`, שורות 1855-1869)
- Haversine O(N²) פעם אחת → lookup O(1) דרך `_dist()`
- כל הנקודות הייחודיות (pool + start/end + waypoints) נכללות

#### 2b. בחירת אסטרטגיה (שורות 719-720)
- `pool.length ≥ N × K` → ללא שיתוף (`allowSharing=false`)
- `pool.length < N × K` או `doubleCheck` → עם שיתוף
- אם השלב הראשון לא הצליח (לא allInRange) → fallback לשיתוף

#### 2c. בנייה + SA (`_targetLengthWithSA`, שורות 799-1014)

**500 סיבובי בנייה**, כל אחד כולל:

1. **בניית פתרון התחלתי** (`_constructTargetLengthSolution`, שורות 1017-1118):
   - **חלוקה גיאוגרפית** (`_geographicPartition`, שורות 1121-1165) — מיון לפי זווית מ-centroid + offset אקראי → N sectors שווים + איזון דליים ריקים
   - סדר מנווטים אקראי (`navOrder.shuffle`) למניעת הטיה
   - כל מנווט בונה ציר מתוך המחיצה שלו (+ השלמה מהשאר)
   - **בחירת K נקודות** (`_constructSingleRoute`, שורות 1145-1216) — Boltzmann selection מתוך top-10 לפי מרחק מהיעד האידיאלי (temperature=0.5)
   - **אופטימיזציית רצף** (`_optimizeSequence`, שורות 1493-1603) — Nearest-neighbor TSP + waypoint insertion + 2-opt (דילוג על waypoints)
   - **ג'יטר ±15%** על אורך היעד ליצירת מגוון בין סיבובים

2. **Simulated Annealing** (`_simulatedAnnealing`, שורות 1219-1434):

   **כיול אוטומטי** (שורות 1252-1271): 20 מהלכי SWAP אקראיים → median דלתות → טמפרטורה התחלתית

   **5 סוגי מהלכים:**

   | מהלך | הסתברות | תיאור | שורות |
   |------|---------|-------|-------|
   | SWAP | 35% | החלפת נקודה בין 2 מנווטים | 1284-1315 |
   | RELOCATE | 20% | העברת נקודה מציר אחד לאחר (עם פיצוי מהפול) | 1317-1371 |
   | MOVE | 15% | החלפת נקודה בציר עם נקודה מהפול החופשי | 1373-1407 |
   | CROSS-EXCHANGE | 15% | החלפת שרשרת 1-2 נקודות בין 2 צירים | 1409-1450 |
   | 2-OPT INTRA | 15% | היפוך תת-רצף בתוך ציר בודד | 1452-1481 |

   **לוח טמפרטורה:**
   - התחלה: median של 20 דלתות ראשוניות (כיול אוטומטי)
   - סיום: startTemp × 0.01
   - קירור: `coolingRate = pow(endTemp/startTemp, 1/steps)`
   - Reheat: אם 40 צעדים ללא שיפור → `temperature *= 1.5`
   - קבלת מהלך גרוע: `random < exp(delta / temperature)`

3. **ניקוד** (`_scoreDistribution`, שורות 1707-1773) — לפי הקריטריון הנבחר

4. **Multi-start restart** (שורות 916-960): כל 100 סיבובי בנייה, SA נוסף מופעל מהפתרון הטוב ביותר שנמצא עד כה

5. **Early exit** (שורות 908-913): allInRange + variance < 0.001 → עצירה מוקדמת

### שלב 3: הרחבה לפי הרכב הכוח (`_expandForComposition`, שורות 359-508)
- **מאבטח (guard)**: פיצול ציר בנקודת החלפה — חצי ראשון/שני
  - נקודת החלפה אוטומטית: `_findAutoSwapPoint` — הנקודה הקרובה ביותר לאמצע הציר
  - מנווט 1: start → swap (first_half)
  - מנווט 2: swap → end (second_half)
- **צמד/חוליה (pair/squad)**: כל חברי הקבוצה מקבלים ציר זהה

---

## פרמטרים

| פרמטר | סוג | תיאור |
|-------|-----|-------|
| `checkpointsPerNavigator` (K) | int | מספר נקודות לכל מנווט |
| `minRouteLength` | double | אורך מינימלי (ק"מ) |
| `maxRouteLength` | double | אורך מקסימלי (ק"מ) |
| `executionOrder` | String | 'sequential' (TSP) או 'free' |
| `scoringCriterion` | String | קריטריון ניקוד (ראה למטה) |
| `startPointId` | String? | נקודת התחלה משותפת |
| `endPointId` | String? | נקודת סיום משותפת |
| `waypoints` | List\<WaypointCheckpoint\> | נקודות חובה |
| `forceComposition` | ForceComposition? | הרכב כוח: solo/guard/pair/squad |
| `boundary` | Boundary? | גבול גזרה (פוליגון) |

---

## קריטריוני ניקוד

### fairness (הוגנות) — ברירת מחדל
- ממזער CV (סטיית תקן / ממוצע) של אורכי הצירים
- `score = -cv * 5000 - rangePenalty + allInRangeBonus + uniqueBonus`

### midpoint (אמצע הטווח)
- ממזער סטייה מ-(min+max)/2
- `score = -totalDeviation * 200 - maxDeviation * 300 - rangePenalty + ...`

### uniqueness (ייחודיות)
- ממקסם מספר נקודות ייחודיות (ממזער שיתוף)
- `score = totalUnique * 1000 - rangePenalty + allInRangeBonus - variance * 10`

### doubleCheck (אימות כפול)
- כל נקודה נבדקת ע"י בדיוק 2 מנווטים
- `score = doubleChecked * 1500 - singleOnly * 500 - overChecked * 300 - ...`

### Soft range penalty (משותף לכל הקריטריונים)
```
rangePenalty = Σ:
  if too_short: (minRoute - length)² × 500
  if too_long:  (length - maxRoute)² × 500
allInRangeBonus = allInRange ? 5000 : 0
uniqueBonus = !hasSharing ? 500 : 0
```

---

## כללים קריטיים (אסור לשנות!)

1. **נקודות התחלה/סיום** — מוחרגות מהפול, נכללות בכל ציר, נספרות באורך
2. **Waypoints** — חייבים להופיע בציר, ננעלים ב-2-opt, מוחרגים מהפול
3. **גבול גזרה** — רק נקודות point-type בתוך הפוליגון (swap point נוסף גם אם מחוץ)
4. **ללא כפילויות בציר** — אותה נקודה לא מופיעה פעמיים באותו ציר
5. **שיתוף רק בצורך** — allowSharing=true רק כש-pool < N×K או doubleCheck
6. **סדר ביצוע** — 'sequential' → TSP + 2-opt; 'free' → ללא סידור
7. **הרכב הכוח** — guard: פיצול בנקודת החלפה; pair/squad: ציר זהה
8. **מנווטים בלבד** — מפקדים לא מקבלים צירים (סינון role)
9. **תתי-מסגרות קבועות** — מדולגות (isFixed=true)
10. **שמירת K קבוע** — כל מנווט חייב לקבל בדיוק K נקודות

---

## מבנה נתונים

### קלט
```dart
distributeAutomatically({
  Navigation navigation,      // ניווט עם selectedParticipantIds, selectedSubFrameworkIds
  NavigationTree tree,         // עץ עם subFrameworks
  List<Checkpoint> checkpoints, // כל נקודות הציון
  Boundary? boundary,          // גבול גזרה (אופציונלי)
  String? startPointId,
  String? endPointId,
  List<WaypointCheckpoint> waypoints,
  String executionOrder,       // 'sequential' | 'free'
  int checkpointsPerNavigator,
  double minRouteLength,
  double maxRouteLength,
  String scoringCriterion,     // 'fairness' | 'midpoint' | 'uniqueness' | 'doubleCheck'
  ForceComposition? forceComposition,
})
```

### פלט
```dart
DistributionResult {
  String status,                    // 'success' | 'needs_approval'
  Map<String, AssignedRoute> routes, // navigatorId → route
  List<ApprovalOption> approvalOptions,
  bool hasSharedCheckpoints,
  int sharedCheckpointCount,
  ForceComposition? forceComposition,
}

AssignedRoute {
  List<String> checkpointIds,    // K נקודות שהוקצו
  List<String> sequence,         // סדר ביקור מאופטמל
  double routeLengthKm,
  String? startPointId,
  String? endPointId,
  List<String> waypointIds,
  String status,                 // 'optimal' | 'too_short' | 'too_long'
  String? groupId,
  String segmentType,            // 'full' | 'first_half' | 'second_half'
  String? swapPointId,
}
```

---

## פרמטרי ביצועים

| פרמטר | ערך | שורות |
|--------|------|-------|
| סיבובי בנייה (`constructionRounds`) | 500 | 822 |
| צעדי SA לסיבוב (`saStepsPerRound`) | 800 | 823 |
| Multi-start restart | כל 100 סיבובים | 916 |
| כיול טמפרטורה | 20 דגימות SWAP | 1252 |
| Boltzmann top-N | 10 מועמדים | 1181 |
| Boltzmann temperature | 0.5 | 1184 |
| 2-opt max passes | 10 | 1547 |
| Reheat threshold | 40 צעדים | 1426 |
| Early exit variance | < 0.001 | 913 |
| Progress reporting | כל 2 איטרציות | 828 |
| מהירות צפויה | 30-90 שניות ל-10 מנווטים × 30 נקודות | — |

---

## ApprovalOptions (כשלא הכל בטווח)

| סוג | תיאור |
|------|-------|
| `expand_range` | הרחבת טווח ל-80%-120% מהמקורי |
| `reduce_checkpoints` | הורדה ל-K-1 נקודות למנווט |
| `accept_best` | קבלת הפתרון הטוב ביותר (עם ציון כמה חורגים) |

---

## פונקציות עזר

| פונקציה | שורות | תיאור |
|---------|-------|-------|
| `autoGroupNavigators` | 127-191 | שיבוץ מנווטים לקבוצות (guard/pair/squad) |
| `_findNavigators` | 576-620 | מציאת מנווטים לפי participants/subFrameworks/unit |
| `_runInIsolate` | 623-683 | הרצת האלגוריתם ב-Isolate עם progress |
| `_isolateWorker` | 686-796 | Worker — הלב של האלגוריתם |
| `_targetLengthWithSA` | 799-1014 | בנייה + SA + multi-start |
| `_constructTargetLengthSolution` | 1017-1118 | בניית פתרון התחלתי |
| `_geographicPartition` | 1121-1165 | חלוקה לפי זווית מ-centroid |
| `_constructSingleRoute` | 1145-1216 | בחירת K נקודות — Boltzmann |
| `_simulatedAnnealing` | 1219-1434 | SA — 5 מהלכים + כיול + reheat |
| `_rebuildRoute` | 1437-1467 | בנייה מחדש אחרי שינוי נקודות |
| `_optimizeSequence` | 1493-1603 | TSP + waypoints + 2-opt |
| `_insertWaypointsIntoSequence` | 1605-1670 | הכנסת waypoints למיקום אופטימלי |
| `_buildRouteWithWaypoints` | 1673-1705 | חישוב אורך ציר מלא |
| `_scoreDistribution` | 1707-1773 | פונקציית ניקוד לפי קריטריון |
| `_createFallbackDistribution` | 1775-1840 | חלוקה בסיסית (fallback) |
| `_buildDistanceMatrix` | 1855-1869 | מטריצת מרחקים O(N²) |
| `_expandForComposition` | 359-508 | הרחבה ל-guard/pair/squad |
| `_findAutoSwapPoint` | 511-539 | נקודת החלפה אוטומטית |
| `_parseIsolateResult` | 1878-1960 | המרת תוצאת Isolate ל-DistributionResult |

---

## היסטוריית שיפורים

### v2 (מרץ 2026) — 7 שיפורי אופטימיזציה
1. **חיפוש מקיף**: constructionRounds 100→500, SA steps 200→800
2. **חלוקה גיאוגרפית משופרת**: זווית מ-centroid (במקום latitude בלבד) + offset אקראי + איזון דליים
3. **מהלך RELOCATE**: העברת נקודה בין צירים עם פיצוי מהפול (20%)
4. **מהלך CROSS-EXCHANGE**: החלפת שרשרת 1-2 נקודות בין צירים (15%)
5. **כיול אוטומטי של טמפרטורה**: median של 20 דלתות SWAP (במקום קבוע 1.0)
6. **Multi-start restart**: SA נוסף מהפתרון הטוב ביותר כל 100 סיבובים
7. **Early exit מחמיר**: variance threshold 0.01→0.001
