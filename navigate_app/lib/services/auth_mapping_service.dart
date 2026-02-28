/// @deprecated — הוחלף ב-Custom Claims (Cloud Functions).
/// auth_mapping collection עדיין קיים ב-Firestore כ-fallback עבור
/// מפקדים עם scope גדול (hasFullScope=true, non-admin).
/// ה-Cloud Function `onUserWrite` מעדכנת custom claims אוטומטית.
///
/// ניתן למחוק קובץ זה בגרסה עתידית לאחר אימות שה-migration הושלם.
@Deprecated('Replaced by Custom Claims — see initSession Cloud Function')
class AuthMappingService {
  static final AuthMappingService _instance = AuthMappingService._internal();
  factory AuthMappingService() => _instance;
  AuthMappingService._internal();
}
