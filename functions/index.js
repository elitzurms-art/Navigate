const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

/**
 * Trigger: כשנוצרת התראה חדשה על מנווט — שליחת push למפקדים
 *
 * Path: navigations/{navigationId}/navigator_alerts/{alertId}
 */
exports.onNavigatorAlert = onDocumentCreated(
  "navigations/{navigationId}/navigator_alerts/{alertId}",
  async (event) => {
    const alertData = event.data.data();
    const { navigationId } = event.params;

    // דילוג על health_report — אינפורמטיבי בלבד
    if (alertData.type === "healthReport" || alertData.type === "health_report") {
      console.log("Skipping health_report alert");
      return;
    }

    try {
      // 1. קריאת מסמך הניווט
      const navDoc = await db.collection("navigations").doc(navigationId).get();
      if (!navDoc.exists) {
        console.log(`Navigation ${navigationId} not found`);
        return;
      }
      const navData = navDoc.data();
      const treeId = navData.treeId;

      // 2. קריאת עץ הניווט לקבלת תתי-מסגרות (מפקדים)
      const treeDoc = await db.collection("navigator_trees").doc(treeId).get();
      if (!treeDoc.exists) {
        console.log(`Tree ${treeId} not found`);
        return;
      }
      const treeData = treeDoc.data();
      const subFrameworks = treeData.subFrameworks || [];

      // 3. איסוף מזהי מפקדים מתתי-מסגרות
      const commanderIds = new Set();
      for (const sf of subFrameworks) {
        const users = sf.users || [];
        for (const user of users) {
          // מפקדים ומנהלת + כל מי שיש לו כובע מפקד
          if (user.role === "commander" || user.role === "unit_admin" || user.role === "admin") {
            commanderIds.add(user.uid || user.personalNumber);
          }
        }
      }

      // fallback — יוצר הניווט
      if (navData.createdBy) {
        commanderIds.add(navData.createdBy);
      }

      if (commanderIds.size === 0) {
        console.log("No commanders found for notification");
        return;
      }

      // 4. איסוף FCM tokens מ-users collection
      const tokens = [];
      const commanderArray = Array.from(commanderIds);

      // Firestore 'in' query supports max 30 items
      for (let i = 0; i < commanderArray.length; i += 30) {
        const batch = commanderArray.slice(i, i + 30);
        const usersSnap = await db
          .collection("users")
          .where("uid", "in", batch)
          .get();

        for (const userDoc of usersSnap.docs) {
          const userData = userDoc.data();
          if (userData.fcmToken) {
            tokens.push(userData.fcmToken);
          }
        }
      }

      if (tokens.length === 0) {
        console.log("No FCM tokens found for commanders");
        return;
      }

      // 5. בניית הודעה
      const alertType = alertData.type || "unknown";
      const navigatorName = alertData.navigatorName || alertData.navigatorId || "מנווט";
      const navName = navData.name || "ניווט";

      const emojiMap = {
        emergency: "\u{1F6A8}",
        boundary: "\u{1F6A7}",
        safetyPoint: "\u{26A0}\u{FE0F}",
        speed: "\u{1F3CE}\u{FE0F}",
        routeDeviation: "\u{1F500}",
        noMovement: "\u{1F6D1}",
        noReception: "\u{1F4F5}",
        battery: "\u{1F50B}",
        barbur: "\u{1F6A7}",
        proximity: "\u{1F465}",
        healthCheckExpired: "\u{23F0}",
      };
      const emoji = emojiMap[alertType] || "\u{1F514}";

      // עדיפות גבוהה להתראות חירום/גבול/בטיחות
      const highPriorityTypes = ["emergency", "boundary", "safetyPoint"];
      const androidPriority = highPriorityTypes.includes(alertType) ? "high" : "normal";

      const displayNames = {
        emergency: "חירום",
        boundary: "חריגה מגבול",
        safetyPoint: "קרבה לנת\"ב",
        speed: "מהירות חריגה",
        routeDeviation: "סטייה מציר",
        noMovement: "חוסר תנועה",
        noReception: "חוסר קליטה",
        battery: "סוללה חלשה",
        barbur: "ברבור",
        proximity: "קרבה למנווט",
        healthCheckExpired: "דוח בריאות פג",
      };
      const displayName = displayNames[alertType] || alertType;

      const message = {
        notification: {
          title: `${emoji} ${displayName}`,
          body: `${navigatorName} — ${navName}`,
        },
        data: {
          navigationId: navigationId,
          alertId: event.params.alertId,
          alertType: alertType,
        },
        android: {
          priority: androidPriority,
        },
        tokens: tokens,
      };

      // 6. שליחה
      const response = await messaging.sendEachForMulticast(message);
      console.log(
        `Sent ${response.successCount}/${tokens.length} notifications for ${alertType} alert`
      );

      // ניקוי tokens שנכשלו
      if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success && resp.error) {
            const code = resp.error.code;
            if (
              code === "messaging/invalid-registration-token" ||
              code === "messaging/registration-token-not-registered"
            ) {
              console.log(`Removing invalid token for index ${idx}`);
              // ניקוי token לא תקף מהמשתמש (אופציונלי)
            }
          }
        });
      }
    } catch (error) {
      console.error("Error sending push notification:", error);
    }
  }
);

/**
 * Scheduled: ניקוי הודעות קוליות ישנות (מעל 7 ימים)
 *
 * מוחק את הקבצים מ-Firebase Storage ואת המסמכים מ-Firestore.
 * רץ כל 24 שעות.
 */
exports.cleanupOldVoiceMessages = onSchedule("every 24 hours", async () => {
  const expirationMs = 7 * 24 * 60 * 60 * 1000;
  const cutoffDate = new Date(Date.now() - expirationMs);

  let storageDeleted = 0;
  let firestoreDeleted = 0;

  // 1. מחיקת קבצי אודיו מ-Storage
  try {
    const bucket = getStorage().bucket();
    const [files] = await bucket.getFiles({ prefix: "voice_messages/" });

    const deletePromises = [];
    for (const file of files) {
      const created = new Date(file.metadata.timeCreated);
      if (created < cutoffDate) {
        deletePromises.push(file.delete());
        storageDeleted++;
      }
    }
    await Promise.all(deletePromises);
  } catch (error) {
    console.error("Error cleaning Storage files:", error);
  }

  // 2. מחיקת מסמכי הודעות מ-Firestore (rooms/{navId}/messages)
  try {
    const roomsSnap = await db.collection("rooms").get();

    for (const roomDoc of roomsSnap.docs) {
      const messagesSnap = await roomDoc.ref
        .collection("messages")
        .where("createdAt", "<", cutoffDate)
        .limit(500)
        .get();

      if (messagesSnap.empty) continue;

      const batch = db.batch();
      for (const msgDoc of messagesSnap.docs) {
        batch.delete(msgDoc.ref);
        firestoreDeleted++;
      }
      await batch.commit();
    }
  } catch (error) {
    console.error("Error cleaning Firestore messages:", error);
  }

  console.log(
    `Cleanup done: ${storageDeleted} storage files, ${firestoreDeleted} Firestore messages deleted`
  );
});
