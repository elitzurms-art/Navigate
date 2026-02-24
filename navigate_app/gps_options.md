# מערכת מיקום — GPS, PDR, Cell Tower ו-Pipeline מלא

## סקירה כללית

המערכת משתמשת בשלושה מקורות מיקום בשרשרת fallback אוטומטית:

```
GPS (ראשי) → PDR+Cell hybrid (משני) → Cell Tower בלבד (שלישי) → none
```

המנווט לא צריך לעשות שום דבר — המעבר בין מקורות הוא אוטומטי לחלוטין.

בנוסף, המערכת כוללת pipeline סינון ואימות מלא:

```
GPS raw fix
  → Jamming State Machine (דיוק + מהירות)
  → Anti-Drift / ZUPT (דחיית drift בעמידה)
  → Velocity cross-validation (GPS vs צעדים)
  → Jump gate (קפיצות בלתי אפשריות)
  → Kalman Filter (החלקה)
  → Window Outlier Removal (glitch→return)
  → TrackPoint עם activity metadata
```

---

## 1. GPS — מקור ראשי

- המקור המדויק ביותר (דיוק < 1 מ')
- משתמש בלווייני GNSS דרך חיישן המכשיר
- **סף דיוק**: אם accuracy > 50 מ' — המערכת מנסה fallback
- **זיהוי זיוף**: אם המיקום רחוק > 50 ק"מ ממרכז גבול הגזרה — GPS נחשב חסום/מזויף

---

## 2. PDR (Pedestrian Dead Reckoning) — מיקום ללא GPS

### מה זה?
PDR מחשב מיקום יחסי על בסיס **ספירת צעדים + כיוון הליכה**, ללא תלות ב-GPS או ברשת סלולרית.

### איך זה עובד?

1. **נקודת עיגון (Anchor)** — כשיש GPS fix טוב (accuracy < 20 מ'), המערכת שומרת את המיקום כנקודת ייחוס ומאפסת את מונה הצעדים.

2. **זיהוי צעדים** — חיישן Step Detector של המכשיר מזהה כל צעד. אורך צעד מחושב דינמית ע"י Weinberg estimator (ברירת מחדל: 0.7 מ').

3. **זיהוי פעילות (Activity Classification)** — classifier מבוסס חיישנים מזהה את סוג הפעילות:
   - **עמידה** — אין צעדים > 3 שניות
   - **הליכה** — cadence 1.5–2.5 צעדים/שנייה
   - **ריצה** — cadence > 2.5 צעדים/שנייה או variance גבוה באקסלרומטר

4. **אורך צעד אדפטיבי** — Weinberg formula: `K × (aMax - aMin)^0.25` (K=0.41)
   - **הליכה**: תוצאת Weinberg ישירה (clamp 0.3–1.8 מ')
   - **ריצה**: תוצאת Weinberg × 1.4 (צעדים ארוכים יותר)
   - **עמידה**: אורך 0 (ZUPT מונע התקדמות)

5. **חישוב כיוון** — Complementary Filter שמשלב:
   - **98% ג'ירוסקופ** — מדויק לטווח קצר, נותן שינוי כיוון בזמן אמת
   - **2% מגנטומטר** — מתקן סחיפה לטווח ארוך (מצפן מגנטי)

6. **עדכון מיקום** — בכל צעד, המיקום מתקדם באורך הצעד המחושב בכיוון הנוכחי:
   ```
   lat += cos(heading) × stepLength / 111,320
   lon += sin(heading) × stepLength / (111,320 × cos(lat))
   ```

### דיוק
- **שגיאה מצטברת**: 2-6% מכל צעד (תלוי בפניות)
  - הליכה ישרה: ~2% (0.014 מ' לצעד)
  - פניות: עד 6% (0.042 מ' לצעד)
- 100 צעדים (~70 מ') → שגיאה ~1.4–4.2 מ'
- 1,000 צעדים (~700 מ') → שגיאה ~14–42 מ'
- כל GPS fix טוב מאפס את השגיאה חזרה ל-0

### חיישנים נדרשים
| חיישן | תפקיד | חובה? |
|--------|--------|-------|
| Step Detector | זיהוי צעדים | כן |
| Gyroscope | שינוי כיוון (מהיר) | כן (או מגנטומטר) |
| Magnetometer | כיוון מוחלט (מצפן) | כן (או ג'ירוסקופ) |
| Accelerometer | אורך צעד דינמי + Activity Classification + ZUPT | כן |

---

## 3. Cell Tower — מיקום על בסיס אנטנות סלולריות

- משתמש באנטנות סלולריות נראות + מסד נתונים מקומי של מיקומי אנטנות
- **3+ אנטנות** → Trilateration (הכי מדויק)
- **1-2 אנטנות** → Weighted Centroid
- **דיוק**: 100-500 מ' (תלוי במספר אנטנות וצפיפותן)

---

## 4. PDR+Cell Hybrid — שילוב

כשגם PDR וגם Cell Tower זמינים, המערכת מחשבת ממוצע משוקלל:

```
pdrWeight  = cellAccuracy / (pdrAccuracy + cellAccuracy)
cellWeight = pdrAccuracy  / (pdrAccuracy + cellAccuracy)

hybridLat = pdr.lat × pdrWeight + cell.lat × cellWeight
hybridLon = pdr.lon × pdrWeight + cell.lon × cellWeight
```

**עיקרון**: המקור המדויק יותר מקבל משקל גבוה יותר.

**דוגמה**: PDR accuracy = 5 מ', Cell accuracy = 200 מ':
- pdrWeight = 200/205 ≈ **0.98**
- cellWeight = 5/205 ≈ **0.02**
- כמעט כל המשקל על PDR, עם תיקון קל מ-Cell

---

## 5. Activity Classification — זיהוי סוג פעילות

### מה זה?
Classifier מבוסס חיישנים (ללא Google Play Services) שמזהה עמידה/הליכה/ריצה מנתוני step cadence ו-accelerometer.

### למה זה נחוץ?
- **אורך צעד אדפטיבי**: ריצה = צעדים ארוכים יותר → PDR מדויק יותר
- **מטה-דאטה לתחקיר**: כל TrackPoint שומר את סוג הפעילות
- **אין תלות חיצונית**: עובד על כל מכשיר, אין latency, אין צורך ב-Play Services

### אלגוריתם

```
1. Step cadence = (מספר צעדים - 1) / זמן בין ראשון לאחרון
   (חלון הזזה של 10 צעדים אחרונים)

2. Accel variance = variance של 100 דגימות אחרונות
   (magnitude בריבוע — ללא sqrt לביצועים)

3. סיווג:
   אין צעדים > 3 שניות          → standing
   cadence ≥ 2.5 steps/sec      → running
   accel variance ≥ 8.0          → running
   אחרת                          → walking
```

### ערכי סף

| פרמטר | ערך | הסבר |
|--------|------|-------|
| `_runningCadenceThreshold` | 2.5 steps/sec | מעל = ריצה |
| `_runningAccelVariance` | 8.0 | variance גבוה = ריצה |
| `_standingTimeout` | 3 שניות | אין צעדים = עמידה |
| `_stepWindowSize` | 10 | צעדים ל-cadence |
| `_accelWindowSize` | 100 | דגימות ל-variance |
| `_runningMultiplier` | ×1.4 | מכפיל אורך צעד בריצה |

### `PdrActivityType` enum

| ערך | תנאי | אורך צעד |
|------|-------|-----------|
| `standing` | אין צעדים > 3 שניות | 0 (ZUPT) |
| `walking` | cadence < 2.5, variance < 8 | Weinberg ×1.0 |
| `running` | cadence ≥ 2.5 או variance ≥ 8 | Weinberg ×1.4 |

> **הערה**: ה-enum נקרא `PdrActivityType` (לא `ActivityType`) כדי למנוע התנגשות עם `ActivityType` מחבילת `geolocator_apple`.

---

## 6. Jamming State Machine — זיהוי חסימת GPS

### מצבים

```
normal ──[3 fixes רעים]──► jammed ──[2 fixes טובים]──► recovering ──► normal
  ▲                                                          │
  └──────────────────────────────────────────────────────────┘
```

### הגדרות

| פרמטר | ערך | הסבר |
|--------|------|-------|
| `_jammingAccuracyThreshold` | 35 מ' | GPS fix עם accuracy גרוע מזה = "רע" |
| `_maxSpeedMps` | 41.67 מ'/שנייה (150 קמ"ש) | מהירות בלתי אפשרית = "רע" |
| `_recoveryAccuracyThreshold` | 35 מ' | סף התאוששות |
| `_requiredBadFixes` | 3 | fixes רעים ברצף → jammed |
| `_requiredGoodFixes` | 2 | fixes טובים ברצף → normal |

### התנהגות
- **normal**: GPS מתקבל רגיל
- **jammed**: GPS נדחה, מעבר ל-fallback (PDR/Cell)
- **recovering**: fixes טובים נספרים, עד 2 → חזרה ל-normal

---

## 7. Anti-Drift / ZUPT — דחיית GPS drift בעמידה

### בעיה
כשהמנווט עומד, GPS ממשיך לדווח מיקומים משתנים (drift) — יוצר "רעידות" במסלול.

### פתרון
**ZUPT (Zero-Velocity Update)**: אם המנווט עומד **ו**-ה-GPS מדווח תזוזה — דוחים את ה-fix.

### הגדרות

| פרמטר | ערך |
|--------|------|
| `_stationaryTimeout` | 5 שניות (אין צעדים) |
| `_driftThresholdMeters` | 8 מ' |

### תנאי דחייה (כל התנאים חייבים להתקיים)
1. אינטרוול > 5 שניות (לא stream mode)
2. **לא** במצב jammed/recovering (bypass)
3. `_isStationary` = true (אין צעדים > 5 שניות)
4. יש נקודות קיימות במסלול
5. אין צעדים מאז הרישום האחרון
6. displacement מהנקודה האחרונה > 8 מ'

### ZUPT ב-PDR Engine
בנוסף ל-Anti-Drift ברמת GPS, ה-PDR Engine עצמו מריץ ZUPT:
- **Accel variance < 0.15** → `isStationary = true` → צעדים נדחים
- חלון 50 דגימות אקסלרומטר
- מונע false step detections בעמידה

---

## 8. Velocity / Jump Validation — סינון תזוזות חריגות

### Step-GPS Cross-Validation (`_isVelocityAnomalous`)
משווה GPS displacement ל-walking distance:
- **תנאי דחייה**: GPS displacement > 5× מרחק הליכה (צעדים × 0.7 מ')
- **מינימום**: 2 צעדים מאז הרישום האחרון
- חל רק על מקור GPS

### Jump Gate (`_isJumpAnomalous`)
מזהה "קפיצות" — GPS שמדווח מיקום רחוק מדי:
- **תנאי דחייה**: displacement > 500 מ' **וגם** מהירות משתמעת > 150 קמ"ש
- חל על כל מקור מיקום (GPS, Cell, PDR)

---

## 9. Kalman Filter — החלקה

Position Kalman Filter מחליק את מיקומי ה-GPS:
- **Motion-aware**: ב-ZUPT (עמידה) — Q קטן מאוד (0.001), נשאר במקום
- **Accuracy-adaptive**: Q מותאם לדיוק ה-GPS fix
- **Force position**: `recordManualPosition` עוקף Kalman ומאפס אותו

---

## 10. Manual Position — דקירה ידנית

כשהמנווט לוחץ על המפה ("דקירה"):

1. **Trim**: מוחק נקודות אחורה שרחוקות > 3× מהמיקום הידני
2. **Record**: שומר TrackPoint עם `positionSource: 'manual'`, accuracy = -1
3. **Kalman reset**: `forcePosition()` — מאפס את ה-Kalman Filter
4. **PDR anchor reset**: מעדכן את נקודת העיגון למיקום הידני
5. **GPS cooldown**: 5 דקות שבהן GPS לא מתקבל (מונע "החזרה" למיקום GPS ישן)
6. **Step reset**: מונה צעדים → 0

---

## 11. Gap-Fill — PDR בזמן חוסר GPS

כש-GPS לא מגיע יותר מ-3 שניות, המערכת עוברת למצב gap-fill:

1. Timer בודק כל שנייה אם `_lastGpsFixTime + 3s < now`
2. אם כן — מתחבר ל-PDR position stream ורושם נקודות PDR ישירות
3. נקודות gap-fill עם `positionSource: 'pdr_gap_fill'`
4. **עוקפות Kalman** — נרשמות ישירות (PDR כבר מסונן)
5. כש-GPS חוזר — יוצא מ-gap-fill mode אוטומטית

---

## 12. Window Outlier Removal — סינון חריגים

### בעיה
GPS שמדווח נקודה "רחוקה" ואז חוזר — glitch→return pattern.

### פתרון
`_pruneWindowOutliers()` רץ אחרי כל הוספת נקודה:
- חלון של 5 נקודות אחרונות
- בודק אם נקודות אמצע "חריגות" ביחס לנקודה לפניהן ואחריהן
- אם כן — מסיר אותן (הן glitches)

---

## שרשרת Fallback — מתי כל מקור נכנס לפעולה

### מצב רגיל (GPS עובד)
```
GPS accuracy < 50 מ' → משתמש ב-GPS
                       + מעדכן PDR anchor (אם accuracy < 20 מ')
```

### GPS לא מדויק
```
GPS accuracy > 50 מ' → מנסה PDR+Cell hybrid
                       → אם hybrid מדויק יותר מ-GPS → משתמש ב-hybrid
                       → אחרת → משתמש ב-GPS
```

### GPS חסום/מזויף
```
מרחק ממרכז ג"ג > 50 ק"מ → PDR+Cell hybrid
                           → אם נכשל → GPS (עדיף משום דבר)
```

### GPS לא זמין (אין הרשאות / שירות כבוי)
```
אין GPS → PDR+Cell hybrid → Cell בלבד → none
```

### GPS נכשל (timeout / שגיאה)
```
שגיאת GPS → PDR+Cell hybrid → Cell בלבד → none
```

---

## כפיית מקור מיקום (forcePositionSource)

המפקד יכול לכפות מקור מיקום ספציפי מ-Firestore (per-track או per-navigation):

| ערך | התנהגות |
|-----|---------|
| `auto` | שרשרת fallback רגילה (ברירת מחדל) |
| `gps` | GPS בלבד — בלי fallback |
| `cellTower` | אנטנות בלבד — דילוג על GPS ו-PDR |
| `pdr` | PDR+Cell hybrid בלבד — דילוג על GPS |

---

## תצוגה למנווט (active_view)

שורת הסטטוס מציגה את מקור המיקום הנוכחי:

| מקור | אייקון | צבע | תווית |
|------|--------|------|-------|
| GPS | `gps_fixed` | ירוק | GPS |
| PDR | `directions_walk` | כתום | PDR |
| PDR+Cell | `directions_walk` + `cell_tower` | כתום | PDR+Cell |
| אנטנות | `cell_tower` | כתום | אנטנות |
| אין מיקום | `gps_off` | אדום | אין מיקום |
| GPS חסום | `gps_off` | אדום | GPS חסום |

---

## TrackPoint — מבנה נקודת מסלול

כל נקודה במסלול שומרת:

| שדה | סוג | הסבר |
|------|------|-------|
| `coordinate` | Coordinate | lat, lng, utm |
| `timestamp` | DateTime | זמן רישום |
| `accuracy` | double | דיוק במטרים (-1 לידני) |
| `altitude` | double? | גובה (GPS או DEM) |
| `speed` | double? | מהירות GPS |
| `heading` | double? | כיוון |
| `positionSource` | String | `'gps'`, `'cellTower'`, `'pdr'`, `'pdrCellHybrid'`, `'pdr_gap_fill'`, `'manual'` |
| `activityType` | String? | `'standing'`, `'walking'`, `'running'` — סוג פעילות ברגע הרישום |

---

## מחזור חיים (Lifecycle)

```
התחלת ניווט
  ├─ initPdr() — בדיקת חיישנים + הפעלת שירות
  │  └─ ActivityClassifier מתחיל לקבל נתוני accel + steps
  ├─ startTracking() — התחלת רישום נקודות + Anti-Drift subscription
  │
  │  [לולאת מעקב כל X שניות]
  │  ├─ Jamming SM — בודק דיוק + מהירות GPS
  │  ├─ Anti-Drift — בודק ZUPT (אין צעדים > 5s?)
  │  ├─ Velocity validation — GPS vs step distance
  │  ├─ Jump gate — displacement + speed check
  │  ├─ Kalman filter — החלקה (motion-aware)
  │  ├─ Activity classifier — standing/walking/running
  │  ├─ Step length — Weinberg × activity multiplier
  │  ├─ Window outlier removal — glitch→return
  │  └─ TrackPoint(positionSource, activityType)
  │
  │  [gap-fill: GPS חסר > 3s]
  │  └─ PDR stream ישיר → TrackPoint(pdr_gap_fill)
  │
סיום ניווט
  ├─ stopTracking() — עצירת רישום
  └─ stopPdr() — עצירת חיישנים + איפוס classifier
```

---

## Pipeline מלא — סדר פעולות

```
1. GPS raw fix מתקבל
   │
2. Jamming State Machine
   ├─ accuracy > 35m? → bad fix counter++
   ├─ speed > 150 km/h? → bad fix counter++
   ├─ 3 consecutive bad fixes → state = jammed → REJECT
   └─ state = recovering? → count good fixes → 2 good → normal
   │
3. GPS Spoofing check
   ├─ distance from boundary center > max? → REJECT, use fallback
   │
4. Anti-Drift (ZUPT)
   ├─ user stationary? (no steps > 5s)
   ├─ displacement > 8m? → REJECT as drift
   │
5. Velocity cross-validation (GPS source only)
   ├─ GPS displacement > 5× walking distance? → REJECT
   │
6. Jump gate (all sources)
   ├─ displacement > 500m AND speed > 150 km/h? → REJECT
   │
7. Kalman Filter
   ├─ motion state update (stationary = tight Q)
   ├─ update(lat, lng, accuracy) → smoothed position
   │
8. Activity Classification
   ├─ PdrActivityType = standing | walking | running
   │
9. Create TrackPoint
   ├─ coordinate, accuracy, positionSource, activityType
   │
10. Window Outlier Removal
    ├─ check last 5 points for glitch→return pattern
    │
11. DEM elevation enrichment (async, fire-and-forget)
```

---

## קבצים רלוונטיים

### gps_plus (חבילה מקומית)
| קובץ | תפקיד |
|-------|--------|
| `android/.../GpsPlusPlugin.kt` | EventChannel + SensorManager — 4 חיישנים |
| `ios/Classes/GpsPlusPlugin.swift` | CoreMotion + CMPedometer — 4 חיישנים |
| `lib/src/models/pdr_position_result.dart` | מודל תוצאת PDR |
| `lib/src/pdr/activity_classifier.dart` | **חדש** — classifier מבוסס cadence + accel |
| `lib/src/pdr/sensor_platform.dart` | Dart wrapper ל-EventChannel |
| `lib/src/pdr/heading_estimator.dart` | Complementary Filter (gyro+mag) |
| `lib/src/pdr/step_length_estimator.dart` | Weinberg + running multiplier (×1.4) |
| `lib/src/pdr/zupt_detector.dart` | ZUPT + adaptive drift + turn detection |
| `lib/src/pdr/pdr_engine.dart` | ליבת PDR — צעד+כיוון→מיקום |
| `lib/src/pdr/pdr_service.dart` | lifecycle + stream + activity integration |
| `lib/gps_plus.dart` | exports (כולל activity_classifier) |

### navigate_app
| קובץ | תפקיד |
|-------|--------|
| `lib/services/gps_service.dart` | שרשרת fallback + PDR hybrid + anchor + activity getter |
| `lib/services/gps_tracking_service.dart` | pipeline מלא: jamming, ZUPT, velocity, jump, Kalman, outlier, activity |
| `lib/services/position_kalman_filter.dart` | Kalman filter (motion-aware) |
| `lib/services/elevation_service.dart` | DEM elevation enrichment |
| `lib/presentation/.../active_view.dart` | תצוגת אייקון מקור מיקום |

---

## אין שינויי DB

- `TrackPoint.positionSource` הוא string גמיש — `'pdr'`, `'pdrCellHybrid'`, `'pdr_gap_fill'`, `'manual'` עובדים אוטומטית
- `TrackPoint.activityType` הוא string אופציונלי — `'standing'`, `'walking'`, `'running'`
- Firestore sync — שדות `positionSource` ו-`activityType` נשמרים ב-track points
- אין מיגרציות Drift
- אין שינויי Navigation entity
