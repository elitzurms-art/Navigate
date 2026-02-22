const admin = require('firebase-admin');

// Use Firebase CLI credentials via gcloud
const { execSync } = require('child_process');

// Get access token from Firebase CLI
function getAccessToken() {
  try {
    const result = execSync('firebase login:ci --no-localhost 2>/dev/null || echo ""', { encoding: 'utf-8' });
    return result.trim();
  } catch (e) {
    return null;
  }
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'navigate-native' });
}

const db = admin.firestore();

async function seedQuiz() {
  console.log('Seeding solo quiz questions...');

  // Config
  await db.collection('solo_quiz_config').doc('settings').set({
    passingScore: 85,
    totalQuestions: 10,
  });
  console.log('Config saved.');

  // Questions
  const questions = [
    // === הצהרות מוכנות (isReadiness: true, לא נספרות בציון) ===
    {
      order: 1,
      type: 'yes_no',
      question: 'האם אתה מעיד על עצמך כי רמת הניווט שלך טובה ומעלה?',
      options: [],
      correctAnswers: [0], // כן
      isReadiness: true,
    },
    {
      order: 2,
      type: 'yes_no',
      question: 'האם אתה מסוגל לממש תכונות אופי: התמדה, אמינות, אחריות, מקצועיות, חברות, חוסן, קבלת החלטות?',
      options: [],
      correctAnswers: [0],
      isReadiness: true,
    },
    {
      order: 3,
      type: 'yes_no',
      question: 'האם ביצעת מעל 10 ניווטי לילה?',
      options: [],
      correctAnswers: [0],
      isReadiness: true,
    },
    {
      order: 4,
      type: 'yes_no',
      question: 'קראת והבנת את התחקירים?',
      options: [],
      correctAnswers: [0],
      isReadiness: true,
    },
    {
      order: 5,
      type: 'yes_no',
      question: 'קראת והבנת את ההוראות?',
      options: [],
      correctAnswers: [0],
      isReadiness: true,
    },

    // === שאלות ידע (נספרות בציון, סף 85%) ===
    {
      order: 6,
      type: 'single',
      question: 'מהי הגישה הנכונה לניווט בדד?',
      options: [
        'גישת זהירות קיצונית',
        'זהירות קיצונית, הימנע מסיטואציות בלתי הפיכות',
        'סיים משימה בכל מחיר',
      ],
      correctAnswers: [1],
      isReadiness: false,
    },
    {
      order: 7,
      type: 'single',
      question: 'מהו הלקח המשותף מ-3 התחקירים?',
      options: [
        'בצע הערכת מצב',
        'הימנע ממזג אוויר קיצוני',
        'קבל אישור מפקד גדוד',
        'אין ניווט בדד ללא טלפון',
      ],
      correctAnswers: [0],
      isReadiness: false,
    },
    {
      order: 8,
      type: 'single',
      question: 'מהו מצב הנשק בניווט בדד?',
      options: [
        'סטרילי - ללא מחסנית',
        'מצב לבן - מחסנית נפרדת',
        'שחור/לבן לפי החלטת מפקד',
      ],
      correctAnswers: [0],
      isReadiness: false,
    },
    {
      order: 9,
      type: 'single',
      question: 'מהו מרחק הבטיחות המינימלי מכביש/מסילת רכבת?',
      options: [
        '100 מ\'',
        '30 מ\'',
        '50 מ\'',
        '10 מ\'',
      ],
      correctAnswers: [2],
      isReadiness: false,
    },
    {
      order: 10,
      type: 'multiple',
      question: 'מהם השלבים בניהול אובדן קשר עם מנווט? (סמן את כל התשובות הנכונות)',
      options: [
        'דיווח לחפ"ק',
        'מפקד מאשר סטטוס מנווט',
        'אחרי שעתיים, הפעלת נהלי חיפוש',
        'מנווט מסמן עם פנס/אותות',
        'שימוש במעקב מערכת קשר',
      ],
      correctAnswers: [0, 1, 2, 3, 4],
      isReadiness: false,
    },
    {
      order: 11,
      type: 'single',
      question: 'מהם סימני החיים החובה לפני ניווט בדד?',
      options: [
        'חום, לחץ דם',
        'חום, דופק, לחץ דם',
        'חום, דופק',
        'דופק, לחץ דם',
      ],
      correctAnswers: [1],
      isReadiness: false,
    },
    {
      order: 12,
      type: 'single',
      question: 'כמה ניווטי לילה מוצלחים בזוגות נדרשים לפני הסמכה לניווט בדד?',
      options: [
        '10 ניווטי לילה',
        '10 ניווטי לילה מוצלחים',
        '8 ניווטי לילה מוצלחים',
        '10 ניווטי יום/לילה',
      ],
      correctAnswers: [1],
      isReadiness: false,
    },
    {
      order: 13,
      type: 'single',
      question: 'מהו הנוהל כשמנווט נפצע בניווט בדד?',
      options: [
        'יקרא בקשר ויעביר דו"ח, ירי של 3 כדורים כל 5 דקות, יטפס לנקודה גבוהה',
        'ימתין במקום ויחכה לחילוץ',
        'ינסה להגיע לנקודה הקרובה ביותר',
      ],
      correctAnswers: [0],
      isReadiness: false,
    },
    {
      order: 14,
      type: 'single',
      question: 'מה עושים כשאין קשר מעל שעה?',
      options: [
        'טפס לנקודה גבוהה, מצא קליטה',
        'בנה מצבה',
        'שתי התשובות נכונות',
        'המתן במקום',
      ],
      correctAnswers: [2],
      isReadiness: false,
    },
    {
      order: 15,
      type: 'single',
      question: 'מה עושים במזג אוויר חמור (גל חום)?',
      options: [
        'עצור, דווח למפקד',
        'המשך משימה',
        'טפס גבוה יותר',
      ],
      correctAnswers: [0],
      isReadiness: false,
    },
  ];

  const batch = db.batch();
  for (const q of questions) {
    const ref = db.collection('solo_quiz_questions').doc();
    batch.set(ref, q);
  }
  await batch.commit();
  console.log(`${questions.length} questions saved.`);
  console.log('Done!');
}

seedQuiz().catch(console.error);
