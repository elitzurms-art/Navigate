/// מצבי מסך מנווט
enum NavigatorScreenState {
  loading,
  notAssigned,
  noActiveNavigation,
  preparation,
  learning,
  systemCheck,
  waiting,
  active,
  review,
  error,
}

/// עדיפות סטטוסי ניווט — ערך גבוה יותר = עדיפות גבוהה יותר
int navigationStatusPriority(String status) {
  switch (status) {
    case 'active':
      return 7;
    case 'system_check':
      return 6;
    case 'waiting':
      return 5;
    case 'learning':
      return 4;
    case 'approval': // backward compat
    case 'review':
      return 2;
    case 'preparation':
    case 'ready':
      return 1;
    default:
      return 0;
  }
}

/// המרת סטטוס ניווט ל-NavigatorScreenState
NavigatorScreenState statusToScreenState(String status) {
  switch (status) {
    case 'preparation':
    case 'ready':
      return NavigatorScreenState.preparation;
    case 'learning':
      return NavigatorScreenState.learning;
    case 'system_check':
      return NavigatorScreenState.systemCheck;
    case 'waiting':
      return NavigatorScreenState.waiting;
    case 'active':
      return NavigatorScreenState.active;
    case 'approval': // backward compat
    case 'review':
      return NavigatorScreenState.review;
    default:
      return NavigatorScreenState.noActiveNavigation;
  }
}
