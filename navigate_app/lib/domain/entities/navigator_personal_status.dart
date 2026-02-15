/// סטטוס אישי של מנווט בניווט פעיל
enum NavigatorPersonalStatus {
  waiting('waiting', 'ממתין'),
  active('active', 'פעיל'),
  finished('finished', 'סיים');

  final String code;
  final String displayName;

  const NavigatorPersonalStatus(this.code, this.displayName);

  static NavigatorPersonalStatus fromCode(String code) {
    return NavigatorPersonalStatus.values.firstWhere(
      (status) => status.code == code,
      orElse: () => NavigatorPersonalStatus.waiting,
    );
  }

  /// גזירת סטטוס מרשומת track
  /// - אין רשומה / isActive=false + endedAt=null → ממתין
  /// - isActive=true + endedAt=null → פעיל
  /// - isActive=false + endedAt!=null → סיים
  static NavigatorPersonalStatus deriveFromTrack({
    required bool hasTrack,
    required bool isActive,
    required DateTime? endedAt,
  }) {
    if (!hasTrack || (!isActive && endedAt == null)) {
      return NavigatorPersonalStatus.waiting;
    }
    if (isActive && endedAt == null) {
      return NavigatorPersonalStatus.active;
    }
    return NavigatorPersonalStatus.finished;
  }
}
