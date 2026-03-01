const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");
const nodemailer = require("nodemailer");

initializeApp();

const db = getFirestore();
const auth = getAuth();
const messaging = getMessaging();

// =========================================================================
// Helper: Send verification email via nodemailer (SMTP direct)
// =========================================================================
let _smtpTransport = null;

async function sendVerificationEmail(toEmail, code) {
  // יצירת transport אם לא קיים — SMTP_URI מוגדר כ-environment variable
  // פורמט: smtps://user:pass@host:port
  if (!_smtpTransport) {
    const uri = process.env.SMTP_URI;
    if (uri) {
      _smtpTransport = nodemailer.createTransport(uri);
    } else {
      console.log("SMTP_URI not configured — email not sent, code returned in response");
      return false;
    }
  }

  try {
    await _smtpTransport.sendMail({
      from: process.env.SMTP_FROM || "Navigate <noreply@navigate.app>",
      to: toEmail,
      subject: "Navigate - קוד אימות",
      html: `
        <div dir="rtl" style="font-family: Arial, sans-serif; max-width: 400px; margin: 0 auto; padding: 20px;">
          <h2 style="color: #1976D2;">Navigate</h2>
          <p>קוד האימות שלך:</p>
          <div style="background: #f5f5f5; padding: 16px; border-radius: 8px; text-align: center; margin: 16px 0;">
            <span style="font-size: 32px; letter-spacing: 8px; font-weight: bold; color: #1976D2;">${code}</span>
          </div>
          <p style="color: #666; font-size: 14px;">הקוד תקף ל-10 דקות.</p>
        </div>
      `,
    });
    return true;
  } catch (error) {
    console.error("sendVerificationEmail SMTP error:", error.message);
    return false;
  }
}

// =========================================================================
// Helper: Compute unit scope (recursive descendant IDs)
// =========================================================================
async function computeUnitScope(unitId) {
  const scope = [unitId];
  const children = await db
    .collection("units")
    .where("parentId", "==", unitId)
    .get();

  for (const child of children.docs) {
    const childScope = await computeUnitScope(child.id);
    scope.push(...childScope);
  }
  return scope;
}

// =========================================================================
// Known developer UIDs — auto-repaired to role='developer' on initSession
// Fixes corruption from old SyncManager code that pushed local role
// =========================================================================
const DEVELOPER_UIDS = ["6868383"];

// =========================================================================
// Helper: Build custom claims from user data
// =========================================================================
async function buildClaims(userData, personalNumber) {
  const role = userData.role || "navigator";
  const unitId = userData.unitId || null;
  const isApproved = userData.isApproved || false;

  let unitScope = [];
  let hasFullScope = role === "developer" || role === "admin";

  if (!hasFullScope && unitId) {
    unitScope = await computeUnitScope(unitId);
    // Custom claims limit: 1000 bytes total — keep under 800 for safety
    if (JSON.stringify(unitScope).length > 800) {
      hasFullScope = true;
      unitScope = [];
    }
  }

  return {
    appUid: personalNumber,
    role,
    isApproved,
    unitId,
    unitScope,
    hasFullScope,
  };
}

// =========================================================================
// Helper: Wait for custom claims to propagate server-side
// Blocks until admin.auth().getUser() confirms claims are set.
// Prevents client-side race condition where getIdToken(true) fires
// before claims propagate → stale token → permission-denied.
// =========================================================================
async function waitForClaimsPropagation(firebaseUid, expectedAppUid) {
  const maxRetries = 20; // 10 seconds total
  for (let i = 0; i < maxRetries; i++) {
    const userRecord = await auth.getUser(firebaseUid);
    const claims = userRecord.customClaims || {};
    if (claims.appUid === expectedAppUid) return;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error(`Claims propagation timeout for ${expectedAppUid} after 10s`);
}

// =========================================================================
// initSession — Callable: sets custom claims on login
// =========================================================================
exports.initSession = onCall({ region: "us-central1", invoker: "public" }, async (request) => {
  if (!request.auth) {
    throw new Error("Authentication required");
  }

  const firebaseUid = request.auth.uid;
  const personalNumber = request.data.personalNumber;

  if (!personalNumber || typeof personalNumber !== "string") {
    throw new Error("personalNumber is required");
  }

  // Generate session ID server-side (admin write bypasses Firestore rules)
  const sessionId = `${personalNumber}_${Date.now()}`;

  // Read REAL user data from Firestore (source of truth)
  const userDoc = await db.collection("users").doc(personalNumber).get();

  if (!userDoc.exists) {
    // New user — set minimal claims
    await auth.setCustomUserClaims(firebaseUid, {
      appUid: personalNumber,
      role: "navigator",
      isApproved: false,
      unitId: null,
      unitScope: [],
      hasFullScope: false,
    });
    await waitForClaimsPropagation(firebaseUid, personalNumber);
    // Write activeSessionId via admin SDK (no rules restriction)
    await db.collection("users").doc(personalNumber).set(
      { activeSessionId: sessionId },
      { merge: true }
    );
    return { success: true, sessionId };
  }

  const userData = userDoc.data();

  // Auto-repair developer role (fixes corruption from old SyncManager push)
  if (DEVELOPER_UIDS.includes(personalNumber) && userData.role !== "developer") {
    console.log(`Fixing developer role for ${personalNumber} (was: ${userData.role})`);
    await db.collection("users").doc(personalNumber).update({ role: "developer" });
    userData.role = "developer";
  }

  const claims = await buildClaims(userData, personalNumber);
  await auth.setCustomUserClaims(firebaseUid, claims);
  await waitForClaimsPropagation(firebaseUid, personalNumber);

  // Write activeSessionId via admin SDK (no rules restriction)
  await db.collection("users").doc(personalNumber).update({
    activeSessionId: sessionId,
  });

  return { success: true, sessionId };
});

// =========================================================================
// onUserJoinUnit — Push to commanders when a user requests to join a unit
// =========================================================================
exports.onUserJoinUnit = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data.before?.data();
  const after = event.data.after?.data();

  if (!after) return; // deleted doc

  const afterUnitId = after.unitId;
  const afterApproved = after.isApproved === true;
  const beforeUnitId = before?.unitId;
  const beforeApproved = before?.isApproved === true;

  // Only fire when: unitId is newly set AND isApproved is false
  const unitJustSet = afterUnitId && afterUnitId !== beforeUnitId;
  const nowPending = !afterApproved;
  const wasPending = !beforeApproved;

  // Trigger when unit changes to a new value while pending
  // OR when unit stays same but approval status changed from approved → pending (re-join)
  const isJoinEvent = afterUnitId && nowPending && (unitJustSet || (wasPending !== nowPending));
  if (!isJoinEvent) return;

  const uid = event.params.uid;
  const firstName = after.firstName || '';
  const lastName = after.lastName || '';
  const fullName = after.fullName || `${firstName} ${lastName}`.trim() || uid;

  console.log(`User ${uid} (${fullName}) joined unit ${afterUnitId} — notifying commanders`);

  try {
    // Build ancestor chain: the joined unit + all parent units up the hierarchy
    // Commanders at any ancestor unit have scope over the joined unit
    const unitScope = new Set([afterUnitId]);
    let currentUnitId = afterUnitId;
    for (let depth = 0; depth < 10; depth++) { // safety limit
      const unitDoc = await db.collection("units").doc(currentUnitId).get();
      if (!unitDoc.exists) break;
      const parentId = unitDoc.data().parentId;
      if (!parentId) break;
      unitScope.add(parentId);
      currentUnitId = parentId;
    }

    // Find commanders for this unit hierarchy from commander_tokens collection
    const commandersSnap = await db
      .collection("commander_tokens")
      .get();

    const tokens = [];
    for (const doc of commandersSnap.docs) {
      const data = doc.data();
      // Notify commanders whose unitId is in the ancestor chain (same unit or any parent)
      if (data.token && (unitScope.has(data.unitId) || !data.unitId)) {
        tokens.push(data.token);
      }
    }

    // Fallback: also check users collection for commanders in the unit hierarchy
    if (tokens.length === 0) {
      const commanderRoles = ["commander", "unit_admin", "admin", "developer"];
      const scopeArray = Array.from(unitScope);

      // whereIn supports up to 10 values — batch if needed
      const commanderIds = [];
      for (let i = 0; i < scopeArray.length; i += 10) {
        const batch = scopeArray.slice(i, i + 10);
        const usersSnap = await db
          .collection("users")
          .where("unitId", "in", batch)
          .where("isApproved", "==", true)
          .get();

        for (const d of usersSnap.docs) {
          if (commanderRoles.includes(d.data().role)) {
            commanderIds.push(d.id);
          }
        }
      }

      for (let i = 0; i < commanderIds.length; i += 30) {
        const batch = commanderIds.slice(i, i + 30);
        const refs = batch.map((id) => db.collection("commander_tokens").doc(id));
        if (refs.length === 0) continue;
        const docs = await db.getAll(...refs);
        for (const doc of docs) {
          if (doc.exists && doc.data().token) tokens.push(doc.data().token);
        }
      }
    }

    if (tokens.length === 0) {
      console.log(`No commander tokens found for unit ${afterUnitId}`);
      return;
    }

    const message = {
      notification: {
        title: "\u{1F91D} בקשת הצטרפות חדשה",
        body: `${fullName} מבקש להצטרף ליחידה`,
      },
      data: {
        type: "joinRequest",
        userId: uid,
        unitId: afterUnitId,
      },
      android: { priority: "high" },
      tokens,
    };

    const response = await messaging.sendEachForMulticast(message);
    console.log(`Join request push: ${response.successCount}/${tokens.length} sent for ${fullName}`);
  } catch (error) {
    console.error("Error sending join request push:", error);
  }
});

// =========================================================================
// onUserWrite — Trigger: updates claims when user doc changes
// =========================================================================
exports.onUserWrite = onDocumentWritten("users/{uid}", async (event) => {
  const after = event.data.after?.data();
  if (!after || !after.firebaseUid) return; // No Firebase auth → skip

  const before = event.data.before?.data();
  // Only update claims if relevant fields changed
  if (
    before &&
    before.role === after.role &&
    before.unitId === after.unitId &&
    before.isApproved === after.isApproved
  ) {
    return;
  }

  try {
    const personalNumber = event.params.uid;
    const claims = await buildClaims(after, personalNumber);
    await auth.setCustomUserClaims(after.firebaseUid, claims);
    console.log(
      `Updated claims for ${personalNumber} (firebaseUid=${after.firebaseUid}, role=${claims.role})`
    );

    // ניקוי commander_tokens אם הורד מתפקיד מפקד
    const commanderRoles = ["commander", "unit_admin", "admin", "developer"];
    const beforeRole = before ? before.role : null;
    const afterRole = after.role || "navigator";
    if (
      beforeRole &&
      commanderRoles.includes(beforeRole) &&
      !commanderRoles.includes(afterRole)
    ) {
      await db.collection("commander_tokens").doc(personalNumber).delete();
      console.log(`Deleted commander_tokens for ${personalNumber} (role: ${beforeRole} → ${afterRole})`);
    }
  } catch (error) {
    console.error("Error updating custom claims:", error);
  }
});

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

      // 4. איסוף FCM tokens מ-commander_tokens (רק מפקדים פעילים)
      const tokens = [];
      const commanderArray = Array.from(commanderIds);

      // קריאת commander_tokens לפי doc IDs (batch של 30)
      for (let i = 0; i < commanderArray.length; i += 30) {
        const batch = commanderArray.slice(i, i + 30);
        const refs = batch.map((id) =>
          db.collection("commander_tokens").doc(id)
        );
        const docs = await db.getAll(...refs);

        for (const doc of docs) {
          if (doc.exists) {
            const data = doc.data();
            if (data.token) {
              tokens.push(data.token);
            }
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

// =========================================================================
// sendEmailCode — Callable: שליחת קוד אימות למייל (desktop)
// =========================================================================
exports.sendEmailCode = onCall({ region: "us-central1", invoker: "public" }, async (request) => {
  const { email, personalNumber, purpose } = request.data;

  if (!email || !personalNumber) {
    throw new Error("email and personalNumber are required");
  }

  // בכניסה — וידוא שהמשתמש קיים והמייל תואם
  if (purpose === "login") {
    const userDoc = await db.collection("users").doc(personalNumber).get();
    if (!userDoc.exists) {
      throw new Error("user_not_found");
    }
    const userData = userDoc.data();
    if (userData.email && userData.email.toLowerCase() !== email.toLowerCase()) {
      throw new Error("email_mismatch");
    }
  }

  // יצירת קוד 6 ספרות
  const code = String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 דקות

  // שמירה ב-email_codes
  await db.collection("email_codes").doc(personalNumber).set({
    code,
    email: email.toLowerCase(),
    expiresAt,
    attempts: 0,
    createdAt: new Date(),
  });

  // שליחת מייל — nodemailer ישיר (fallback: החזרת קוד בתגובה)
  const emailSent = await sendVerificationEmail(email, code);

  console.log(`Email code for ${personalNumber}: sent=${emailSent} (purpose: ${purpose})`);
  return emailSent ? { success: true } : { success: true, code };
});

// =========================================================================
// verifyEmailCode — Callable: אימות קוד מייל (desktop)
// =========================================================================
exports.verifyEmailCode = onCall({ region: "us-central1", invoker: "public" }, async (request) => {
  const { personalNumber, code } = request.data;

  if (!personalNumber || !code) {
    throw new Error("personalNumber and code are required");
  }

  const docRef = db.collection("email_codes").doc(personalNumber);
  const doc = await docRef.get();

  if (!doc.exists) {
    throw new Error("code_expired");
  }

  const data = doc.data();

  // בדיקת תפוגה
  if (data.expiresAt.toDate() < new Date()) {
    await docRef.delete();
    throw new Error("code_expired");
  }

  // בדיקת מספר ניסיונות
  if (data.attempts >= 5) {
    await docRef.delete();
    throw new Error("max_attempts_exceeded");
  }

  // בדיקת קוד
  if (data.code !== code) {
    await docRef.update({ attempts: data.attempts + 1 });
    throw new Error("invalid_code");
  }

  // הצלחה — מחיקת הקוד
  await docRef.delete();
  console.log(`Email code verified for ${personalNumber}`);
  return { success: true };
});

// =========================================================================
// onExtensionRequestWrite — Push to navigator when commander responds
// =========================================================================
exports.onExtensionRequestWrite = onDocumentWritten(
  "navigations/{navigationId}/extension_requests/{requestId}",
  async (event) => {
    const before = event.data.before?.data();
    const after = event.data.after?.data();

    // Only fire when status transitions from pending to approved/rejected
    if (!before || !after) return;
    if (before.status !== "pending" || after.status === "pending") return;

    const navigatorId = after.navigatorId;
    if (!navigatorId) {
      console.log("No navigatorId on extension request");
      return;
    }

    try {
      // Read navigator's FCM token
      const userDoc = await db.collection("users").doc(navigatorId).get();
      if (!userDoc.exists) {
        console.log(`User ${navigatorId} not found`);
        return;
      }
      const fcmToken = userDoc.data().fcmToken;
      if (!fcmToken) {
        console.log(`No fcmToken for user ${navigatorId}`);
        return;
      }

      // Build notification
      const approved = after.status === "approved";
      const title = approved ? "✅ בקשת הארכה אושרה" : "❌ בקשת הארכה נדחתה";
      const body = approved && after.approvedMinutes
        ? `${after.approvedMinutes} דקות נוספו`
        : undefined;

      const message = {
        notification: { title, ...(body && { body }) },
        data: {
          navigationId: event.params.navigationId,
          requestId: event.params.requestId,
          type: "extensionResponse",
        },
        android: { priority: "high" },
        token: fcmToken,
      };

      await messaging.send(message);
      console.log(`Extension response push sent to ${navigatorId} (${after.status})`);
    } catch (error) {
      console.error("Error sending extension response push:", error);
    }
  }
);

// =========================================================================
// onBarburChecklistUpdate — Push to navigator when commander updates checklist
// =========================================================================
exports.onBarburChecklistUpdate = onDocumentWritten(
  "navigations/{navigationId}/navigator_alerts/{alertId}",
  async (event) => {
    const before = event.data.before?.data();
    const after = event.data.after?.data();

    if (!after) return; // Deleted doc
    if (after.type !== "barbur") return;
    if (!after.isActive) return;

    // Compare checklists — only notify on changes
    const beforeChecklist = (before && before.barburChecklist) || {};
    const afterChecklist = after.barburChecklist || {};

    // Find newly-checked steps (false→true only)
    const stepNames = {
      returnToAxis: "חזרה בציר",
      goToHighPoint: "עלייה למקום גבוה",
      openMap: "פתיחת מפה",
      showLocation: "הצגת מיקום",
    };

    const newlyChecked = [];
    for (const [key, hebrew] of Object.entries(stepNames)) {
      if (afterChecklist[key] === true && beforeChecklist[key] !== true) {
        newlyChecked.push(`✓ ${hebrew}`);
      }
    }

    if (newlyChecked.length === 0) return; // No new steps checked

    const navigatorId = after.navigatorId;
    if (!navigatorId) {
      console.log("No navigatorId on barbur alert");
      return;
    }

    try {
      // Read navigator's FCM token
      const userDoc = await db.collection("users").doc(navigatorId).get();
      if (!userDoc.exists) {
        console.log(`User ${navigatorId} not found`);
        return;
      }
      const fcmToken = userDoc.data().fcmToken;
      if (!fcmToken) {
        console.log(`No fcmToken for user ${navigatorId}`);
        return;
      }

      const message = {
        notification: {
          title: "🚧 עדכון נוהל ברבור",
          body: newlyChecked.join(", "),
        },
        data: {
          navigationId: event.params.navigationId,
          alertId: event.params.alertId,
          type: "barburUpdate",
        },
        android: { priority: "high" },
        token: fcmToken,
      };

      await messaging.send(message);
      console.log(`Barbur checklist push sent to ${navigatorId}: ${newlyChecked.join(", ")}`);
    } catch (error) {
      console.error("Error sending barbur checklist push:", error);
    }
  }
);

// =========================================================================
// onEmergencyBroadcast — Push to all navigators on emergency broadcast creation
// =========================================================================
exports.onEmergencyBroadcast = onDocumentCreated(
  "navigations/{navigationId}/emergency_broadcasts/{broadcastId}",
  async (event) => {
    const broadcastData = event.data.data();
    const { navigationId, broadcastId } = event.params;

    const navName = (await db.collection("navigations").doc(navigationId).get()).data()?.name || "ניווט";
    const participants = broadcastData.participants || [];

    if (participants.length === 0) {
      console.log(`No participants for emergency broadcast ${broadcastId}`);
      return;
    }

    // Batch-fetch FCM tokens from users collection
    const tokens = [];
    for (let i = 0; i < participants.length; i += 30) {
      const batch = participants.slice(i, i + 30);
      const refs = batch.map((id) => db.collection("users").doc(id));
      const docs = await db.getAll(...refs);
      for (const doc of docs) {
        if (doc.exists) {
          const token = doc.data().fcmToken;
          if (token) tokens.push(token);
        }
      }
    }

    if (tokens.length === 0) {
      console.log(`No FCM tokens for emergency broadcast ${broadcastId}`);
      return;
    }

    const fcmType = broadcastData.type === 'cancellation'
      ? 'emergencyCancelled'
      : 'emergencyBroadcast';

    const message = {
      notification: {
        title: fcmType === 'emergencyCancelled'
          ? `✅ חזרה לשגרה — ${navName}`
          : `\u{1F6A8} שידור חירום — ${navName}`,
        body: broadcastData.message || '',
      },
      data: {
        type: fcmType,
        navigationId,
        broadcastId,
        message: broadcastData.message || '',
        instructions: broadcastData.instructions || '',
        emergencyMode: String(broadcastData.emergencyMode ?? 0),
      },
      android: { priority: "high" },
      tokens,
    };

    try {
      const response = await messaging.sendEachForMulticast(message);
      console.log(
        `Emergency broadcast sent: ${response.successCount}/${tokens.length} tokens`
      );
    } catch (error) {
      console.error("Error sending emergency broadcast:", error);
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

// =========================================================================
// HTTP endpoints for desktop clients (cloud_functions SDK not supported)
// These wrap the callable functions for direct HTTP access
// =========================================================================

/**
 * Helper: verify Firebase ID token from Authorization header
 */
async function verifyAuthToken(req) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return null;
  }
  const idToken = authHeader.split("Bearer ")[1];
  try {
    const decoded = await auth.verifyIdToken(idToken);
    return decoded;
  } catch (e) {
    console.log("Token verification failed:", e.message);
    return null;
  }
}

exports.httpInitSession = onRequest(
  { region: "us-central1", cors: true },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const decoded = await verifyAuthToken(req);
    if (!decoded) {
      res.status(401).json({ error: "Authentication required" });
      return;
    }

    const { personalNumber } = req.body.data || req.body;
    if (!personalNumber) {
      res.status(400).json({ error: "personalNumber is required" });
      return;
    }

    try {
      const firebaseUid = decoded.uid;
      const userDoc = await db.collection("users").doc(personalNumber).get();

      if (!userDoc.exists) {
        await auth.setCustomUserClaims(firebaseUid, {
          appUid: personalNumber,
          role: "navigator",
          isApproved: false,
          unitId: null,
          unitScope: [],
          hasFullScope: false,
        });
        await waitForClaimsPropagation(firebaseUid, personalNumber);
        res.json({ result: { success: true } });
        return;
      }

      const userData = userDoc.data();

      // Auto-repair developer role (fixes corruption from old SyncManager push)
      if (DEVELOPER_UIDS.includes(personalNumber) && userData.role !== "developer") {
        console.log(`httpInitSession: Fixing developer role for ${personalNumber} (was: ${userData.role})`);
        await db.collection("users").doc(personalNumber).update({ role: "developer" });
        userData.role = "developer";
      }

      const claims = await buildClaims(userData, personalNumber);
      await auth.setCustomUserClaims(firebaseUid, claims);
      await waitForClaimsPropagation(firebaseUid, personalNumber);
      res.json({ result: { success: true } });
    } catch (error) {
      console.error("httpInitSession error:", error);
      res.status(500).json({ error: error.message });
    }
  }
);

exports.httpSendEmailCode = onRequest(
  { region: "us-central1", cors: true },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const { email, personalNumber, purpose } = req.body.data || req.body;

    if (!email || !personalNumber) {
      res.status(400).json({ error: "email and personalNumber are required" });
      return;
    }

    try {
      if (purpose === "login") {
        const userDoc = await db.collection("users").doc(personalNumber).get();
        if (!userDoc.exists) {
          res.status(404).json({ error: "user_not_found" });
          return;
        }
        const userData = userDoc.data();
        if (userData.email && userData.email.toLowerCase() !== email.toLowerCase()) {
          res.status(400).json({ error: "email_mismatch" });
          return;
        }
      }

      const code = String(Math.floor(100000 + Math.random() * 900000));
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

      await db.collection("email_codes").doc(personalNumber).set({
        code,
        email: email.toLowerCase(),
        expiresAt,
        attempts: 0,
        createdAt: new Date(),
      });

      // שליחת מייל — nodemailer ישיר (fallback: החזרת קוד בתגובה)
      const emailSent = await sendVerificationEmail(email, code);

      console.log(`Email code for ${personalNumber}: sent=${emailSent} (purpose: ${purpose})`);
      res.json({ result: emailSent ? { success: true } : { success: true, code } });
    } catch (error) {
      console.error("httpSendEmailCode error:", error);
      res.status(500).json({ error: error.message });
    }
  }
);

exports.httpVerifyEmailCode = onRequest(
  { region: "us-central1", cors: true },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const { personalNumber, code } = req.body.data || req.body;

    if (!personalNumber || !code) {
      res.status(400).json({ error: "personalNumber and code are required" });
      return;
    }

    try {
      const docRef = db.collection("email_codes").doc(personalNumber);
      const doc = await docRef.get();

      if (!doc.exists) {
        res.status(400).json({ error: "code_expired" });
        return;
      }

      const data = doc.data();

      if (data.expiresAt.toDate() < new Date()) {
        await docRef.delete();
        res.status(400).json({ error: "code_expired" });
        return;
      }

      if (data.attempts >= 5) {
        await docRef.delete();
        res.status(400).json({ error: "max_attempts_exceeded" });
        return;
      }

      if (data.code !== code) {
        await docRef.update({ attempts: data.attempts + 1 });
        res.status(400).json({ error: "invalid_code" });
        return;
      }

      await docRef.delete();
      console.log(`Email code verified for ${personalNumber}`);
      res.json({ result: { success: true } });
    } catch (error) {
      console.error("httpVerifyEmailCode error:", error);
      res.status(500).json({ error: error.message });
    }
  }
);
