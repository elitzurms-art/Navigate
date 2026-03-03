import '../../domain/entities/unit_checklist.dart';

/// 4 צ'קליסטים ברירת מחדל ליחידה חדשה
List<UnitChecklist> kDefaultUnitChecklists() {
  final now = DateTime.now();
  return [
  // ──────────────────────────────────────────────
  // 1. צ'ק ליסט חפ"ק
  // ──────────────────────────────────────────────
  UnitChecklist(
    id: 'default_hafkak',
    title: 'צ\'ק ליסט חפ"ק',
    isMandatory: false,
    createdAt: now,
    updatedAt: now,
    sections: [
      ChecklistSection(id: 'ds_haf_vehicle', title: 'רכב', items: [
        ChecklistItem(id: 'di_haf_v1', title: 'ג\'יפ רנגלר / סופה'),
        ChecklistItem(id: 'di_haf_v2', title: 'נהג ערני עם רישיון והיתר בתוקף'),
        ChecklistItem(id: 'di_haf_v3', title: 'מיכל דלק מלא'),
        ChecklistItem(id: 'di_haf_v4', title: 'כלי נהג'),
        ChecklistItem(id: 'di_haf_v5', title: 'רצועת גרירה (מומלץ)'),
        ChecklistItem(id: 'di_haf_v6', title: 'שאקלים (מומלץ)'),
        ChecklistItem(id: 'di_haf_v7', title: 'שקע מצת עובד'),
        ChecklistItem(id: 'di_haf_v8', title: 'בדיקת אורות'),
        ChecklistItem(id: 'di_haf_v9', title: 'בדיקת גלגל רזרבי + כלי החלפה'),
        ChecklistItem(id: 'di_haf_v10', title: 'בדיקת מטף'),
        ChecklistItem(id: 'di_haf_v11', title: 'בדיקת אפוד זוהר'),
        ChecklistItem(id: 'di_haf_v12', title: 'ביצוע תל"ת'),
      ]),
      ChecklistSection(id: 'ds_haf_comms', title: 'קשר ובקרה', items: [
        ChecklistItem(id: 'di_haf_c1', title: 'מכשיר קשר נייח (עדיפות למכלול 122)'),
        ChecklistItem(id: 'di_haf_c2', title: 'ק.פ. ערוצים (מומלץ)'),
        ChecklistItem(id: 'di_haf_c3', title: 'מעדים למפקד ולקצין ניווט'),
        ChecklistItem(id: 'di_haf_c4', title: 'תדרים מכויילים'),
        ChecklistItem(id: 'di_haf_c5', title: 'בדיקת קשר מול גורם מרוחק'),
        ChecklistItem(id: 'di_haf_c6', title: 'ציוד להחלפה - מעדים, אנטנות, סוללות'),
        ChecklistItem(id: 'di_haf_c7', title: 'מכשיר קשר נייד מכוייל (למקרה של פריקה לחילוץ)'),
        ChecklistItem(id: 'di_haf_c8', title: 'בקר / מחשב משואה'),
        ChecklistItem(id: 'di_haf_c9', title: 'מטען לרכב תקין לבקר / מחשב'),
      ]),
      ChecklistSection(id: 'ds_haf_nav', title: 'ניווט', items: [
        ChecklistItem(id: 'di_haf_n1', title: 'קצין ניווט'),
        ChecklistItem(id: 'di_haf_n2', title: 'תיק ניווט מלא ומאושר'),
        ChecklistItem(id: 'di_haf_n3', title: 'דף משתנים'),
        ChecklistItem(id: 'di_haf_n4', title: 'דף תיאום קרקע בטוחה'),
        ChecklistItem(id: 'di_haf_n5', title: 'מפת מאסטר עם נקודות ציון, נת"בים'),
        ChecklistItem(id: 'di_haf_n6', title: 'תסריט חפ"ק ורכב פינוי'),
        ChecklistItem(id: 'di_haf_n7', title: 'שקפי צירי הניווט של כלל המנווטים'),
        ChecklistItem(id: 'di_haf_n8', title: 'טבלת שליטה'),
        ChecklistItem(id: 'di_haf_n9', title: 'הוראות קשר מרחביות'),
        ChecklistItem(id: 'di_haf_n10', title: 'בזנ"טים וסס"ל לסימון נת"בים'),
        ChecklistItem(id: 'di_haf_n11', title: 'אמצעי מיקום ספייר - פלאפונים עם אפליקציה / דרוריות / משיבי מיקום'),
      ]),
      ChecklistSection(id: 'ds_haf_med', title: 'רפואה', items: [
        ChecklistItem(id: 'di_haf_m1', title: 'חובש'),
        ChecklistItem(id: 'di_haf_m2', title: 'מס\' טלפון של גורם רפואי זמין בזמן הניווט'),
        ChecklistItem(id: 'di_haf_m3', title: 'ציוד חובש'),
        ChecklistItem(id: 'di_haf_m4', title: 'פנס ראש'),
        ChecklistItem(id: 'di_haf_m5', title: 'קסטרל'),
        ChecklistItem(id: 'di_haf_m6', title: 'אלונקה תקינה'),
        ChecklistItem(id: 'di_haf_m7', title: '2 מכלי מים 20 ליטר'),
        ChecklistItem(id: 'di_haf_m8', title: '2 שמיכות'),
        ChecklistItem(id: 'di_haf_m9', title: '2 שק"ש (לחימום)'),
      ]),
      ChecklistSection(id: 'ds_haf_emrg', title: 'חירום', items: [
        ChecklistItem(id: 'di_haf_e1', title: 'מספרי טלפון חיוניים - מסוקים, חמ"ל, בתי חולים, רופא זמין'),
        ChecklistItem(id: 'di_haf_e2', title: 'ערכת הנחתה למסוק'),
        ChecklistItem(id: 'di_haf_e3', title: 'M-203 מטול'),
        ChecklistItem(id: 'di_haf_e4', title: '6 רימוני תאורה / 6 תאורה ידנית'),
        ChecklistItem(id: 'di_haf_e5', title: 'עיפרון / אקדח זיקוקים ו-3 זיקוקים'),
        ChecklistItem(id: 'di_haf_e6', title: 'סטיקלייטים אדומים וירוקים'),
      ]),
    ],
  ),

  // ──────────────────────────────────────────────
  // 2. צ'ק ליסט רכב פינוי
  // ──────────────────────────────────────────────
  UnitChecklist(
    id: 'default_pinui',
    title: 'צ\'ק ליסט רכב פינוי',
    isMandatory: false,
    createdAt: now,
    updatedAt: now,
    sections: [
      ChecklistSection(id: 'ds_pin_vehicle', title: 'רכב', items: [
        ChecklistItem(id: 'di_pin_v1', title: 'רכב 4*4 אשר מאפשר פינוי פצוע במצב שכיבה'),
        ChecklistItem(id: 'di_pin_v2', title: 'נהג ערני עם רישיון והיתר בתוקף'),
        ChecklistItem(id: 'di_pin_v3', title: 'מיכל דלק מלא'),
        ChecklistItem(id: 'di_pin_v4', title: 'רצועת גרירה (מומלץ)'),
        ChecklistItem(id: 'di_pin_v5', title: 'שאקלים (מומלץ)'),
        ChecklistItem(id: 'di_pin_v6', title: 'שקע מצת עובד'),
        ChecklistItem(id: 'di_pin_v7', title: 'בדיקת אורות'),
        ChecklistItem(id: 'di_pin_v8', title: 'בדיקת גלגל רזרבי + כלי החלפה'),
        ChecklistItem(id: 'di_pin_v9', title: 'בדיקת מטף'),
        ChecklistItem(id: 'di_pin_v10', title: 'בדיקת אפוד זוהר'),
        ChecklistItem(id: 'di_pin_v11', title: 'ביצוע תל"ת'),
      ]),
      ChecklistSection(id: 'ds_pin_comms', title: 'קשר ובקרה', items: [
        ChecklistItem(id: 'di_pin_c1', title: 'מכשיר קשר נייח / קשר מוגבר טעון'),
        ChecklistItem(id: 'di_pin_c2', title: 'מעד + סוללות ספיר (אם זה קשר מוגבר)'),
        ChecklistItem(id: 'di_pin_c3', title: 'תדרים מכויילים'),
        ChecklistItem(id: 'di_pin_c4', title: 'בדיקת קשר מול גורם מרוחק'),
        ChecklistItem(id: 'di_pin_c5', title: 'מכשיר קשר נייד מכוייל (למקרה של פריקה לחילוץ)'),
        ChecklistItem(id: 'di_pin_c6', title: 'אפליקציה / דרורית / משיב מיקום'),
      ]),
      ChecklistSection(id: 'ds_pin_nav', title: 'ניווט', items: [
        ChecklistItem(id: 'di_pin_n1', title: 'מפת מאסטר עם נקודות ציון, נת"בים'),
        ChecklistItem(id: 'di_pin_n2', title: 'תסריט חפ"ק ורכב פינוי'),
      ]),
      ChecklistSection(id: 'ds_pin_med', title: 'רפואה', items: [
        ChecklistItem(id: 'di_pin_m1', title: 'מס\' טלפון של גורם רפואי זמין בזמן הניווט'),
        ChecklistItem(id: 'di_pin_m2', title: 'אלונקה תקינה'),
        ChecklistItem(id: 'di_pin_m3', title: '2 ג\'ריקנים של 20 ל\' כל אחד'),
        ChecklistItem(id: 'di_pin_m4', title: 'מדים להחלפה'),
        ChecklistItem(id: 'di_pin_m5', title: '3 שק"ש + 6 שמיכות'),
        ChecklistItem(id: 'di_pin_m6', title: '20 שקיות חימום'),
      ]),
      ChecklistSection(id: 'ds_pin_photo', title: 'צלם', items: [
        ChecklistItem(id: 'di_pin_p1', title: 'בטחונית צלם'),
        ChecklistItem(id: 'di_pin_p2', title: 'אין צלם מחוץ לבטחונית'),
      ]),
      ChecklistSection(id: 'ds_pin_general', title: 'כללי', items: [
        ChecklistItem(id: 'di_pin_g1', title: 'ציוד פריסה ושתייה'),
        ChecklistItem(id: 'di_pin_g2', title: 'בדיקה כי תא המטען אינו מלא ומאפשר פינוי בשכיבה – עם הציוד'),
      ]),
    ],
  ),

  // ──────────────────────────────────────────────
  // 3. צ'ק ליסט סיור שטח
  // ──────────────────────────────────────────────
  UnitChecklist(
    id: 'default_siyur',
    title: 'צ\'ק ליסט סיור שטח',
    isMandatory: false,
    createdAt: now,
    updatedAt: now,
    sections: [
      ChecklistSection(id: 'ds_siy_pre', title: 'מקדים', items: [
        ChecklistItem(id: 'di_siy_p1', title: 'וידוא תיאום שטח הניווט מול המתא"ם רלוונטי'),
        ChecklistItem(id: 'di_siy_p2', title: 'וידוא המצאות תיק שטח האש / אזרחי'),
        ChecklistItem(id: 'di_siy_p3', title: 'וידוא המצאות תיק ניווט'),
        ChecklistItem(id: 'di_siy_p4', title: 'תיאום כלל בעלי התפקידים שחייבים להשתתף מפקד הניווט, קצין הניווט ומפקד רכב הפינוי'),
        ChecklistItem(id: 'di_siy_p5', title: 'תאום הסיור ודיווח כניסה לשטח'),
      ]),
      ChecklistSection(id: 'ds_siy_during', title: 'בסיור עצמו', items: [
        ChecklistItem(id: 'di_siy_d1', title: 'הכרת כלל הנת"בים המופיעים בתיק השטח ותיק הניווט'),
        ChecklistItem(id: 'di_siy_d2', title: 'איתור נת"בים בשטח'),
        ChecklistItem(id: 'di_siy_d3', title: 'מתן מענה לכלל הסיכונים והנת"בים המופיעים בתיק'),
        ChecklistItem(id: 'di_siy_d4', title: 'מתן מענה לנת"בים החדשים שהתגלו במסגרת הסיור כולל סימון ומענה מתאים לכל נת"ב'),
        ChecklistItem(id: 'di_siy_d5', title: 'עדכון הגורם הרלוונטי (מתא"ם / יחידה בעלת השטח) בנת"בים שהתגלו'),
        ChecklistItem(id: 'di_siy_d6', title: 'מתן מענה הולם לנת"בים שאותרו'),
        ChecklistItem(id: 'di_siy_d7', title: 'בדיקת מפות שטחי אש שכנים ודרכי קשר'),
        ChecklistItem(id: 'di_siy_d8', title: 'הכרת המגבלות המרחביות של השטח'),
      ]),
      ChecklistSection(id: 'ds_siy_physical', title: 'מעבר פיזית במקומות הבאים', items: [
        ChecklistItem(id: 'di_siy_f1', title: 'נקודת התחלה'),
        ChecklistItem(id: 'di_siy_f2', title: 'מעבר חובה או נקודת בקרה'),
        ChecklistItem(id: 'di_siy_f3', title: 'מיקומי עצירות החפ"ק ורכב הפינוי - בדיקת קליטה לפלאפון ולבקר קריטי!'),
        ChecklistItem(id: 'di_siy_f4', title: 'נקודות חציית כבישים'),
        ChecklistItem(id: 'di_siy_f5', title: 'תכנון ובדיקת צירי הפינוי והפו"ש ועבירותם'),
      ]),
    ],
  ),

  // ──────────────────────────────────────────────
  // 4. צ'ק ליסט הוצאת ניווט
  // ──────────────────────────────────────────────
  UnitChecklist(
    id: 'default_hotzaa',
    title: 'צ\'ק ליסט הוצאת ניווט',
    isMandatory: false,
    createdAt: now,
    updatedAt: now,
    sections: [
      ChecklistSection(id: 'ds_hot_prep', title: 'הכנות מקדימות', items: [
        ChecklistItem(id: 'di_hot_pr1', title: 'סיור שטח'),
        ChecklistItem(id: 'di_hot_pr2', title: 'מילוי דף משתנים'),
        ChecklistItem(id: 'di_hot_pr3', title: 'אישור דף משתנים ורישום הנחיות מפקד'),
      ]),
      ChecklistSection(id: 'ds_hot_navs', title: 'מנווטים', items: [
        ChecklistItem(id: 'di_hot_n1', title: 'בדיקת בקיאות החיילים בהוראות בטיחות ותחקירים'),
        ChecklistItem(id: 'di_hot_n2', title: 'בדיקת ביצוע מבחן ניווט / בדד בהתאם לנדרש בתקופת האימון האחרונה'),
        ChecklistItem(id: 'di_hot_n3', title: 'אישור צירים ושקפי בטיחות'),
        ChecklistItem(id: 'di_hot_n4', title: 'תדריך בטיחות על ידי מפקד הניווט'),
        ChecklistItem(id: 'di_hot_n5', title: 'חלוקת מספרי ברזל'),
        ChecklistItem(id: 'di_hot_n6', title: 'תשאול רפואי'),
        ChecklistItem(id: 'di_hot_n7', title: 'בדיקות חובש (כולל מדדים בניווט בדד)'),
        ChecklistItem(id: 'di_hot_n8', title: 'הפנייה לרופא וקבלת תשובות על מנווטים עם מדדים חריגים'),
        ChecklistItem(id: 'di_hot_n9', title: 'בדיקת ציוד למנווטים - נשק וווסט מלא לפי פק"ל יחידתי, מכשיר קשר מכוייל, מחסנית נותבים מסומנת, מים לפי חישוב ציר הניווט, פנס ראש, 2 סטיקלייטים לסימון בורות או מפגעים חדשים, סימון סטיקלייט בצבע אחיד על גבי החיילים במידה ויש ציידים בשטח, חבל אישי, מד קורדינטות, מצפן, שעון תקין, פנקס, עיפרון/עט, כובע וביגוד חם בצב בהתאם לעונה'),
        ChecklistItem(id: 'di_hot_n10', title: 'חבירה לנהג אוטובוס'),
      ]),
      ChecklistSection(id: 'ds_hot_vehicles', title: 'רכבים', items: [
        ChecklistItem(id: 'di_hot_vh1', title: 'מסדר רכב פינוי ורכב חפ"ק (ע"פ צ\'ק ליסט)'),
        ChecklistItem(id: 'di_hot_vh2', title: 'וידוא פריסה / ארוחה'),
        ChecklistItem(id: 'di_hot_vh3', title: 'תדריך נהגים ומפקדים ומילוי כרטיס עבודה'),
      ]),
      ChecklistSection(id: 'ds_hot_phones', title: 'טלפונים', items: [
        ChecklistItem(id: 'di_hot_ph1', title: 'חבירה טלפונית ע"פ קרקע בטוחה ורישום הנחיות'),
        ChecklistItem(id: 'di_hot_ph2', title: 'חבירה טלפונית לחמ"ל רלוונטי להקפצת מסוק (פקע"ר / אוגמ"ר)'),
      ]),
      ChecklistSection(id: 'ds_hot_field', title: 'הכנות בשטח', items: [
        ChecklistItem(id: 'di_hot_f0', title: 'דיווח כניסה לשטח לחמ"ל / מתא"ם'),
        ChecklistItem(id: 'di_hot_f0b', title: 'חבירה לכוחות שכנים'),
        ChecklistItem(id: 'di_hot_f0c', title: 'סריקת נפלים בניווט בשטח אש'),
        ChecklistItem(id: 'di_hot_f0d', title: 'תדריך בטיחות למעטפת - מנהלה'),
        ChecklistItem(id: 'di_hot_f1', title: 'מדידת עומס חום / קור'),
        ChecklistItem(id: 'di_hot_f2', title: 'וידוא מערכות קשר ובקרה'),
      ]),
      ChecklistSection(id: 'ds_hot_go', title: 'ניווט', items: [
        ChecklistItem(id: 'di_hot_g1', title: 'גמר שילוחים'),
        ChecklistItem(id: 'di_hot_g2', title: 'ביצוע תרגיל חפ"ק למצב קיצון'),
        ChecklistItem(id: 'di_hot_g3', title: 'דילוג לנק\' חפ"ק / מעבר חובה'),
        ChecklistItem(id: 'di_hot_g4', title: 'סיום ניווט ומסדרי אנשים, צלם וציוד'),
        ChecklistItem(id: 'di_hot_g5', title: 'דיווח יציאה מהשטח לחמ"ל / מתא"ם'),
      ]),
      ChecklistSection(id: 'ds_hot_general', title: 'כללי', items: [
        ChecklistItem(id: 'di_hot_gl1', title: 'ערכת הנחתת מסוק'),
        ChecklistItem(id: 'di_hot_gl2', title: 'ציוד לחציית כביש - 2 פנסים ו-2 אפודות זוהרות'),
      ]),
      ChecklistSection(id: 'ds_hot_end', title: 'הגעה לבסיס', items: [
        ChecklistItem(id: 'di_hot_e1', title: 'סריקת אוטובוס'),
        ChecklistItem(id: 'di_hot_e2', title: 'וידוא אנשים, צלם וציוד'),
      ]),
    ],
  ),
];
}
