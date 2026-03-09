import 'package:equatable/equatable.dart';

/// סוגי אירועי אבטחה לסשן ניווט
class SecurityEventType {
  static const navigationStarted = 'navigation_started';
  static const guidedAccessConfirmed = 'guided_access_confirmed';
  static const appResignedActive = 'app_resigned_active';
  static const appEnteredBackground = 'app_entered_background';
  static const appBecameActive = 'app_became_active';
  static const screenLocked = 'screen_locked';
  static const screenUnlocked = 'screen_unlocked';
  static const navigationInterrupted = 'navigation_interrupted';
  static const navigationResumed = 'navigation_resumed';
  static const navigationFinished = 'navigation_finished';
  static const foregroundIntegrityViolation = 'foreground_integrity_violation';
  static const securityTamperingDetected = 'security_tampering_detected';
}

/// אירוע אבטחה בודד בסשן ניווט
class NavigationSecurityEvent extends Equatable {
  final String eventType;
  final DateTime timestamp;
  final String? navigationState;
  final Map<String, dynamic>? additionalContext;

  const NavigationSecurityEvent({
    required this.eventType,
    required this.timestamp,
    this.navigationState,
    this.additionalContext,
  });

  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'timestamp': timestamp.toIso8601String(),
      if (navigationState != null) 'navigationState': navigationState,
      if (additionalContext != null) 'additionalContext': additionalContext,
    };
  }

  factory NavigationSecurityEvent.fromMap(Map<String, dynamic> map) {
    return NavigationSecurityEvent(
      eventType: map['eventType'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      navigationState: map['navigationState'] as String?,
      additionalContext: map['additionalContext'] as Map<String, dynamic>?,
    );
  }

  @override
  List<Object?> get props => [eventType, timestamp];
}

/// סשן אבטחה לניווט — מסמך אחד ל-Firestore per navigator per navigation
class NavigationSecuritySession extends Equatable {
  final String navigationId;
  final String navigatorId;
  final DateTime startTime;
  final DateTime? endTime;
  final bool guidedAccessConfirmed;
  final List<NavigationSecurityEvent> events;

  const NavigationSecuritySession({
    required this.navigationId,
    required this.navigatorId,
    required this.startTime,
    this.endTime,
    required this.guidedAccessConfirmed,
    this.events = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'navigationId': navigationId,
      'navigatorId': navigatorId,
      'startTime': startTime.toIso8601String(),
      if (endTime != null) 'endTime': endTime!.toIso8601String(),
      'guidedAccessConfirmed': guidedAccessConfirmed,
      'events': events.map((e) => e.toMap()).toList(),
    };
  }

  factory NavigationSecuritySession.fromMap(Map<String, dynamic> map) {
    return NavigationSecuritySession(
      navigationId: map['navigationId'] as String,
      navigatorId: map['navigatorId'] as String,
      startTime: DateTime.parse(map['startTime'] as String),
      endTime: map['endTime'] != null
          ? DateTime.parse(map['endTime'] as String)
          : null,
      guidedAccessConfirmed: map['guidedAccessConfirmed'] as bool? ?? false,
      events: (map['events'] as List<dynamic>?)
              ?.map((e) => NavigationSecurityEvent.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }

  NavigationSecuritySession copyWith({
    DateTime? endTime,
    List<NavigationSecurityEvent>? events,
  }) {
    return NavigationSecuritySession(
      navigationId: navigationId,
      navigatorId: navigatorId,
      startTime: startTime,
      endTime: endTime ?? this.endTime,
      guidedAccessConfirmed: guidedAccessConfirmed,
      events: events ?? this.events,
    );
  }

  @override
  List<Object?> get props => [navigationId, navigatorId, startTime];
}
