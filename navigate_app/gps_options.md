# מערכת מיקום — GPS, PDR ו-Cell Tower

## סקירה כללית

המערכת משתמשת בשלושה מקורות מיקום בשרשרת fallback אוטומטית:

```
GPS (ראשי) → PDR+Cell hybrid (משני) → Cell Tower בלבד (שלישי) → none
```

המנווט לא צריך לעשות שום דבר — המעבר בין מקורות הוא אוטומטי לחלוטין.

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

2. **זיהוי צעדים** — חיישן Step Detector של המכשיר מזהה כל צעד. אורך צעד קבוע: 0.7 מ'.

3. **חישוב כיוון** — Complementary Filter שמשלב:
   - **98% ג'ירוסקופ** — מדויק לטווח קצר, נותן שינוי כיוון בזמן אמת
   - **2% מגנטומטר** — מתקן סחיפה לטווח ארוך (מצפן מגנטי)

4. **עדכון מיקום** — בכל צעד, המיקום מתקדם 0.7 מ' בכיוון הנוכחי:
   ```
   lat += cos(heading) × 0.7 / 111,320
   lon += sin(heading) × 0.7 / (111,320 × cos(lat))
   ```

### דיוק
- **שגיאה מצטברת**: ~2% מכל צעד (0.014 מ' לצעד)
- 100 צעדים (~70 מ') → שגיאה ~1.4 מ'
- 1,000 צעדים (~700 מ') → שגיאה ~14 מ'
- כל GPS fix טוב מאפס את השגיאה חזרה ל-0

### חיישנים נדרשים (Android)
| חיישן | תפקיד | חובה? |
|--------|--------|-------|
| Step Detector | זיהוי צעדים | כן |
| Gyroscope | שינוי כיוון (מהיר) | כן (או מגנטומטר) |
| Magnetometer | כיוון מוחלט (מצפן) | כן (או ג'ירוסקופ) |
| Accelerometer | שמור לעתיד (אורך צעד דינמי) | לא |

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

## מחזור חיים (Lifecycle)

```
התחלת ניווט
  ├─ initPdr() — בדיקת חיישנים + הפעלת שירות
  ├─ startTracking() — התחלת רישום נקודות
  │
  │  [לולאת מעקב כל X שניות]
  │  ├─ GPS fix טוב → שמור נקודה + עדכן PDR anchor
  │  ├─ GPS לא טוב → fallback ל-PDR+Cell hybrid
  │  └─ GPS נכשל → fallback ל-PDR+Cell → Cell → none
  │
סיום ניווט
  ├─ stopTracking() — עצירת רישום
  └─ stopPdr() — עצירת חיישנים + איפוס
```

---

## קבצים רלוונטיים

### gps_plus (חבילה מקומית)
| קובץ | תפקיד |
|-------|--------|
| `android/.../GpsPlusPlugin.kt` | EventChannel + SensorManager — 4 חיישנים |
| `lib/src/models/pdr_position_result.dart` | מודל תוצאת PDR |
| `lib/src/pdr/sensor_platform.dart` | Dart wrapper ל-EventChannel |
| `lib/src/pdr/heading_estimator.dart` | Complementary Filter (gyro+mag) |
| `lib/src/pdr/pdr_engine.dart` | ליבת PDR — צעד+כיוון→מיקום |
| `lib/src/pdr/pdr_service.dart` | lifecycle + stream management |

### navigate_app
| קובץ | תפקיד |
|-------|--------|
| `lib/services/gps_service.dart` | שרשרת fallback + PDR hybrid + anchor |
| `lib/services/gps_tracking_service.dart` | PDR lifecycle + GPS anchor reset |
| `lib/presentation/.../active_view.dart` | תצוגת אייקון מקור מיקום |

---

## אין שינויי DB

- `TrackPoint.positionSource` הוא string גמיש — `'pdr'` ו-`'pdrCellHybrid'` עובדים אוטומטית
- Firestore sync — שדה `positionSource` כבר מסונכרן
- אין מיגרציות Drift
- אין שינויי Navigation entity
