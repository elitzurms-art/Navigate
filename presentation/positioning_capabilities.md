---
marp: true
theme: default
paginate: true
dir: rtl
header: 'Navigate — מערכת מיקום'
footer: 'סודי'
style: |
  section {
    font-family: 'Rubik', 'Arial', sans-serif;
    background: linear-gradient(135deg, #0a1628 0%, #1a2744 100%);
    color: #e0e8f0;
    font-size: 21px;
    direction: rtl;
    text-align: right;
  }
  section * {
    direction: rtl;
    text-align: right;
  }
  section code, section pre {
    direction: ltr;
    text-align: left;
  }
  h1 {
    color: #00d4ff;
    border-bottom: 3px solid #00d4ff;
    padding-bottom: 6px;
    font-size: 32px;
    margin-bottom: 12px;
  }
  h2 {
    color: #7dd3fc;
    font-size: 24px;
  }
  h3 {
    font-size: 20px;
    margin-bottom: 4px;
  }
  section.lead, section.lead * {
    background: linear-gradient(135deg, #0f3460 0%, #16213e 100%);
    text-align: center;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  section.lead h1 {
    border-bottom: none;
    font-size: 48px;
    color: #00d4ff;
  }
  section.lead h2 {
    color: #90e0ef;
    font-size: 24px;
    font-weight: normal;
  }
  table, table * {
    color: #e0e8f0 !important;
    background: none !important;
    background-color: transparent !important;
    background-image: none !important;
    box-shadow: none !important;
    text-shadow: none !important;
    font-size: 18px;
    border-collapse: collapse;
  }
  table {
    width: 100%;
  }
  th {
    background-color: #00609e !important;
    color: #ffffff !important;
    font-weight: bold;
    padding: 4px 8px;
    border: 1px solid #00609e !important;
  }
  td {
    padding: 3px 8px;
    border-bottom: 1px solid rgba(255,255,255,0.2) !important;
  }
  code {
    background-color: rgba(0,212,255,0.1);
    color: #7dd3fc;
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 18px;
  }
  pre {
    font-size: 16px;
    margin: 6px 0;
  }
  .columns {
    display: flex;
    gap: 1.5em;
    direction: rtl;
  }
  .col {
    flex: 1;
  }
  blockquote {
    border-right: 4px solid #00d4ff;
    border-left: none;
    padding-right: 1em;
    color: #90e0ef;
    font-style: italic;
    margin: 6px 0;
  }
  strong {
    color: #00d4ff;
  }
  footer {
    color: #ff6b6b;
    font-weight: bold;
  }
  p { margin: 4px 0; }
  ul, ol { margin: 4px 0; }
---

<!-- _class: lead -->

# Navigate — מערכת מיקום

## יכולות מיקום מתקדמות לאימוני ניווט צבאי

**ריבוי מקורות · Sensor Fusion · עמידות בשיבושים**

---

# סדר יום

1. **ארכיטקטורת מיקום** — סקירת מקורות ושרשרת Fallback
2. **GPS** — מעקב, דיוק, זיהוי שיבושים (Jamming + Spoofing)
3. **אנטנות סלולריות** — Trilateration ו-Path Loss
4. **PDR** — ניווט אינרציאלי רגלי (Weinberg + ZUPT)
5. **Activity Classification** — זיהוי עמידה/הליכה/ריצה
6. **Sensor Fusion** — מסנן קלמן אדפטיבי
7. **Anti-Drift** — ZUPT + Velocity + Jump Gate
8. **Gap-Fill** — מילוי פערי GPS בזמן אמת
9. **Window Outlier Removal** — סינון glitch→return
10. **מיקום ידני** — דקירה על מפה (+ Trim)
11. **PDR+Cell Hybrid** — ממוצע משוקלל
12. **מזג אוויר ואסטרונומיה** — נתונים סביבתיים
13. **התראות מבוססות מיקום** — מעקב אוטומטי
14. **Pipeline מלא** — 11 שלבי סינון ואימות
15. **סיכום ומקרי קצה**

---

# ארכיטקטורת מיקום — סקירה כללית

המערכת מפעילה **4 מקורות מיקום** עם שרשרת Fallback אוטומטית:

```
GPS (geolocator — LocationAccuracy.best)
  ↓ דיוק > 30 מ'
PDR + Cell Hybrid (ממוצע משוקלל)
  ↓ אין חיישנים
Cell Tower Trilateration (3+ אנטנות)
  ↓ פחות מ-3 אנטנות
Weighted Centroid (1-2 אנטנות)
  ↓ אין אנטנות
None — אין מיקום זמין
```

> כל מעבר אוטומטי — המנווט לא מרגיש בשינוי מקור

---

# ארכיטקטורת מיקום — הגדרות per-Navigation

כל ניווט מגדיר **אילו מקורות מיקום מורשים**:

| מקור | ברירת מחדל | שימוש |
|---|---|---|
| `gps` | ✅ | GPS מובנה — מקור ראשי |
| `cellTower` | ✅ | אנטנות סלולריות — fallback |
| `pdr` | ✅ | חיישנים אינרציאליים |
| `pdrCellHybrid` | ✅ | שילוב PDR + סלולרי |

**תדירות GPS**: סליידר 5-120 שניות (ברירת מחדל: 30 שניות)

- **≤5 שניות** → Stream Mode — GPS פועל ברציפות (`LocationAccuracy.best`)
- **>5 שניות** → Timer Mode — GPS נדלק מחזורית (timeout: 10s, חסכון בסוללה)
- **סינון stream**: מינימום `interval × 80%` בין רישומים (מונע הצפה)

**כפיית מקור** (`forcePositionSource`): `auto` / `gps` / `cellTower` / `pdr` — ניתן לדריסה per-navigator

---

# GPS — מעקב בזמן אמת

<div class="columns">
<div class="col">

### Stream Mode (תדירות ≤5 שניות)
- GPS פועל **ברציפות** — `LocationAccuracy.best`
- `distanceFilter: 10` מטרים (מינימום תזוזה)
- PDR Gap-Fill מופעל (מילוי פערים)
- Anti-Drift פעיל (מניעת סחף)
- PDR מאותחל (אינטרוול ≤10 שניות)
- צריכת סוללה **גבוהה**

### Timer Mode (תדירות >5 שניות)
- GPS נדלק **כל N שניות** (timeout: 10 שניות)
- `LocationAccuracy.high` ב-`getCurrentPosition`
- חיסכון משמעותי בסוללה
- מתאים לאימונים ארוכים (יום שלם)

</div>
<div class="col">

### מבנה TrackPoint
```
coordinate    — lat, lng, utm
accuracy      — דיוק במטרים (-1 לידני)
altitude      — גובה (GPS או DEM)
speed         — מהירות GPS
heading       — כיוון
positionSource — gps / cellTower / pdr /
                 pdrCellHybrid /
                 pdr_gap_fill / manual
activityType  — standing / walking / running
timestamp     — זמן רישום
```

- שמירה מקומית (SQLite) + סנכרון ל-Firebase כל 2 דקות (batch)

</div>
</div>

---

# GPS — זיהוי שיבושים (Jamming State Machine)

<div class="columns">
<div class="col">

### מכונת מצבים

```
Normal ──[3 bad fixes]──► Jammed
  ▲                          │
  │    ◄──[bad fix]──────────┤
  │                          │
  │  ◄──[2nd good]── Recovering
  │                     ▲
  └─[good fix (reset)]  │
                  [1st good fix]
```

| מצב | תנאי כניסה |
|---|---|
| **Jammed** | 3 fixes רצופים "גרועים" |
| **Recovering** | fix טוב ראשון (דיוק ≤35 מ') |
| **Normal** | fix טוב שני ברצף |

### תנאים ל-"fix גרוע" (`_isGpsFixGood = false`)
- דיוק GPS > **35 מ'**
- מהירות משתמעת > **150 קמ"ש** (41.67 מ'/ש) ו-dt > 0.5s

</div>
<div class="col">

### תגובות אוטומטיות

**כשמזהים Jamming:**
- מעבר ל-PDR Gap-Fill
- התראה למפקד
- המשך מעקב ברקע

**כשמתאוששים:**
- חזרה ל-GPS
- עדכון עוגן PDR
- ריסט Kalman Filter


</div>
</div>

---

# GPS — זיהוי GPS Spoofing

<div class="columns">
<div class="col">

### מנגנון
- השוואת מיקום GPS מול **מרכז גבול הגזרה**
- אם המרחק > סף מוגדר — חשד ל-Spoofing
- **סף ברירת מחדל**: 50 ק"מ
- **ניתן להגדרה per-navigation** (`gpsSpoofingMaxDistanceKm`)

### תגובה
1. מעבר ל-PDR+Cell Hybrid כמקור ראשי
2. אם Hybrid לא זמין — חזרה ל-GPS (עדיף משום דבר)
3. התראה למפקד על חריגת מיקום

</div>
<div class="col">

### למה 50 ק"מ?
- אימון ניווט טיפוסי: רדיוס 5-15 ק"מ
- תנועה טבעית לא תחרוג מעשרות ק"מ
- Spoofing בדרך כלל שולח לקואורדינטות רחוקות

### מתי מופעל בבדיקה
- בתוך `_isGpsFixGood` — חלק ממכונת Jamming
- **וגם** ב-fallback chain של `gps_service.dart`
- פועל בשני שלבים: גם כ-"fix גרוע" וגם כ-trigger ל-fallback

</div>
</div>

---

# אנטנות סלולריות — Path Loss Model

<div class="columns">
<div class="col">

### נוסחת המרחק (Log-Distance)
```
distance = 10 ^ ((txPower - RSSI) / (10 × n))
```

### עוצמת שידור לפי טכנולוגיה

| טכנולוגיה | txPower | שימוש |
|---|---|---|
| GSM / CDMA / UMTS | 43 dBm | 2G / 3G |
| LTE | 46 dBm | 4G |
| NR | 49 dBm | 5G |

### מקדם דעיכה אדפטיבי (n)

| מספר אנטנות | n | סביבה |
|---|---|---|
| 5+ | 3.8 | עירונית צפופה |
| 3-4 | 3.0 | פרבר |
| 1-2 | 2.5 | שטח פתוח |

</div>
<div class="col">

### גבולות פלט

| פרמטר | טווח |
|---|---|
| RSSI קלט | -140 עד -20 dBm |
| מרחק פלט | 10 מ' עד 50 ק"מ |
| Cache | 3 שניות |

### דיוק צפוי

| סביבה | אנטנות | אלגוריתם | דיוק |
|---|---|---|---|
| עירונית | 5+ | Trilateration | 100-500 מ' |
| פרבר | 3-4 | Trilateration | 300-2,000 מ' |
| כפרי | 1-2 | Centroid | 1-5 ק"מ |

### מסד נתונים: OpenCellID
- **MCC 425** — ישראל
- SQLite מקומי — מובנה באפליקציה
- חיפוש: MCC, MNC, LAC, CID

</div>
</div>

---

# אנטנות סלולריות — אלגוריתם Trilateration

<div class="columns">
<div class="col">

### עקרון: חיתוך מעגלי מרחק מ-3+ אנטנות

**אלגוריתם (Least Squares):**
1. המרת אנטנות לקואורדינטות מקומיות (מטרים)
2. בניית מערכת משוואות ליניאריות
3. פתרון: `x = (AᵀA)⁻¹ AᵀB`
4. המרה חזרה ל-Lat/Lon
5. חישוב RMSE כדיוק

**ניפוח PDOP (Dilution of Precision):**

| פיזור אנטנות | מקדם | משמעות |
|---|---|---|
| < 30° | ×3.0 | מקובצות — דיוק גרוע |
| 30°–60° | ×1.5 | בינוני |
| > 60° | ×1.0 | פיזור טוב |

</div>
<div class="col">

### Weighted Centroid (1-2 אנטנות)
- כש-Trilateration נכשל (אנטנות קו-ליניאריות)
- או כשיש פחות מ-3 אנטנות

```
position = Σ(tower_i × weight_i) / Σ(weight_i)
weight = 1 / distance²
```

- דיוק: מאות מטרים עד קילומטרים
- מספיק כדי לתת **כיוון כללי**

</div>
</div>

---

# PDR — ניווט אינרציאלי רגלי

<div class="columns">
<div class="col">

### Pedestrian Dead Reckoning — מיקום מחיישנים בלבד

**רכיבים:**

| רכיב | תפקיד |
|---|---|
| **StepLengthEstimator** | אומדן אורך צעד (Weinberg) |
| **ZuptDetector** | זיהוי עצירה + סחף אדפטיבי |
| **HeadingEstimator** | כיוון (98% gyro + 2% mag) |
| **ActivityClassifier** | עמידה / הליכה / ריצה |
| **PdrEngine** | שילוב צעדים + כיוון → מיקום |

**חיישנים נדרשים (50 Hz):**
- Accelerometer, Gyroscope, Magnetometer, Pedometer

</div>
<div class="col">

**עקרון הפעולה:**
```
1. זיהוי צעד (Pedometer)
2. ActivityClassifier → סוג פעילות
3. אומדן אורך (Weinberg × activity)
4. חישוב כיוון (Gyro+Mag)
5. ZUPT check — דיכוי false steps
6. עדכון מיקום:
   dN = cos(heading) × stepLength
   dE = sin(heading) × stepLength
   lat += dN / 111,320
   lon += dE / (111,320 × cos(lat))
```

> **יתרון מפתח**: פועל ללא GPS, ללא רשת — חיישנים בלבד

</div>
</div>

---

# PDR — אומדן אורך צעד (Weinberg)

<div class="columns">
<div class="col">

### נוסחה
```
stepLength = K × (aMax - aMin) ^ (1/4)
```

| פרמטר | ערך | הסבר |
|---|---|---|
| **K** (`_k`) | 0.41 | קבוע Weinberg |
| **aMax** | — | שיא תאוצה בין צעדים |
| **aMin** | — | שפל תאוצה בין צעדים |
| `_minSamples` | 5 | מינימום דגימות לאומדן |
| `_minStepLength` | 0.3 מ' | Clamp תחתון |
| `_maxStepLength` | 1.8 מ' | Clamp עליון |
| `defaultStepLength` | 0.7 מ' | fallback (< 5 דגימות) |
| `_runningMultiplier` | ×1.4 | מכפיל ריצה |

</div>
<div class="col">

### אלגוריתם
1. אם `standing` → return **0.0** (ZUPT)
2. אם < 5 דגימות → return **0.7 מ'** (× 1.4 בריצה)
3. חישוב magnitude: `√(x² + y² + z²)`
4. מציאת min/max → הפרש → שורש רביעי
5. אם `running` → כפל × 1.4
6. Clamp: **[0.3, 1.8] מ'**

### מכפיל פעילות

| פעילות | מכפיל | אורך צעד |
|---|---|---|
| עמידה | ×0 | 0 (ZUPT) |
| הליכה | ×1.0 | Weinberg ישיר |
| ריצה | ×1.4 | Weinberg × 1.4 |

</div>
</div>

---

# PDR — זיהוי עצירה (ZUPT)

<div class="columns">
<div class="col">

### Zero-Velocity Update — מניעת סחף

**עקרון:**
- חלון הזזה של **50 דגימות תאוצה**
- חישוב **שונות** (variance)
- שונות < **0.15** (m/s²)² → **עומד במקום**
- צעדים נדחים (`shouldProcessStep() = false`)

**מצבי סחף:**

| מצב | סחף לצעד | הסבר |
|---|---|---|
| עומד | 0.0% | אין סחף כלל |
| הליכה ישרה | 2.0% | בסיסי |
| פנייה חדה | עד 6.0% | שגיאת כיוון מצטברת |

</div>
<div class="col">

### זיהוי פנייה (אדפטיבי)
- סף פנייה: **0.3 rad/s** (~17°/שנייה)
- מקדם: `turnFactor = ((rate - 0.3) / 0.3).clamp(0, 1)`
- drift = `0.02 + turnFactor × 0.04`

### נוסחת דיוק PDR
```
accuracy = totalDistance × adaptiveDriftPerStep
clamp: [1 מ', 500 מ']
```

**דוגמה:**
- 500 מ' הליכה ישרה → דיוק: **10 מ'**
- 500 מ' עם פניות חדות → דיוק: **30 מ'**
- עמידה → דיוק: **0 מ'** (קפוא)


</div>
</div>

---

# זיהוי סוג פעילות — Activity Classification

<div class="columns">
<div class="col">

### Classifier מבוסס חיישנים (ללא Google Play Services)

**אלגוריתם:**
```
1. Step cadence = צעדים/שנייה
   (חלון הזזה — 10 צעדים אחרונים)
   cadence = (count-1) / span

2. Accel variance = שונות 100 דגימות
   (magnitude בריבוע — ללא sqrt)

3. סיווג:
   אין צעדים > 3 שניות → standing
   cadence ≥ 2.5 steps/sec → running
   accel variance ≥ 8.0  → running
   אחרת               → walking
```

</div>
<div class="col">

### ערכי סף (`activity_classifier.dart`)

| פרמטר | ערך |
|---|---|
| `_runningCadenceThreshold` | 2.5 צעדים/שנייה |
| `_runningAccelVariance` | 8.0 (magnitude²) |
| `_standingTimeout` | 3 שניות ללא צעדים |
| `_stepWindowSize` | 10 צעדים |
| `_accelWindowSize` | 100 דגימות |
| `_runningMultiplier` | ×1.4 |

**שימוש:**
- **PDR**: אורך צעד אדפטיבי (ריצה ×1.4)
- **מטה-דאטה**: כל TrackPoint שומר `activityType`
- **ללא תלות חיצונית**: עובד ללא Play Services
- **Accel magnitude²**: `x*x + y*y + z*z` (ללא sqrt, לביצועים)

</div>
</div>

---

# PDR — תמיכת iOS (CoreMotion)

<div class="columns">
<div class="col">

### אינטגרציה Native — Swift

| חיישן | Framework | המרה | קצב |
|---|---|---|---|
| Accelerometer | CMAcceleration | G → m/s² (×9.81) | 50 Hz |
| Gyroscope | CMRotationRate | rad/s (ישיר) | 50 Hz |
| Magnetometer | CMMagneticField | µT (ישיר) | 50 Hz |
| Pedometer | CMPedometer | מצטבר → דלתא | Real-time |

### זיהוי צעדים
```swift
let newSteps = currentSteps - lastStepCount
for _ in 0..<newSteps {
    sink(["type": "step", "timestamp": ...])
}
```

</div>
<div class="col">

### זרימת אירועים (pdr_service.dart)
```
'step'  → ActivityClassifier.onStep()
        → StepLengthEstimator.onStep()
        → PdrEngine.onStep()
        → emit position (if not ZUPT)

'accel' → StepLengthEstimator.onAccel()
        → ActivityClassifier.onAccel()
        → PdrEngine.onAccel()

'gyro'  → PdrEngine.onGyro()
'mag'   → PdrEngine.onMag()
```

### Graceful Fallback
- **אין חיישנים** (מכשיר ישן) → PDR מושבת
- GPS עובד כרגיל ללא פגיעה
- Anti-Drift + Gap-Fill פשוט מבוטלים

</div>
</div>

---

# Sensor Fusion — מסנן קלמן אדפטיבי

<div class="columns">
<div class="col">

### Position Kalman Filter
**וקטור מצב:** `[x, y, vx, vy]` — מיקום + מהירות (מטרים מקומיים)

### רעש תהליך אדפטיבי (Q)

| מצב | Q | משמעות |
|---|---|---|
| GPS טוב (5 מ') | 1.0 | סומכים על GPS |
| GPS בינוני (10 מ') | 0.5 | מאוזן |
| GPS גרוע (100 מ') | 0.05 | מתנגדים לרעש |
| **עומד (ZUPT)** | **0.001** | נעילת מיקום — 500× פחות |

### נוסחה
```
scale = clamp(10 / gpsAccuracy, 0.1, 2.0)
Q = 0.5 × scale

אם עומד (ZUPT): Q = 0.001 (override)
  + velocity forced to zero (vx=0, vy=0)
```

</div>
<div class="col">

### פרמטרים (`position_kalman_filter.dart`)
| פרמטר | ערך |
|---|---|
| `_qBase` | 0.5 |
| `_qStationary` | 0.001 |
| `_referenceAccuracy` | 10.0 מ' |
| `_qMinScale` | 0.1 |
| `_qMaxScale` | 2.0 |

### מקרי איפוס

| מצב | תגובה |
|---|---|
| פער זמן > **60 שניות** | איפוס מלא |
| דיוק > **5,000 מ'** | דילוג — חיזוי בלבד |
| dt < **0.01 שניות** | דילוג |
| מטריצה סינגולרית | דילוג על עדכון |

### המרת קואורדינטות
- 1° lat = **110,540** מ'
- 1° lon = **111,320 × cos(lat)** מ'

</div>
</div>

---

# Anti-Drift — מניעת סחף GPS

### בעיה: GPS "זז" גם כשעומדים במקום

<div class="columns">
<div class="col">

### פתרון 1: ZUPT — דחייה גורפת בעמידה

**תנאים** (`_shouldRejectAsDrift`):
1. ✅ המנווט **עומד** (אין צעדים > 5 שניות)
2. ✅ **0 צעדים** מאז המדידה האחרונה
3. ✅ יש נקודות קיימות במסלול

**תוצאה: כל GPS נדחה** — ללא סף מרחק
(כשעומדים, *כל* GPS הוא jitter)

```
"ZUPT: stationary + 0 steps
 → rejecting ALL GPS positions"
```

> **Bypass**: לא פעיל בזמן Jamming recovery

</div>
<div class="col">

### פתרון 2: Step-GPS Cross-Validation

**תנאים** (`_isVelocityAnomalous`):
1. ✅ GPS displacement > **10 מ'** (מוחלט)
2. ✅ dt ≤ **30 שניות** (אחרת — מידע לא אמין)
3. ✅ displacement / expected > **5.0**

**חישוב:**
```
maxExpected = steps × 1.2m × 2.0
ratio = gpsDisplacement / maxExpected
אם ratio > 5.0 AND displacement > 10m
  → דחייה
```

### פתרון 3: Jump Gate (כל מקור)

**שניהם חייבים להתקיים:**
- displacement > **500 מ'**
- מהירות משתמעת > **150 קמ"ש** (41.67 m/s)

</div>
</div>

---

# Gap-Fill — מילוי פערי GPS

<div class="columns">
<div class="col">

### בעיה: GPS נעלם — חור במסלול

### פתרון: PDR ממלא את הפער אוטומטית

**טריגר** (Stream Mode + Jamming):
- טיימר 1 שנייה בודק:
- `now - lastGpsFix > 3 שניות` → Gap-Fill
- **או** מכונת Jamming עברה ל-jammed

**בזמן Gap-Fill:**
- הרשמה לזרם PDR
- כל צעד PDR → TrackPoint עם `pdr_gap_fill`
- **עוקף Kalman** — מיקום PDR גולמי
- עדכון מפה בזמן אמת

**יציאה:**
- GPS חוזר → ביטול הרשמת PDR
- חזרה למצב רגיל

</div>
<div class="col">

### דוגמת תרחיש

```
00:00 — GPS פעיל (5 מ' דיוק)
00:03 — GPS אבד (בניין/עצים)
00:04 — Gap-Fill מופעל
00:04 — PDR: צעד 1 (0.72 מ')
00:05 — PDR: צעד 2 (0.68 מ')
00:06 — PDR: צעד 3 (0.75 מ')
  ...
00:15 — GPS חוזר (8 מ' דיוק)
00:15 — Gap-Fill מושבת
00:15 — עוגן PDR מתעדכן
```

**תוצאה:** מסלול רציף ללא חורים

> **הערה**: Gap-Fill רץ גם כש-Jamming מזוהה — מעבר אוטומטי ל-PDR

</div>
</div>

---

# Window Outlier Removal — סינון חריגים

<div class="columns">
<div class="col">

### בעיה: GPS glitch→return

GPS שמדווח נקודה "רחוקה" ואז חוזר — יוצר "שיניים" במסלול.

### אלגוריתם (`_pruneWindowOutliers`)

1. חלון של **5 נקודות אחרונות**
2. לכל נקודת אמצע (1–3), בדיקת "רגליים":
   - רגל ← = מהנקודה הקודמת
   - רגל → = לנקודה הבאה
3. אם **שתי הרגליים בלתי אפשריות**:
   - מהירות > **150 קמ"ש** (41.67 m/s)
   - **וגם** מרחק > **800 מ'**
4. **וגם** חיבור ישיר בין השכנות סביר:
   - מהירות < **150 קמ"ש**
   - **וגם** מרחק < **300 מ'**
5. → הנקודה מוסרת (glitch)

</div>
<div class="col">

### דוגמה ויזואלית
```
A ──── B ──── C ──── D ──── E
             ↑
          חריגה?

B→C: 1200m, 200 km/h (impossible ✅)
C→D: 1100m, 190 km/h (impossible ✅)
B→D: 150m, 30 km/h   (plausible ✅)

→ C מוסרת!
```

### פרמטרים

| פרמטר | ערך |
|---|---|
| `windowSize` | 5 נקודות |
| `minJumpDistance` | 800 מ' |
| direct `maxDistance` | 300 מ' |
| `maxSpeedMps` | 41.67 m/s |

</div>
</div>

---

# מיקום ידני — דקירה על מפה

<div class="columns">
<div class="col">

### מתי מופעל
- המפקד מגדיר `allowManualPosition = true`
- כפתור דקירה מופיע במסך הניווט הפעיל

### מה קורה (`recordManualPosition`)
1. **Trim** — מחיקת נקודות אחורה שרחוקות > **5 ק"מ**
2. רישום TrackPoint: `positionSource: 'manual'`, accuracy = **-1**
3. **Window Outlier Pruning** — ניקוי חריגים
4. **מסנן קלמן מתאפס** (`forcePosition`)
   - מיקום מוגדר, accuracy = 30 מ'
   - velocity variance = 4.0
5. **עוגן PDR מתאפס** לנקודה
6. **GPS cooldown** — **5 דקות** ללא GPS
7. **איפוס צעדים** — `_stepsSinceLastRecord = 0`
   `_lastStepTime = null`

</div>
<div class="col">

### Cooldown (5 דקות)
- `_manualCooldownDuration = Duration(minutes: 5)`
- מונע GPS לסתור את הדקירה הידנית
- PDR ממשיך לעקוב מהנקודה החדשה
- אחרי 5 דקות — GPS חוזר לפעולה

### למה Trim?
- אם המנווט דקר מיקום רחוק מאוד מנקודות קודמות, הנקודות הישנות "מושכות" את המסלול
- מחיקה > 5 ק"מ מנקה artifacts ברורים
- שומרת נקודות קרובות (ייתכן שלגיטימיות)

### Cooldown Bypass
- `_recordPointFromLatLng` (cell/PDR) **לא** נחסם
- רק GPS source נדחה בזמן cooldown

</div>
</div>

---

# PDR+Cell Hybrid — שילוב חכם

<div class="columns">
<div class="col">

### כשגם PDR וגם אנטנות זמינים — ממוצע משוקלל

**נוסחה:**
```
pdrWeight  = cellAccuracy / (pdrAccuracy + cellAccuracy)
cellWeight = pdrAccuracy  / (pdrAccuracy + cellAccuracy)

hybridLat = pdrLat × pdrWeight + cellLat × cellWeight
hybridLng = pdrLng × pdrWeight + cellLng × cellWeight
hybridAcc = pdrAcc × pdrWeight + cellAcc × cellWeight
```

**לוגיקה:** מקור עם **דיוק גרוע** מקבל **משקל נמוך**

### דוגמה

| מקור | דיוק | משקל |
|---|---|---|
| PDR | 15 מ' | 300 / (15+300) = **95%** |
| Cell Tower | 300 מ' | 15 / (15+300) = **5%** |

</div>
<div class="col">

### מתי משתמשים (`gps_service.dart`)
- GPS accuracy > **30 מ'** → מנסה hybrid
  - hybrid מחליף GPS רק אם **דיוק hybrid טוב יותר**
- GPS spoofed → hybrid כ-fallback
- GPS לא זמין → hybrid → cell בלבד → null

### Fallback chain מלאה
```
1. getCurrentPosition (GPS, 10s timeout)
2. בדיקת spoofing (מרחק מגבול)
3. בדיקת דיוק (> 30m?)
   → if yes: getPdrCellHybridPosition
   → use hybrid only if better accuracy
4. on GPS failure:
   → getPdrCellHybridPosition
   → or null
```


</div>
</div>

---

# מזג אוויר ואסטרונומיה

<div class="columns">
<div class="col">

### מזג אוויר — OpenWeatherMap API

| פרמטר | פלט | שימוש |
|---|---|---|
| **טמפרטורה** | °C | תכנון ציוד + התראות |
| **תיאור** | עברית | מצב מזג אוויר |
| **רוח** | m/s | השפעה על ניווט |
| **לחות** | % | נוחות מנווט |

### התראות אוטומטיות

| תנאי | התראה |
|---|---|
| טמפרטורה > 35°C | חום קיצוני — שתיית מים |
| טמפרטורה < 5°C | קור קיצוני — ביגוד |
| רוח > 15 m/s | רוחות חזקות |

</div>
<div class="col">

### אסטרונומיה — חישוב מקומי (ללא API)

**זריחה/שקיעה (NOAA):**
```
declination = -23.45° × cos(2π/365 × (d+10))
hourAngle = acos(...)
sunrise = 12 - hourAngle/15 - EoT/60 + tz
sunset  = 12 + hourAngle/15 - EoT/60 + tz
```
- דיוק: ±2 דקות

**הארת ירח:**
```
phase = (daysSinceNewMoon % 29.53) / 29.53
illumination = (1 - cos(phase × 2π)) / 2
```
- 0.0 = ירח חדש (חשוך)
- 1.0 = ירח מלא (מואר)

**שימוש:** תכנון ניווט לילי, הערכת תנאי ראות

</div>
</div>

---

# התראות מבוססות מיקום

### מעקב אוטומטי בזמן אמת

| התראה | תנאי | Cooldown |
|---|---|---|
| **חריגת מהירות** | מהירות GPS > סף מוגדר | 3 דק' |
| **יציאה מגבול גזרה** | מחוץ לפוליגון ג"ג | 5 דק' |
| **סטייה מציר** | מרחק מציר מתוכנן > סף | 5 דק' |
| **קרבה לנ"ב** | בתוך N מטרים מנקודת בטיחות | 5 דק' |
| **חוסר תנועה** | < 10 מ' הזזה למשך N דקות | 10 דק' |
| **קרבת מנווטים** | < N מטרים ממנווט אחר | per-nav |

### סף דיוק GPS
- אם דיוק GPS > **50 מ'** → **כל הבדיקות מושבתות** (מונע false positives)

### זרם אירועים
- כל עדכון מיקום → בדיקת שרשרת התראות → התראה ראשונה שמופעלת → שליחה למפקד

---

# Pipeline מלא — סדר פעולות

<div class="columns">
<div class="col">

### GPS source (`_recordPoint`)
```
 1. Anti-Drift (ZUPT)
    stationary + 0 steps? → REJECT

 2. Velocity cross-validation
    disp > 5× (steps×1.2×2.0)
    AND disp > 10m
    AND dt ≤ 30s? → REJECT

 3. Jump gate
    disp > 500m AND
    speed > 150 km/h? → REJECT

 4. Kalman Filter
    adaptive Q + ZUPT override

 5. Add TrackPoint

 6. Window Outlier Removal
    (5-point window)

 7. Reset step counter

 8. DEM elevation (async)
```

</div>
<div class="col">

### Cell/PDR source (`_recordPointFromLatLng`)
```
 1. Jump gate only
    disp > 500m AND
    speed > 150 km/h? → REJECT

 2. Kalman Filter
    adaptive Q + ZUPT override

 3. Add TrackPoint

 4. Window Outlier Removal

 5. Reset step counter

 6. DEM elevation (async)
```

### לפני ה-Pipeline (Jamming SM)
```
GPS raw fix
  → accuracy > 35m? → bad++
  → speed > 150 km/h? → bad++
  → spoofing? → bad++
  → 3 bad → jammed → Gap-Fill
```


</div>
</div>

---

# סיכום — ספי סינון ואימות

| מדד | ערך | משתנה בקוד |
|---|---|---|
| סף דיוק GPS ל-Fallback | > **30 מ'** | `_accuracyThreshold` |
| סף Jamming | > **35 מ'** × 3 fixes | `_jammingAccuracyThreshold` |
| סף Recovery | ≤ **35 מ'** × 2 fixes | `_recoveryAccuracyThreshold` |
| סף Spoofing | > **50 ק"מ** (ניתן להגדרה) | `_gpsSpoofingMaxDistanceMeters` |
| Anti-Drift (ZUPT) | עומד + 0 צעדים → **דחייה גורפת** | `_shouldRejectAsDrift` |
| סף Velocity | disp > **5×** expected + > **10 מ'** | `_isVelocityAnomalous` |
| סף Jump Gate | > **500 מ'** + > **150 קמ"ש** | `_isJumpAnomalous` |
| Outlier — legs | > **800 מ'** + > **150 קמ"ש** | `minJumpDistance` |
| Outlier — direct | < **300 מ'** + < **150 קמ"ש** | `directPlausible` |
| Gap-Fill trigger | > **3 שניות** ללא GPS | `_gapThreshold` |

---

# סיכום — פרמטרי מערכת

| מדד | ערך | משתנה בקוד |
|---|---|---|
| עוגן PDR (נע) | < **20 מ'** | `gps_service.dart` |
| עוגן PDR (עומד) | < **40 מ'** | `gps_service.dart` |
| Kalman Q (עומד) | **0.001** | `_qStationary` |
| Cooldown דקירה | **5 דקות** | `_manualCooldownDuration` |
| Trim דקירה | > **5 ק"מ** | `trimThresholdMeters` |
| צעד Weinberg | **0.3–1.8 מ'** | `_minStepLength`/`_maxStepLength` |
| מכפיל ריצה | **×1.4** | `_runningMultiplier` |
| סחף PDR (ישר) | **2%** לצעד | `_baseDrift` |
| סחף PDR (פנייה) | עד **6%** לצעד | `_maxDrift` |
| Distance Safety Net | מדלג > **150 קמ"ש** | `getTotalDistance()` |

---

# סיכום — מקרי קצה ותגובות

| תרחיש | תגובת המערכת |
|---|---|
| **כניסה למבנה** (GPS אבד) | Gap-Fill: PDR ממלא פערים (>3 שניות) |
| **שיבוש GPS** (Jamming) | 3 fixes >35 מ' → jammed → PDR + Cell Hybrid |
| **GPS Spoofing** | מרחק > סף מגבול (50 ק"מ ברירת מחדל) → Fallback |
| **עמידה במקום** | ZUPT: כל GPS נדחה (0 צעדים), Kalman Q=0.001 |
| **נסיעה ברכב** | Velocity >5× expected + Jump Gate >500 מ' → דחייה |
| **ריצה** | Activity Classifier → מכפיל ×1.4 לאורך צעד PDR |
| **יער צפוף** (GPS גרוע) | Kalman Q נמוך: מתנגד לרעש, סומך על מודל |
| **אין חיישנים** (מכשיר ישן) | Graceful fallback: GPS רגיל, PDR מושבת |
| **אימון יום שלם** | Timer Mode (30s): חיסכון בסוללה |
| **המנווט אבוד** | דקירה ידנית + Trim 5 ק"מ + cooldown 5 דק' |
| **שטח פתוח** (GPS מעולה) | Kalman Q גבוה: מקבל GPS מהר |
| **glitch→return** | Window Outlier: חלון 5, legs >800 מ' → הסרה |
| **ניווט לילי** | נתוני ירח + שקיעה לתכנון |

---

<!-- _class: lead -->

# Navigate — מערכת מיקום

## ריבוי מקורות · Sensor Fusion · עמידות בשיבושים

**4 מקורות** | **קלמן אדפטיבי** | **ZUPT** | **Gap-Fill** | **Jamming** | **Jump Gate**

> שאלות?
