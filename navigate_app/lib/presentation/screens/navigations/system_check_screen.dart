import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/boundary.dart';
import '../../../domain/entities/user.dart' as domain_user;
import '../../../data/repositories/boundary_repository.dart';
import '../../../data/repositories/navigation_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/geometry_utils.dart';
import '../../../core/utils/utm_converter.dart';
import '../../../services/navigation_data_loader.dart';
import '../../../services/gps_service.dart';
import 'dart:async';
import '../../widgets/map_with_selector.dart';
import '../../widgets/map_controls.dart';
import '../../../core/map_config.dart';
import '../../widgets/fullscreen_map_screen.dart';
import '../../../services/auto_map_download_service.dart';
import '../../../services/voice_service.dart';
import '../../widgets/voice_messages_panel.dart';

/// מסך בדיקת מערכות
class SystemCheckScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final bool isCommander;
  final domain_user.User? currentUser;

  const SystemCheckScreen({
    super.key,
    required this.navigation,
    this.isCommander = true,
    this.currentUser,
  });

  @override
  State<SystemCheckScreen> createState() => _SystemCheckScreenState();
}

class _SystemCheckScreenState extends State<SystemCheckScreen> with SingleTickerProviderStateMixin {
  final BoundaryRepository _boundaryRepo = BoundaryRepository();
  final NavigationRepository _navRepo = NavigationRepository();
  final UserRepository _userRepo = UserRepository();
  final MapController _mapController = MapController();
  final GpsService _gpsService = GpsService();
  final Battery _battery = Battery();

  late TabController _tabController;
  Boundary? _boundary;
  bool _isLoading = false;

  // הגדרות סוללה (אחוזים)
  int _batteryRedThreshold = 20;
  int _batteryOrangeThreshold = 50;

  // סטטוס מנווטים (סימולציה)
  Map<String, NavigatorStatus> _navigatorStatuses = {};
  Map<String, domain_user.User> _usersCache = {};
  // שמות מנווטים מ-Firestore (fallback כשאין ב-usersCache)
  final Map<String, String> _navigatorNames = {};

  // מנווט ממוקד במפה (עיגול כחול)
  String? _focusedNavigatorId;

  // סטטוס מערכת למנווט
  bool _hasGpsPermission = false;
  bool _hasLocationService = false;
  bool _hasBackgroundLocationPermission = false;
  int _batteryLevel = 0;
  double _gpsAccuracy = -1;
  LatLng? _currentPosition;
  bool _isCheckingSystem = false;

  // סטטוס מפות אופליין למנווט
  MapDownloadStatus _mapDownloadStatus = MapDownloadStatus.notStarted;
  double _mapDownloadProgress = 0.0;
  Timer? _mapStatusTimer;

  // הרשאות מכשיר (לטאב הרשאות)
  Map<String, PermissionStatus> _permissionStatuses = {};

  // מצב בדיקת מערכות (התחיל/לא)
  late domain.Navigation _currentNavigation;
  bool _systemCheckStarted = false;

  bool _measureMode = false;
  final List<LatLng> _measurePoints = [];

  // שכבות מפה
  bool _showGG = true;
  bool _showNavigators = true;

  double _ggOpacity = 1.0;
  double _navigatorsOpacity = 1.0;

  VoiceService? _voiceService;

  // הורדת נתונים
  NavigationDataLoader? _dataLoader;
  StreamSubscription<LoadProgress>? _progressSubscription;
  LoadProgress? _currentDataProgress;
  NavigationDataBundle? _loadedBundle;
  bool _isDataLoading = false;
  bool _dataLoadCompleted = false;
  bool _dataHasError = false;
  String? _dataFatalError;
  DateTime? _lastSyncTime;

  // הרשאות מפקד (cached — לא FutureBuilder)
  Map<String, PermissionStatus> _commanderPermissions = {};
  bool _isLoadingPermissions = true;

  // Firestore listener — סטטוס מנווטים בזמן אמת (למפקד)
  StreamSubscription<QuerySnapshot>? _systemStatusListener;

  // polling fallback — למקרה שה-listener לא עובד (Windows threading bug)
  Timer? _statusPollTimer;

  // טיימר בדיקה מחזורית (למנווט)
  Timer? _navigatorCheckTimer;

  @override
  void initState() {
    super.initState();
    _currentNavigation = widget.navigation;
    _systemCheckStarted = widget.navigation.status == 'system_check';
    _tabController = TabController(length: 6, vsync: this);
    _loadData();
    if (widget.isCommander) {
      _initializeNavigatorStatuses();
      _loadNavigatorUsers();
      _startSystemStatusListener();
      _startStatusPolling();
      _initDataLoader();
      _loadCommanderPermissions();
    } else {
      _checkNavigatorSystem();
    }
  }

  Future<void> _loadCommanderPermissions() async {
    try {
      final perms = await _getAllPermissions();
      if (mounted) {
        setState(() {
          _commanderPermissions = perms;
          _isLoadingPermissions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPermissions = false);
    }
  }

  Future<void> _checkNavigatorSystem() async {
    setState(() => _isCheckingSystem = true);

    try {
      // בקשת כל ההרשאות החסרות אוטומטית
      await _requestAllMissingPermissions();

      // בדיקת הרשאות GPS באמצעות GpsService
      _hasLocationService = await _gpsService.isGpsAvailable();
      _hasGpsPermission = await _gpsService.checkPermissions();
      _hasBackgroundLocationPermission = (await Permission.locationAlways.status).isGranted;

      // בדיקת דיוק GPS + מיקום נוכחי
      if (_hasGpsPermission && _hasLocationService) {
        _gpsAccuracy = await _gpsService.getCurrentAccuracy();
        _currentPosition = await _gpsService.getCurrentPosition();
      }

      // בדיקת סוללה אמיתית
      try {
        _batteryLevel = await _battery.batteryLevel;
      } catch (_) {
        _batteryLevel = -1; // לא זמין (אמולטור)
      }

      // בדיקת הרשאות מכשיר
      await _checkDevicePermissions();

      // בדיקת סטטוס מפות אופליין + הפעלת הורדה אם לא התחילה
      _checkMapDownloadStatus();

      setState(() => _isCheckingSystem = false);

      // דיווח סטטוס ל-Firestore כדי שהמפקד יראה
      _reportStatusToFirestore();

      // הפעלת בדיקה מחזורית כל 15 שניות
      _navigatorCheckTimer ??= Timer.periodic(
        const Duration(seconds: 15),
        (_) => _checkAndReportStatus(),
      );

      // polling סטטוס מפות כל 5 שניות (עדכון UI מהיר בזמן הורדה)
      _mapStatusTimer ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkMapDownloadStatus(),
      );
    } catch (e) {
      setState(() => _isCheckingSystem = false);
    }
  }

  /// בדיקת סטטוס הורדת מפות + הפעלה אוטומטית
  void _checkMapDownloadStatus() {
    final service = AutoMapDownloadService();
    final navId = _currentNavigation.id;

    final newStatus = service.getStatus(navId);
    final newProgress = service.getProgress(navId);

    // הפעלת הורדה אוטומטית אם לא התחילה
    if (newStatus == MapDownloadStatus.notStarted) {
      _triggerAutoMapDownload(_currentNavigation);
    }

    if (newStatus != _mapDownloadStatus || newProgress != _mapDownloadProgress) {
      if (mounted) {
        setState(() {
          _mapDownloadStatus = newStatus;
          _mapDownloadProgress = newProgress;
        });
        // עדכון Firestore עם סטטוס מפות חדש
        _reportStatusToFirestore();
      }
    }
  }

  /// הורדה ידנית מחדש
  Future<void> _startManualMapDownload() async {
    final service = AutoMapDownloadService();
    service.resetForManualDownload(_currentNavigation.id);
    service.onStatusMessage = (message, {bool isError = false}) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.blue,
          duration: Duration(seconds: isError ? 4 : 3),
        ),
      );
    };
    setState(() {
      _mapDownloadStatus = MapDownloadStatus.downloading;
      _mapDownloadProgress = 0.0;
    });
    await service.triggerDownload(_currentNavigation);
    _checkMapDownloadStatus();
  }

  /// בדיקה מחזורית ודיווח (מנווט)
  Future<void> _checkAndReportStatus() async {
    if (!mounted) return;
    try {
      _hasLocationService = await _gpsService.isGpsAvailable();
      _hasGpsPermission = await _gpsService.checkPermissions();
      _hasBackgroundLocationPermission = (await Permission.locationAlways.status).isGranted;

      if (_hasGpsPermission && _hasLocationService) {
        _gpsAccuracy = await _gpsService.getCurrentAccuracy();
        _currentPosition = await _gpsService.getCurrentPosition();
        print('DEBUG SystemCheck navigator: perm=$_hasGpsPermission svc=$_hasLocationService bgPerm=$_hasBackgroundLocationPermission pos=$_currentPosition accuracy=$_gpsAccuracy source=${_gpsService.lastPositionSource}');
      } else {
        print('DEBUG SystemCheck navigator: GPS skipped — perm=$_hasGpsPermission svc=$_hasLocationService bgPerm=$_hasBackgroundLocationPermission');
      }

      try {
        _batteryLevel = await _battery.batteryLevel;
      } catch (_) {
        _batteryLevel = -1;
      }

      if (mounted) setState(() {});
      _reportStatusToFirestore();
    } catch (e) {
      print('DEBUG SystemCheck navigator: _checkAndReportStatus error: $e');
    }
  }

  /// כתיבת סטטוס בדיקת מערכות ל-Firestore (מנווט → מפקד)
  Future<void> _reportStatusToFirestore() async {
    final uid = widget.currentUser?.uid;
    if (uid == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(widget.navigation.id)
          .collection('system_status')
          .doc(uid);

      await docRef.set({
        'navigatorId': uid,
        'isConnected': _currentPosition != null,
        'batteryLevel': _batteryLevel,
        'hasGPS': _hasGpsPermission && _hasLocationService,
        'hasBackgroundLocation': _hasBackgroundLocationPermission,
        'gpsAccuracy': _gpsAccuracy,
        'receptionLevel': _estimateReceptionLevel(),
        'latitude': _currentPosition?.latitude,
        'longitude': _currentPosition?.longitude,
        'positionSource': _gpsService.lastPositionSource.name,
        'mapsStatus': _mapDownloadStatus.name,
        'hasMicrophonePermission': _permissionStatuses['microphone']?.isGranted ?? false,
        'hasPhonePermission': _permissionStatuses['phone']?.isGranted ?? false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('DEBUG SystemCheck: failed to report status: $e');
    }
  }

  /// הערכת רמת קליטה לפי דיוק GPS
  int _estimateReceptionLevel() {
    if (!_hasGpsPermission || !_hasLocationService) return 0;
    if (_gpsAccuracy < 0) return 0;
    if (_gpsAccuracy <= 10) return 4; // מצוין
    if (_gpsAccuracy <= 30) return 3; // טוב
    if (_gpsAccuracy <= 50) return 2; // בינוני
    if (_gpsAccuracy <= 100) return 1; // חלש
    return 0;
  }

  Future<void> _checkDevicePermissions() async {
    _permissionStatuses = {
      'location': await Permission.location.status,
      'locationAlways': await Permission.locationAlways.status,
      'notification': await Permission.notification.status,
      'microphone': await Permission.microphone.status,
      'phone': await Permission.phone.status,
      'sms': await Permission.sms.status,
    };
  }

  /// בקשת כל ההרשאות החסרות באופן אוטומטי
  Future<void> _requestAllMissingPermissions() async {
    final permissions = [
      Permission.notification,
      Permission.location,
      Permission.locationAlways,
      Permission.microphone,
      Permission.phone,
      Permission.sms,
    ];

    for (final permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted && !status.isPermanentlyDenied) {
        await permission.request();
      }
    }
  }

  Future<void> _requestPermissions() async {
    await _gpsService.checkPermissions(); // זה גם מבקש הרשאות אם חסרות
    await _checkNavigatorSystem();
  }

  Future<void> _requestPermission(Permission permission) async {
    await permission.request();
    await _checkDevicePermissions();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _progressSubscription?.cancel();
    _dataLoader?.dispose();
    _gpsService.dispose();
    _systemStatusListener?.cancel();
    _statusPollTimer?.cancel();
    _navigatorCheckTimer?.cancel();
    _mapStatusTimer?.cancel();
    _voiceService?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      Boundary? boundary;
      if (widget.navigation.boundaryLayerId != null) {
        boundary = await _boundaryRepo.getById(widget.navigation.boundaryLayerId!);
      }

      setState(() {
        _boundary = boundary;
        _isLoading = false;
      });

      if (boundary != null && boundary.coordinates.isNotEmpty) {
        final points = boundary.coordinates.map((c) => LatLng(c.lat, c.lng)).toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.fitCamera(CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(30),
            ));
          } catch (_) {}
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _initializeNavigatorStatuses() {
    // אתחול סטטוסים לכל המשתתפים
    final allNavigatorIds = <String>{
      ...widget.navigation.routes.keys,
      ...widget.navigation.selectedParticipantIds,
    };

    for (final navigatorId in allNavigatorIds) {
      _navigatorStatuses[navigatorId] = NavigatorStatus(
        isConnected: false,
        batteryLevel: 0,
        hasGPS: false,
        receptionLevel: 0,
        latitude: null,
        longitude: null,
      );
    }
  }

  Future<void> _loadNavigatorUsers() async {
    final allNavigatorIds = <String>{
      ...widget.navigation.routes.keys,
      ...widget.navigation.selectedParticipantIds,
    };

    for (final uid in allNavigatorIds) {
      try {
        final user = await _userRepo.getUser(uid);
        if (user != null) {
          _usersCache[uid] = user;
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  /// האזנה בזמן אמת לסטטוס מנווטים מ-Firestore (למפקד)
  void _startSystemStatusListener() {
    _systemStatusListener = FirebaseFirestore.instance
        .collection(AppConstants.navigationsCollection)
        .doc(widget.navigation.id)
        .collection('system_status')
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final navigatorId = data['navigatorId'] as String? ?? doc.id;
            final navigatorName = data['navigatorName'] as String?;
            if (navigatorName != null && navigatorName.isNotEmpty) {
              _navigatorNames[navigatorId] = navigatorName;
            }

            final posUpdatedAt = data['positionUpdatedAt'];
            DateTime? posTime;
            if (posUpdatedAt is Timestamp) {
              posTime = posUpdatedAt.toDate();
            } else if (posUpdatedAt is String) {
              posTime = DateTime.tryParse(posUpdatedAt);
            }

            _navigatorStatuses[navigatorId] = NavigatorStatus(
              isConnected: data['isConnected'] as bool? ?? false,
              hasReported: true,
              batteryLevel: data['batteryLevel'] as int? ?? 0,
              hasGPS: data['hasGPS'] as bool? ?? false,
              receptionLevel: data['receptionLevel'] as int? ?? 0,
              latitude: (data['latitude'] as num?)?.toDouble(),
              longitude: (data['longitude'] as num?)?.toDouble(),
              positionSource: data['positionSource'] as String? ?? 'gps',
              positionUpdatedAt: posTime,
              gpsAccuracy: (data['gpsAccuracy'] as num?)?.toDouble() ?? -1,
              mapsStatus: data['mapsStatus'] as String? ?? 'notStarted',
              hasMicrophonePermission: data['hasMicrophonePermission'] as bool? ?? false,
              hasPhonePermission: data['hasPhonePermission'] as bool? ?? false,
            );
          }
        });
      },
      onError: (e) {
        print('DEBUG SystemCheck: system_status listener error: $e');
      },
    );
  }

  /// polling fallback — שאילתת Firestore ישירה כל 10 שניות
  /// (עוקף את בעיית ה-threading של snapshots ב-Windows)
  void _startStatusPolling() {
    // שאילתה ראשונית מיידית
    _pollNavigatorStatuses();
    _statusPollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _pollNavigatorStatuses(),
    );
  }

  Future<void> _pollNavigatorStatuses() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(widget.navigation.id)
          .collection('system_status')
          .get();

      if (!mounted) return;
      print('DEBUG SystemCheck poll: ${snapshot.docs.length} docs');
      setState(() {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final navigatorId = data['navigatorId'] as String? ?? doc.id;
          final navigatorName = data['navigatorName'] as String?;
          if (navigatorName != null && navigatorName.isNotEmpty) {
            _navigatorNames[navigatorId] = navigatorName;
          }
          print('DEBUG SystemCheck poll: navigator=$navigatorId connected=${data['isConnected']} hasGPS=${data['hasGPS']} lat=${data['latitude']} lng=${data['longitude']} source=${data['positionSource']} posUpdatedAt=${data['positionUpdatedAt']}');

          final posUpdatedAt = data['positionUpdatedAt'];
          DateTime? posTime;
          if (posUpdatedAt is Timestamp) {
            posTime = posUpdatedAt.toDate();
          } else if (posUpdatedAt is String) {
            posTime = DateTime.tryParse(posUpdatedAt);
          }

          _navigatorStatuses[navigatorId] = NavigatorStatus(
            isConnected: data['isConnected'] as bool? ?? false,
            hasReported: true,
            batteryLevel: data['batteryLevel'] as int? ?? 0,
            hasGPS: data['hasGPS'] as bool? ?? false,
            receptionLevel: data['receptionLevel'] as int? ?? 0,
            latitude: (data['latitude'] as num?)?.toDouble(),
            longitude: (data['longitude'] as num?)?.toDouble(),
            positionSource: data['positionSource'] as String? ?? 'gps',
            positionUpdatedAt: posTime,
            gpsAccuracy: (data['gpsAccuracy'] as num?)?.toDouble() ?? -1,
            hasMicrophonePermission: data['hasMicrophonePermission'] as bool? ?? false,
            hasPhonePermission: data['hasPhonePermission'] as bool? ?? false,
          );
        }
      });
    } catch (e) {
      print('DEBUG SystemCheck: poll error: $e');
    }
  }

  void _initDataLoader() {
    _dataLoader = NavigationDataLoader();
    _checkDataCache();
  }

  Future<void> _checkDataCache() async {
    if (_dataLoader == null) return;
    try {
      final isCached = await _dataLoader!.isDataCachedLocally(widget.navigation.id);
      final lastSync = await _dataLoader!.getLastSyncTimestamp(widget.navigation.id);
      if (mounted) {
        setState(() {
          _lastSyncTime = lastSync;
          if (isCached && lastSync != null) {
            _dataLoadCompleted = true;
          }
        });
        if (!isCached || lastSync == null) {
          _startDataLoading(forceRefresh: false);
        }
      }
    } catch (_) {}
  }

  Future<void> _startDataLoading({bool forceRefresh = false}) async {
    if (_isDataLoading || _dataLoader == null) return;
    setState(() {
      _isDataLoading = true;
      _dataHasError = false;
      _dataFatalError = null;
      _dataLoadCompleted = false;
      _currentDataProgress = null;
    });

    _progressSubscription?.cancel();
    _progressSubscription = _dataLoader!.progressStream.listen(
      (progress) {
        if (mounted) setState(() => _currentDataProgress = progress);
      },
      onError: (error) {
        if (mounted) setState(() {
          _dataHasError = true;
          _dataFatalError = error.toString();
        });
      },
    );

    try {
      NavigationDataBundle? bundle;
      if (widget.isCommander) {
        bundle = await _dataLoader!.loadCommanderData(
          navigationId: widget.navigation.id,
          forceRefresh: forceRefresh,
        );
      } else if (widget.currentUser != null) {
        bundle = await _dataLoader!.loadNavigatorData(
          navigationId: widget.navigation.id,
          navigatorUid: widget.currentUser!.uid,
          forceRefresh: forceRefresh,
        );
      }

      if (mounted) {
        final lastSync = await _dataLoader!.getLastSyncTimestamp(widget.navigation.id);
        setState(() {
          _loadedBundle = bundle;
          _isDataLoading = false;
          _dataLoadCompleted = bundle != null;
          _dataHasError = bundle == null;
          _lastSyncTime = lastSync;
          if (bundle == null) _dataFatalError = 'לא ניתן לטעון את נתוני הניווט';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDataLoading = false;
          _dataHasError = true;
          _dataFatalError = 'שגיאה בטעינת נתונים: $e';
        });
      }
    }
  }

  String _getNavigatorDisplayName(String navigatorId) {
    final user = _usersCache[navigatorId];
    if (user != null && user.fullName.isNotEmpty) {
      return user.fullName;
    }
    // fallback — שם מ-Firestore system_status
    final firestoreName = _navigatorNames[navigatorId];
    if (firestoreName != null && firestoreName.isNotEmpty) {
      return firestoreName;
    }
    return navigatorId;
  }

  @override
  Widget build(BuildContext context) {
    // תצוגה למנווט
    if (!widget.isCommander) {
      return _buildNavigatorView();
    }

    // תצוגה למפקד
    return PopScope(
      canPop: true,
      onPopInvoked: (bool didPop) {
        // בדיקת המערכות תמשיך לרוץ ברקע — רק כפתור "סיום בדיקת מערכות" משנה סטטוס
      },
      child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'בדיקת מערכות',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'מנווטים'),
            Tab(icon: Icon(Icons.battery_charging_full), text: 'אנרגיה'),
            Tab(icon: Icon(Icons.signal_cellular_alt), text: 'צפיה'),
            Tab(icon: Icon(Icons.settings), text: 'מערכת'),
            Tab(icon: Icon(Icons.cloud_download), text: 'נתונים'),
            Tab(icon: Icon(Icons.security), text: 'הרשאות'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildNavigatorsTab(),
                      _buildBatteryView(),
                      _buildConnectivityView(),
                      _buildSystemTab(),
                      _buildDataTab(),
                      _buildPermissionsTab(),
                    ],
                  ),
                ),
                if (widget.navigation.communicationSettings.walkieTalkieEnabled && widget.currentUser != null)
                  Builder(builder: (context) {
                    _voiceService ??= VoiceService();
                    return VoiceMessagesPanel(
                      navigationId: widget.navigation.id,
                      currentUser: widget.currentUser!,
                      voiceService: _voiceService!,
                      isCommander: widget.isCommander,
                      enabled: true,
                    );
                  }),
              ],
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // כפתור הפעלת בדיקת מערכות
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _systemCheckStarted ? null : _startSystemCheck,
                icon: Icon(_systemCheckStarted ? Icons.check : Icons.play_arrow),
                label: Text(
                  _systemCheckStarted ? 'בדיקת מערכות פעילה' : 'הפעלת בדיקת מערכות',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _systemCheckStarted ? Colors.grey : Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // כפתור סיום בדיקת מערכות
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _systemCheckStarted ? _finishSystemCheck : null,
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  'סיום בדיקת מערכות',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _startSystemCheck() async {
    // בקשת כל ההרשאות החסרות במכשיר המפקד
    await _requestAllMissingPermissions();
    await _checkDevicePermissions();

    final updatedNav = _currentNavigation.copyWith(
      status: 'system_check',
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNav);
    _currentNavigation = updatedNav;
    _triggerAutoMapDownload(updatedNav);
    if (mounted) {
      setState(() => _systemCheckStarted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('בדיקת מערכות הופעלה — המנווטים יראו את המסך שלהם'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  /// הפעלת הורדת מפות אוטומטית עם SnackBar למשתמש
  void _triggerAutoMapDownload(domain.Navigation navigation) {
    final service = AutoMapDownloadService();
    service.onStatusMessage = (message, {bool isError = false}) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.blue,
          duration: Duration(seconds: isError ? 4 : 3),
        ),
      );
    };
    service.triggerDownload(navigation);
  }

  Future<void> _finishSystemCheck() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('סיום בדיקת מערכות'),
        content: const Text('האם לסיים את בדיקת המערכות?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('סיום'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Clean up system_status documents from Firestore
    try {
      final statusCollection = FirebaseFirestore.instance
          .collection(AppConstants.navigationsCollection)
          .doc(_currentNavigation.id)
          .collection('system_status');
      final snapshot = await statusCollection.get();
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      print('DEBUG SystemCheck: failed to clean up system_status: $e');
    }

    final updatedNavigation = _currentNavigation.copyWith(
      status: 'preparation',
      systemCheckStartTime: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _navRepo.update(updatedNavigation);
    _currentNavigation = updatedNavigation;

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildNavigatorsTab() {
    final navigatorIds = _navigatorStatuses.keys.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // סיכום כללי
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.people, size: 40, color: Colors.blue),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${navigatorIds.length} מנווטים',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_navigatorStatuses.values.where((s) => s.hasReported).length} מדווחים',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // מקרא
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildStatusIndicator(Icons.gps_fixed, Colors.green, 'GPS תקין'),
              _buildStatusIndicator(Icons.gps_off, Colors.red, 'אין GPS'),
              _buildStatusIndicator(Icons.battery_full, Colors.green, 'סוללה תקינה'),
              _buildStatusIndicator(Icons.battery_alert, Colors.red, 'סוללה נמוכה'),
              _buildStatusIndicator(Icons.signal_cellular_4_bar, Colors.green, 'קליטה טובה'),
              _buildStatusIndicator(Icons.signal_cellular_0_bar, Colors.red, 'אין קליטה'),
              _buildStatusIndicator(Icons.map, Colors.green, 'מפות ירדו'),
              _buildStatusIndicator(Icons.cloud_off, Colors.orange, 'מפות חסרות'),
            ],
          ),
          const SizedBox(height: 16),

          // רשימת מנווטים
          ...navigatorIds.map((navigatorId) {
            final status = _navigatorStatuses[navigatorId]!;
            return _buildNavigatorCard(navigatorId, status);
          }),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildNavigatorCard(String navigatorId, NavigatorStatus status) {
    final displayName = _getNavigatorDisplayName(navigatorId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showNavigatorDetails(navigatorId, status),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // אווטאר
              CircleAvatar(
                backgroundColor: status.hasReported
                    ? (status.isConnected ? Colors.green[100] : Colors.orange[100])
                    : Colors.grey[200],
                child: Icon(
                  Icons.person,
                  color: status.hasReported
                      ? (status.isConnected ? Colors.green : Colors.orange)
                      : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),

              // שם ומספר
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (displayName != navigatorId)
                      Text(
                        navigatorId,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    Text(
                      !status.hasReported
                          ? 'לא דיווח'
                          : status.isConnected
                              ? 'מחובר'
                              : 'מדווח · ללא מיקום',
                      style: TextStyle(
                        fontSize: 12,
                        color: !status.hasReported
                            ? Colors.grey
                            : status.isConnected
                                ? Colors.green
                                : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),

              // חיווי GPS
              _buildMiniIndicator(
                icon: status.hasGPS ? Icons.gps_fixed : Icons.gps_off,
                color: !status.hasReported
                    ? Colors.grey
                    : !status.hasGPS
                        ? Colors.red
                        : status.positionSource == 'cellTower'
                            ? Colors.orange
                            : Colors.green,
              ),
              const SizedBox(width: 8),

              // חיווי סוללה
              _buildMiniIndicator(
                icon: _getBatteryIcon(status),
                color: _getBatteryColor(status),
                label: status.hasReported ? '${status.batteryLevel}%' : null,
              ),
              const SizedBox(width: 8),

              // חיווי קליטה
              _buildMiniIndicator(
                icon: _getReceptionIcon(status),
                color: _getReceptionColor(status),
              ),
              const SizedBox(width: 8),

              // חיווי מבחן בדד (רק אם requireSoloQuiz)
              if (_currentNavigation.learningSettings.requireSoloQuiz) ...[
                _buildMiniIndicator(
                  icon: Icons.quiz,
                  color: _getQuizStatusColor(navigatorId),
                ),
                const SizedBox(width: 8),
              ],

              // חיווי מפות אופליין
              _buildMiniIndicator(
                icon: _getMapsIcon(status),
                color: _getMapsColor(status),
              ),

              const SizedBox(width: 4),
              Icon(Icons.chevron_left, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniIndicator({
    required IconData icon,
    required Color color,
    String? label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        if (label != null)
          Text(
            label,
            style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }

  Color _getQuizStatusColor(String navigatorId) {
    final user = _usersCache[navigatorId];
    if (user == null) return Colors.grey;
    if (user.hasSoloQuizValid) return Colors.green;
    if (user.soloQuizPassedAt != null) return Colors.red; // עבר אבל פג תוקף
    return Colors.red; // לא ביצע
  }

  String _getQuizStatusText(String navigatorId) {
    final user = _usersCache[navigatorId];
    if (user == null) return 'לא זמין';
    if (user.hasSoloQuizValid) return 'עבר בהצלחה';
    if (user.soloQuizPassedAt != null) return 'נכשל';
    return 'לא ביצע';
  }

  IconData _getBatteryIcon(NavigatorStatus status) {
    if (!status.hasReported) return Icons.battery_unknown;
    if (status.batteryLevel < _batteryRedThreshold) return Icons.battery_alert;
    if (status.batteryLevel < _batteryOrangeThreshold) return Icons.battery_2_bar;
    return Icons.battery_full;
  }

  Color _getBatteryColor(NavigatorStatus status) {
    if (!status.hasReported) return Colors.grey;
    if (status.batteryLevel < _batteryRedThreshold) return Colors.red;
    if (status.batteryLevel < _batteryOrangeThreshold) return Colors.orange;
    return Colors.green;
  }

  IconData _getReceptionIcon(NavigatorStatus status) {
    if (!status.hasReported) return Icons.signal_cellular_off;
    if (status.receptionLevel <= 0) return Icons.signal_cellular_0_bar;
    if (status.receptionLevel <= 1) return Icons.signal_cellular_alt_1_bar;
    if (status.receptionLevel <= 2) return Icons.signal_cellular_alt_2_bar;
    if (status.receptionLevel <= 3) return Icons.signal_cellular_alt;
    return Icons.signal_cellular_4_bar;
  }

  Color _getReceptionColor(NavigatorStatus status) {
    if (!status.hasReported) return Colors.grey;
    if (status.receptionLevel <= 1) return Colors.red;
    if (status.receptionLevel <= 2) return Colors.orange;
    return Colors.green;
  }

  IconData _getMapsIcon(NavigatorStatus status) {
    switch (status.mapsStatus) {
      case 'completed':
        return Icons.map;
      case 'downloading':
        return Icons.cloud_download;
      case 'failed':
        return Icons.cloud_off;
      default:
        return Icons.cloud_off;
    }
  }

  Color _getMapsColor(NavigatorStatus status) {
    if (!status.hasReported) return Colors.grey;
    switch (status.mapsStatus) {
      case 'completed':
        return Colors.green;
      case 'downloading':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  void _showNavigatorDetails(String navigatorId, NavigatorStatus status) {
    final displayName = _getNavigatorDisplayName(navigatorId);
    final hasRoute = widget.navigation.routes.containsKey(navigatorId);
    final route = widget.navigation.routes[navigatorId];

    Timer? refreshTimer;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            // הפעלת טיימר רענון כל 3 שניות (פעם אחת)
            refreshTimer ??= Timer.periodic(
              const Duration(seconds: 3),
              (_) {
                if (builderContext.mounted) {
                  setDialogState(() {});
                }
              },
            );

            // קריאת הסטטוס העדכני מה-map החי
            final s = _navigatorStatuses[navigatorId] ?? status;
            final user = _usersCache[navigatorId];

            return AlertDialog(
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: s.hasReported
                        ? (s.isConnected ? Colors.green[100] : Colors.orange[100])
                        : Colors.grey[200],
                    child: Icon(
                      Icons.person,
                      color: s.hasReported
                          ? (s.isConnected ? Colors.green : Colors.orange)
                          : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, style: const TextStyle(fontSize: 18)),
                        Text(
                          navigatorId,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // סטטוס חיבור
                    _buildDetailRow(
                      'חיבור',
                      !s.hasReported
                          ? 'לא דיווח'
                          : s.isConnected
                              ? 'מחובר'
                              : 'מדווח · ללא מיקום',
                      Icons.wifi,
                      !s.hasReported
                          ? Colors.grey
                          : s.isConnected
                              ? Colors.green
                              : Colors.orange,
                    ),
                    const Divider(),

                    // GPS
                    _buildDetailRow(
                      'GPS',
                      !s.hasReported
                          ? 'לא ידוע'
                          : !s.hasGPS
                              ? 'לא פעיל'
                              : s.positionSource == 'cellTower'
                                  ? 'מערכת חליפית תקינה'
                                  : 'פעיל ותקין',
                      s.hasGPS ? Icons.gps_fixed : Icons.gps_off,
                      !s.hasReported
                          ? Colors.grey
                          : !s.hasGPS
                              ? Colors.red
                              : s.positionSource == 'cellTower'
                                  ? Colors.orange
                                  : Colors.green,
                    ),
                    if (s.hasReported && s.hasGPS && s.latitude != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 40),
                        child: Text(
                          'מיקום: ${UtmConverter.latLngToUtm(LatLng(s.latitude!, s.longitude!))}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            setState(() => _focusedNavigatorId = navigatorId);
                            _tabController.animateTo(2); // טאב צפיה/מפה
                            // התמקדות על המנווט במפה
                            Future.delayed(const Duration(milliseconds: 300), () {
                              _mapController.move(
                                LatLng(s.latitude!, s.longitude!),
                                16,
                              );
                            });
                          },
                          icon: const Icon(Icons.my_location, size: 16),
                          label: const Text('התמקד במפה'),
                        ),
                      ),
                    ],
                    // דיוק GPS
                    if (s.gpsAccuracy > 0)
                      _buildDetailRow(
                        'דיוק',
                        '${s.gpsAccuracy.toStringAsFixed(0)} מטר',
                        Icons.my_location,
                        s.gpsAccuracy <= 10
                            ? Colors.green
                            : s.gpsAccuracy <= 50
                                ? Colors.orange
                                : Colors.red,
                      ),
                    // מקור מיקום
                    if (s.hasReported && s.hasGPS)
                      _buildDetailRow(
                        'מקור מיקום',
                        _positionSourceLabel(s.positionSource),
                        _positionSourceIcon(s.positionSource),
                        _positionSourceColor(s.positionSource),
                      ),
                    const Divider(),

                    // סוללה
                    _buildDetailRow(
                      'סוללה',
                      s.hasReported ? '${s.batteryLevel}%' : 'לא ידוע',
                      _getBatteryIcon(s),
                      _getBatteryColor(s),
                    ),
                    const Divider(),

                    // קליטה
                    _buildDetailRow(
                      'קליטה',
                      s.hasReported
                          ? _getReceptionText(s.receptionLevel)
                          : 'לא ידוע',
                      _getReceptionIcon(s),
                      _getReceptionColor(s),
                    ),
                    const Divider(),

                    // הרשאות מיקרופון וטלפון
                    _buildDetailRow(
                      'מיקרופון',
                      s.hasMicrophonePermission ? 'מאושר' : 'לא מאושר',
                      Icons.mic,
                      s.hasMicrophonePermission ? Colors.green : Colors.red,
                    ),
                    _buildDetailRow(
                      'טלפון',
                      s.hasPhonePermission ? 'מאושר' : 'לא מאושר',
                      Icons.phone_android,
                      s.hasPhonePermission ? Colors.green : Colors.red,
                    ),
                    const Divider(),

                    // פרטי משתמש
                    if (user != null) ...[
                      _buildDetailRow(
                        'טלפון',
                        user.phoneNumber.isNotEmpty ? user.phoneNumber : 'לא זמין',
                        Icons.phone,
                        Colors.blue,
                      ),
                      const Divider(),
                    ],

                    // מבחן בדד (רק אם מופעל)
                    if (_currentNavigation.learningSettings.requireSoloQuiz) ...[
                      _buildDetailRow(
                        'מבחן בדד',
                        _getQuizStatusText(navigatorId),
                        Icons.quiz,
                        _getQuizStatusColor(navigatorId),
                      ),
                      const Divider(),
                    ],

                    // ציר מוקצה
                    _buildDetailRow(
                      'ציר',
                      hasRoute
                          ? '${route!.sequence.length} נקודות (${route.routeLengthKm.toStringAsFixed(2)} ק"מ)'
                          : 'לא הוקצה ציר',
                      Icons.route,
                      hasRoute ? Colors.blue : Colors.grey,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('סגור'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => refreshTimer?.cancel());
  }

  String _positionSourceLabel(String source) {
    switch (source) {
      case 'gps': return 'GPS';
      case 'cellTower': return 'אנטנות';
      case 'pdr': return 'PDR';
      case 'pdrCellHybrid': return 'PDR+Cell';
      default: return source;
    }
  }

  IconData _positionSourceIcon(String source) {
    switch (source) {
      case 'gps': return Icons.gps_fixed;
      case 'cellTower': return Icons.cell_tower;
      case 'pdr': return Icons.directions_walk;
      case 'pdrCellHybrid': return Icons.merge_type;
      default: return Icons.location_on;
    }
  }

  Color _positionSourceColor(String source) {
    switch (source) {
      case 'gps': return Colors.green;
      case 'cellTower': return Colors.orange;
      case 'pdr': return Colors.blue;
      case 'pdrCellHybrid': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(value, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  String _getReceptionText(int level) {
    if (level <= 0) return 'אין קליטה';
    if (level <= 1) return 'חלשה';
    if (level <= 2) return 'בינונית';
    if (level <= 3) return 'טובה';
    return 'מצוינת';
  }

  Widget _buildBatteryView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // הגדרות סף
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'הגדרות סוללה',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('🔴 אדום: מתחת ל-'),
                      Expanded(
                        child: Slider(
                          value: _batteryRedThreshold.toDouble(),
                          min: 0,
                          max: 50,
                          divisions: 10,
                          label: '$_batteryRedThreshold%',
                          activeColor: Colors.red,
                          onChanged: (value) {
                            setState(() => _batteryRedThreshold = value.toInt());
                          },
                        ),
                      ),
                      Text('$_batteryRedThreshold%'),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('🟠 כתום: מתחת ל-'),
                      Expanded(
                        child: Slider(
                          value: _batteryOrangeThreshold.toDouble(),
                          min: 20,
                          max: 80,
                          divisions: 12,
                          label: '$_batteryOrangeThreshold%',
                          activeColor: Colors.orange,
                          onChanged: (value) {
                            setState(() => _batteryOrangeThreshold = value.toInt());
                          },
                        ),
                      ),
                      Text('$_batteryOrangeThreshold%'),
                    ],
                  ),
                  const Row(
                    children: [
                      Text('🟢 ירוק: מעל כתום'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // רשימת מנווטים
          const Text(
            'מצב סוללה',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ..._navigatorStatuses.entries.map((entry) {
            return _buildBatteryCard(entry.key, entry.value);
          }),
        ],
      ),
    );
  }

  Widget _buildBatteryCard(String navigatorId, NavigatorStatus status) {
    Color statusColor;
    String statusText;
    IconData icon;

    if (!status.hasReported) {
      statusColor = Colors.grey;
      statusText = 'לא דיווח';
      icon = Icons.power_off;
    } else if (status.batteryLevel < _batteryRedThreshold) {
      statusColor = Colors.red;
      statusText = 'קריטי';
      icon = Icons.battery_alert;
    } else if (status.batteryLevel < _batteryOrangeThreshold) {
      statusColor = Colors.orange;
      statusText = 'נמוך';
      icon = Icons.battery_2_bar;
    } else {
      statusColor = Colors.green;
      statusText = 'טוב';
      icon = Icons.battery_full;
    }

    final displayName = _getNavigatorDisplayName(navigatorId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: statusColor, size: 32),
        title: Text(displayName),
        subtitle: Text(statusText),
        trailing: status.hasReported
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${status.batteryLevel}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              )
            : const Icon(Icons.help_outline, color: Colors.grey),
      ),
    );
  }

  Widget _buildConnectivityView() {
    return Column(
      children: [
        // מקרא
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey[100],
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem('פעיל / עד 2 דק׳', Colors.green),
                _buildLegendItem('GPS חליפי', Colors.yellow[700]!),
                _buildLegendItem('2-10 דק׳ מאות אחרון', Colors.orange),
                _buildLegendItem('מעל 10 דק׳', Colors.grey),
              ],
            ),
          ),
        ),

        // מפה
        Expanded(
          child: Stack(
            children: [
              MapWithTypeSelector(
                showTypeSelector: false,
                mapController: _mapController,
                initialMapType: MapConfig.resolveMapType(widget.navigation.displaySettings.defaultMap),
                options: MapOptions(
                  initialCenter: widget.navigation.displaySettings.openingLat != null
                      ? LatLng(
                          widget.navigation.displaySettings.openingLat!,
                          widget.navigation.displaySettings.openingLng!,
                        )
                      : const LatLng(32.0853, 34.7818),
                  initialZoom: 13.0,
                  onTap: (tapPosition, point) {
                    if (_measureMode) {
                      setState(() => _measurePoints.add(point));
                      return;
                    }
                  },
                ),
                layers: [
                  // פוליגון ג"ג
                  if (_showGG && _boundary != null && _boundary!.coordinates.isNotEmpty)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _boundary!.coordinates
                              .map((coord) => LatLng(coord.lat, coord.lng))
                              .toList(),
                          color: Colors.black.withValues(alpha: 0.1 * _ggOpacity),
                          borderColor: Colors.black.withValues(alpha: _ggOpacity),
                          borderStrokeWidth: _boundary!.strokeWidth,
                          isFilled: true,
                        ),
                      ],
                    ),

                  // סמנים של מנווטים
                  if (_showNavigators)
                  MarkerLayer(
                    markers: _navigatorStatuses.entries.map((entry) {
                      final navigatorId = entry.key;
                      final status = entry.value;

                      // אין מיקום בכלל — לא מציג סמן
                      if (status.latitude == null) {
                        return Marker(
                          point: const LatLng(0, 0),
                          width: 0,
                          height: 0,
                          child: Container(),
                        );
                      }

                      // חישוב צבע לפי מקרא: ירוק=פעיל/עד 2 דק׳, צהוב=GPS חליפי, כתום=2-10 דק׳, אפור=מעל 10 דק׳
                      Color color;
                      double opacity = _navigatorsOpacity;

                      final posTime = status.positionUpdatedAt;
                      final elapsed = posTime != null
                          ? DateTime.now().difference(posTime)
                          : null;

                      if (elapsed == null) {
                        // אין מידע על זמן — אפור
                        color = Colors.grey;
                        opacity = _navigatorsOpacity * 0.6;
                      } else if (elapsed.inMinutes >= 10) {
                        // מעל 10 דקות מאות אחרון — אפור
                        color = Colors.grey;
                        opacity = _navigatorsOpacity * 0.6;
                      } else if (elapsed.inMinutes >= 2) {
                        // 2-10 דקות מאות אחרון — כתום
                        color = Colors.orange;
                      } else if (status.positionSource == 'cellTower') {
                        // פעיל אבל GPS חליפי (אנטנות) — צהוב
                        color = Colors.yellow[700]!;
                      } else {
                        // פעיל / עד 2 דקות מאות אחרון — ירוק
                        color = Colors.green;
                      }

                      return Marker(
                        point: LatLng(status.latitude!, status.longitude!),
                        width: 60,
                        height: 60,
                        child: Opacity(
                          opacity: opacity,
                          child: Column(
                            children: [
                              Icon(
                                Icons.person_pin_circle,
                                color: color,
                                size: 40,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: color, width: 2),
                                ),
                                child: Text(
                                  _getNavigatorDisplayName(navigatorId),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // עיגול כחול סביב מנווט ממוקד
                  if (_focusedNavigatorId != null) ...[
                    () {
                      final fs = _navigatorStatuses[_focusedNavigatorId];
                      if (fs == null || fs.latitude == null) return const MarkerLayer(markers: []);
                      return CircleLayer(
                        circles: [
                          CircleMarker(
                            point: LatLng(fs.latitude!, fs.longitude!),
                            radius: 30,
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderColor: Colors.blue,
                            borderStrokeWidth: 3,
                          ),
                        ],
                      );
                    }(),
                  ],

                  // שכבות מדידה
                  ...MapControls.buildMeasureLayers(_measurePoints),
                ],
              ),
              MapControls(
                mapController: _mapController,
                measureMode: _measureMode,
                onMeasureModeChanged: (v) => setState(() {
                  _measureMode = v;
                  if (!v) _measurePoints.clear();
                }),
                measurePoints: _measurePoints,
                onMeasureClear: () => setState(() => _measurePoints.clear()),
                onMeasureUndo: () => setState(() {
                  if (_measurePoints.isNotEmpty) _measurePoints.removeLast();
                }),
                onFullscreen: () {
                  final camera = _mapController.camera;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FullscreenMapScreen(
                      title: 'בדיקת מערכת',
                      initialCenter: camera.center,
                      initialZoom: camera.zoom,
                      layerConfigs: [
                        MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, opacity: _ggOpacity, onVisibilityChanged: (_) {}, onOpacityChanged: (_) {}),
                        MapLayerConfig(id: 'navigators', label: 'מנווטים', color: Colors.blue, visible: _showNavigators, opacity: _navigatorsOpacity, onVisibilityChanged: (_) {}, onOpacityChanged: (_) {}),
                      ],
                      layerBuilder: (visibility, opacity) => [
                        if (visibility['gg'] == true && _boundary != null && _boundary!.coordinates.isNotEmpty)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: _boundary!.coordinates
                                    .map((coord) => LatLng(coord.lat, coord.lng))
                                    .toList(),
                                color: Colors.black.withValues(alpha: 0.1 * (opacity['gg'] ?? 1.0)),
                                borderColor: Colors.black.withValues(alpha: (opacity['gg'] ?? 1.0)),
                                borderStrokeWidth: _boundary!.strokeWidth,
                                isFilled: true,
                              ),
                            ],
                          ),
                        if (visibility['navigators'] == true)
                          MarkerLayer(
                            markers: _navigatorStatuses.entries
                                .where((e) => e.value.latitude != null)
                                .map((entry) {
                              final status = entry.value;
                              return Marker(
                                point: LatLng(status.latitude!, status.longitude!),
                                width: 60,
                                height: 60,
                                child: Opacity(
                                  opacity: (opacity['navigators'] ?? 1.0),
                                  child: Icon(
                                    Icons.person_pin_circle,
                                    color: Colors.green,
                                    size: 40,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ));
                },
                layers: [
                  MapLayerConfig(id: 'gg', label: 'גבול גזרה', color: Colors.black, visible: _showGG, onVisibilityChanged: (v) => setState(() => _showGG = v), opacity: _ggOpacity, onOpacityChanged: (v) => setState(() => _ggOpacity = v)),
                  MapLayerConfig(id: 'navigators', label: 'מנווטים', color: Colors.blue, visible: _showNavigators, onVisibilityChanged: (v) => setState(() => _showNavigators = v), opacity: _navigatorsOpacity, onOpacityChanged: (v) => setState(() => _navigatorsOpacity = v)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getConnectivityColor(NavigatorStatus status) {
    if (!status.hasReported || !status.isConnected) return Colors.grey;
    if (!status.hasGPS) return Colors.black;

    // TODO: בדיקה אם בתוך ג"ג
    // TODO: בדיקה אם קרוב למפקד
    // בינתיים: ירוק
    return Colors.green;
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 12),
      ],
    );
  }

  /// לשונית מערכת — סיכום מצב כללי למפקד
  Widget _buildSystemTab() {
    final totalNavigators = _navigatorStatuses.length;
    final connected = _navigatorStatuses.values.where((s) => s.hasReported).length;
    final withGps = _navigatorStatuses.values.where((s) => s.hasReported && s.hasGPS).length;
    final lowBattery = _navigatorStatuses.values
        .where((s) => s.hasReported && s.batteryLevel < _batteryRedThreshold)
        .length;
    final noReception = _navigatorStatuses.values
        .where((s) => s.hasReported && s.receptionLevel <= 0)
        .length;

    final mapsReady = _navigatorStatuses.values
        .where((s) => s.hasReported && s.mapsReady)
        .length;
    final mapsNotReady = _navigatorStatuses.values
        .where((s) => s.hasReported && !s.mapsReady)
        .length;

    final allOk = connected == totalNavigators &&
        withGps == connected &&
        lowBattery == 0 &&
        noReception == 0 &&
        mapsNotReady == 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // סטטוס כללי
          Card(
            color: totalNavigators == 0
                ? Colors.grey[50]
                : allOk
                    ? Colors.green[50]
                    : Colors.orange[50],
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    totalNavigators == 0
                        ? Icons.hourglass_empty
                        : allOk
                            ? Icons.check_circle
                            : Icons.warning,
                    size: 64,
                    color: totalNavigators == 0
                        ? Colors.grey
                        : allOk
                            ? Colors.green
                            : Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    totalNavigators == 0
                        ? 'ממתין לחיבור מנווטים'
                        : allOk
                            ? 'כל המערכות תקינות'
                            : 'יש בעיות שדורשות טיפול',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: totalNavigators == 0
                          ? Colors.grey
                          : allOk
                              ? Colors.green[800]
                              : Colors.orange[800],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // סיכום מספרים
          _buildSummaryRow(
            icon: Icons.people,
            label: 'מנווטים מחוברים',
            value: '$connected / $totalNavigators',
            color: connected == totalNavigators ? Colors.green : Colors.orange,
          ),
          _buildSummaryRow(
            icon: Icons.gps_fixed,
            label: 'GPS פעיל',
            value: '$withGps / $connected',
            color: withGps == connected ? Colors.green : Colors.red,
          ),
          _buildSummaryRow(
            icon: Icons.battery_alert,
            label: 'סוללה קריטית',
            value: '$lowBattery',
            color: lowBattery == 0 ? Colors.green : Colors.red,
          ),
          _buildSummaryRow(
            icon: Icons.signal_cellular_off,
            label: 'ללא קליטה',
            value: '$noReception',
            color: noReception == 0 ? Colors.green : Colors.red,
          ),
          _buildSummaryRow(
            icon: Icons.map,
            label: 'מפות אופליין',
            value: '$mapsReady / $connected',
            color: mapsNotReady == 0 ? Colors.green : Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(label),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  /// לשונית נתונים — הורדת נתונים מהשרת
  Widget _buildDataTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // סטטוס
          Card(
            color: _isDataLoading
                ? Colors.blue[50]
                : _dataHasError
                    ? Colors.red[50]
                    : _dataLoadCompleted
                        ? Colors.green[50]
                        : Colors.grey[50],
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    _isDataLoading
                        ? Icons.cloud_download
                        : _dataHasError
                            ? Icons.error_outline
                            : _dataLoadCompleted
                                ? Icons.check_circle
                                : Icons.cloud_download_outlined,
                    size: 64,
                    color: _isDataLoading
                        ? Colors.blue
                        : _dataHasError
                            ? Colors.red
                            : _dataLoadCompleted
                                ? Colors.green
                                : Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isDataLoading
                        ? 'מוריד נתונים...'
                        : _dataHasError
                            ? 'שגיאה בהורדה'
                            : _dataLoadCompleted
                                ? 'הנתונים מוכנים'
                                : 'הכנה לניווט',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isDataLoading
                          ? Colors.blue
                          : _dataHasError
                              ? Colors.red
                              : _dataLoadCompleted
                                  ? Colors.green[800]
                                  : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // סרגל התקדמות
          if (_isDataLoading || _currentDataProgress != null) ...[
            _buildDataProgress(),
            const SizedBox(height: 16),
          ],

          // שלבי טעינה
          if (_currentDataProgress != null) _buildDataSteps(),

          // שגיאה
          if (_dataHasError && _dataFatalError != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_dataFatalError!, style: const TextStyle(color: Colors.red))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _startDataLoading(forceRefresh: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('נסה שוב'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // סנכרון אחרון
          if (_lastSyncTime != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'סנכרון אחרון: ${_formatSyncTime(_lastSyncTime!)}',
                        style: TextStyle(color: Colors.blue[700], fontSize: 13),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isDataLoading ? null : () => _startDataLoading(forceRefresh: true),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('רענן'),
                      style: TextButton.styleFrom(foregroundColor: Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // סיכום נתונים שנטענו
          if (_dataLoadCompleted && _loadedBundle != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storage, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Text(
                          'נתונים מוכנים לשימוש אופליין',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800], fontSize: 16),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildDataSummaryRow('גבול גזרה (GG)', _loadedBundle!.boundary != null ? 'נטען' : 'לא קיים', Icons.border_all),
                    _buildDataSummaryRow('נקודות ציון (NZ)', '${_loadedBundle!.checkpoints.length} נקודות', Icons.location_on),
                    _buildDataSummaryRow('נקודות בטיחות (NB)', '${_loadedBundle!.safetyPoints.length} נקודות', Icons.warning_amber),
                    _buildDataSummaryRow('ביצי איזור (BA)', '${_loadedBundle!.clusters.length} ביצים', Icons.hexagon_outlined),
                    _buildDataSummaryRow('צירים', '${_loadedBundle!.navigation.routes.length} צירים', Icons.route),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDataProgress() {
    final percent = _currentDataProgress?.progressPercent ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('התקדמות כללית', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${(percent * 100).toInt()}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 12,
            backgroundColor: Colors.grey[200],
          ),
        ),
      ],
    );
  }

  Widget _buildDataSteps() {
    final steps = _currentDataProgress!.steps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('שלבי טעינה', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...steps.map((step) {
              Widget leading;
              Color textColor;
              switch (step.status) {
                case LoadStepStatus.pending:
                  leading = Icon(Icons.radio_button_unchecked, color: Colors.grey[400], size: 24);
                  textColor = Colors.grey;
                  break;
                case LoadStepStatus.loading:
                  leading = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5));
                  textColor = Colors.blue;
                  break;
                case LoadStepStatus.completed:
                  leading = const Icon(Icons.check_circle, color: Colors.green, size: 24);
                  textColor = Colors.green;
                  break;
                case LoadStepStatus.failed:
                  leading = const Icon(Icons.error, color: Colors.red, size: 24);
                  textColor = Colors.red;
                  break;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.label, style: TextStyle(color: textColor)),
                          if (step.status == LoadStepStatus.completed && step.itemCount > 0)
                            Text('${step.itemCount} פריטים', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          if (step.status == LoadStepStatus.failed && step.errorMessage != null)
                            Text(step.errorMessage!, style: const TextStyle(fontSize: 12, color: Colors.red), maxLines: 2),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSummaryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.green[600]),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.grey[700])),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
        ],
      ),
    );
  }

  String _formatSyncTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'הרגע';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דקות';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    final d = dateTime.day.toString().padLeft(2, '0');
    final mo = dateTime.month.toString().padLeft(2, '0');
    final h = dateTime.hour.toString().padLeft(2, '0');
    final mi = dateTime.minute.toString().padLeft(2, '0');
    return '$d/$mo/${dateTime.year} $h:$mi';
  }

  /// תצוגה למנווט - בדיקת מערכות
  Widget _buildNavigatorView() {
    final isBatteryOk = _batteryLevel < 0 ? true : _batteryLevel >= _batteryRedThreshold;
    final isGpsOk = _hasGpsPermission && _hasLocationService;
    final isBgLocationOk = _hasBackgroundLocationPermission;
    final isGpsAccuracyOk = _gpsAccuracy < 0 || _gpsAccuracy <= 50.0;

    Color batteryColor() {
      if (_batteryLevel < 0) return Colors.grey;
      if (_batteryLevel < _batteryRedThreshold) return Colors.red;
      if (_batteryLevel < _batteryOrangeThreshold) return Colors.orange;
      return Colors.green;
    }

    String batteryText() {
      if (_batteryLevel < 0) return 'לא זמין';
      return '$_batteryLevel%';
    }

    return PopScope(
      canPop: true,
      onPopInvoked: (bool didPop) {
        // בדיקת המערכות תמשיך לרוץ ברקע — רק כפתור "סיום בדיקת מערכות" משנה סטטוס
      },
      child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.navigation.name),
            const Text(
              'בדיקת מערכות',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkNavigatorSystem,
            tooltip: 'רענן',
          ),
        ],
      ),
      body: _isCheckingSystem
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // סטטוס כללי
                  Builder(builder: (context) {
                    final isCellTowerFallback = isGpsOk && _gpsService.lastPositionSource == PositionSource.cellTower;
                    final allOk = isBatteryOk && isGpsOk && isBgLocationOk;
                    final cardColor = !allOk
                        ? Colors.red[50]
                        : isCellTowerFallback
                            ? Colors.orange[50]
                            : Colors.green[50];
                    final iconColor = !allOk
                        ? Colors.red
                        : isCellTowerFallback
                            ? Colors.orange
                            : Colors.green;
                    final textColor = !allOk
                        ? Colors.red[900]
                        : isCellTowerFallback
                            ? Colors.orange[900]
                            : Colors.green[900];
                    final statusText = !allOk
                        ? 'יש בעיות במערכת'
                        : isCellTowerFallback
                            ? 'מערכת חליפית תקינה'
                            : 'המערכת תקינה';

                    return Card(
                      color: cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              allOk ? Icons.check_circle : Icons.error,
                              size: 80,
                              color: iconColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              statusText,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // הרשאות מכשיר
                  if (_permissionStatuses.isNotEmpty)
                    _buildNavigatorPermissionsCard(),

                  const SizedBox(height: 24),

                  // בדיקת מיקום
                  Builder(builder: (context) {
                    final isCellTower = _gpsService.lastPositionSource == PositionSource.cellTower;
                    final gpsStatusText = !isGpsOk
                        ? 'לא תקין - בעיה במיקום'
                        : isCellTower
                            ? 'מערכת חליפית - מיקום מאנטנות סלולריות'
                            : 'תקין - המיקום פועל';
                    final gpsStatusColor = !isGpsOk
                        ? Colors.red[700]
                        : isCellTower
                            ? Colors.orange[700]
                            : Colors.green[700];
                    final gpsIconColor = !isGpsOk
                        ? Colors.red
                        : isCellTower
                            ? Colors.orange
                            : Colors.green;

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isGpsOk ? Icons.check_circle : Icons.error,
                          color: gpsIconColor,
                          size: 40,
                        ),
                        title: const Text('מיקום GPS'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gpsStatusText,
                              style: TextStyle(color: gpsStatusColor),
                            ),
                            if (isGpsOk && _gpsAccuracy > 0)
                              Text(
                                'דיוק: ${_gpsAccuracy.toStringAsFixed(0)} מטר',
                                style: TextStyle(
                                  color: isGpsAccuracyOk ? Colors.green[600] : Colors.orange[700],
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        trailing: !isGpsOk
                            ? ElevatedButton(
                                onPressed: _requestPermissions,
                                child: const Text('אשר הרשאות'),
                              )
                            : null,
                      ),
                    );
                  }),

                  if (!_hasGpsPermission)
                    Card(
                      color: Colors.orange[50],
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text('יש לאשר הרשאות מיקום לאפליקציה'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (!_hasLocationService)
                    Card(
                      color: Colors.orange[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('יש להפעיל שירותי מיקום במכשיר'),
                            ),
                            TextButton(
                              onPressed: () => _gpsService.openLocationSettings(),
                              child: const Text('הגדרות'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // בדיקת GPS ברקע
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _hasBackgroundLocationPermission
                            ? Icons.check_circle
                            : Icons.error,
                        color: _hasBackgroundLocationPermission
                            ? Colors.green
                            : Colors.orange,
                        size: 40,
                      ),
                      title: const Text('GPS ברקע'),
                      subtitle: Text(
                        _hasBackgroundLocationPermission
                            ? 'תקין - GPS יפעל גם כשהאפליקציה ברקע'
                            : 'לא מאושר - GPS לא יפעל ברקע',
                        style: TextStyle(
                          color: _hasBackgroundLocationPermission
                              ? Colors.green[700]
                              : Colors.orange[700],
                        ),
                      ),
                      trailing: !_hasBackgroundLocationPermission
                          ? ElevatedButton(
                              onPressed: () async {
                                final result = await Permission.locationAlways.request();
                                if (!result.isGranted && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('ההרשאה לא אושרה — יש לאשר "תמיד" בהגדרות המכשיר'),
                                      action: SnackBarAction(
                                        label: 'הגדרות',
                                        onPressed: openAppSettings,
                                      ),
                                    ),
                                  );
                                }
                                _hasBackgroundLocationPermission = (await Permission.locationAlways.status).isGranted;
                                if (mounted) setState(() {});
                              },
                              child: const Text('אשר'),
                            )
                          : null,
                    ),
                  ),

                  if (!_hasBackgroundLocationPermission)
                    Card(
                      color: Colors.orange[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.orange),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'ללא הרשאת מיקום ברקע, ה-GPS יפסיק לעבוד כשהמסך נכבה או כשעוברים לאפליקציה אחרת',
                              ),
                            ),
                            TextButton(
                              onPressed: openAppSettings,
                              child: const Text('הגדרות'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // בדיקת סוללה
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _batteryLevel < 0
                            ? Icons.battery_unknown
                            : isBatteryOk
                                ? Icons.check_circle
                                : Icons.error,
                        color: batteryColor(),
                        size: 40,
                      ),
                      title: const Text('סוללה'),
                      subtitle: Text(
                        _batteryLevel < 0
                            ? 'לא ניתן לקרוא את מצב הסוללה'
                            : isBatteryOk
                                ? 'תקינה - ${batteryText()} (מינימום: $_batteryRedThreshold%)'
                                : 'לא תקינה - ${batteryText()} (מינימום: $_batteryRedThreshold%)',
                        style: TextStyle(color: batteryColor()),
                      ),
                      trailing: Icon(
                        _batteryLevel < 0
                            ? Icons.battery_unknown
                            : _batteryLevel < _batteryRedThreshold
                                ? Icons.battery_alert
                                : _batteryLevel < _batteryOrangeThreshold
                                    ? Icons.battery_4_bar
                                    : Icons.battery_full,
                        color: batteryColor(),
                      ),
                    ),
                  ),

                  if (!isBatteryOk && _batteryLevel >= 0)
                    Card(
                      color: Colors.red[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'יש לטעון את הסוללה לפחות ל-$_batteryRedThreshold%',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // בדיקת מפות אופליין
                  _buildMapDownloadCard(),

                  const SizedBox(height: 32),

                  // כפתור אישור
                  if (isBatteryOk && isGpsOk && isBgLocationOk)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.check),
                        label: const Text('המערכת תקינה - המשך'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
                ),
                if (widget.navigation.communicationSettings.walkieTalkieEnabled && widget.currentUser != null)
                  Builder(builder: (context) {
                    _voiceService ??= VoiceService();
                    return VoiceMessagesPanel(
                      navigationId: widget.navigation.id,
                      currentUser: widget.currentUser!,
                      voiceService: _voiceService!,
                      isCommander: false,
                      enabled: true,
                    );
                  }),
              ],
            ),
      ),
    );
  }

  /// כרטיס סטטוס הורדת מפות אופליין
  Widget _buildMapDownloadCard() {
    IconData icon;
    Color color;
    String statusText;
    Widget? trailing;

    switch (_mapDownloadStatus) {
      case MapDownloadStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        statusText = 'מפות אופליין הורדו בהצלחה';
        break;
      case MapDownloadStatus.downloading:
        icon = Icons.cloud_download;
        color = Colors.blue;
        final pct = (_mapDownloadProgress * 100).toStringAsFixed(0);
        statusText = 'מוריד מפות אופליין... $pct%';
        trailing = SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            value: _mapDownloadProgress > 0 ? _mapDownloadProgress : null,
            strokeWidth: 3,
            color: Colors.blue,
          ),
        );
        break;
      case MapDownloadStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        statusText = 'הורדת מפות נכשלה';
        trailing = ElevatedButton(
          onPressed: _startManualMapDownload,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text('הורד שוב'),
        );
        break;
      case MapDownloadStatus.notStarted:
        icon = Icons.cloud_off;
        color = Colors.orange;
        statusText = 'מפות אופליין לא הורדו';
        trailing = ElevatedButton(
          onPressed: _startManualMapDownload,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text('הורד'),
        );
        break;
      case MapDownloadStatus.interrupted:
        icon = Icons.pause_circle_filled;
        color = Colors.orange;
        final pct = (_mapDownloadProgress * 100).toStringAsFixed(0);
        statusText = 'הורדת מפות הופסקה ($pct%) — ימשיך אוטומטית';
        trailing = SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            value: _mapDownloadProgress > 0 ? _mapDownloadProgress : null,
            strokeWidth: 3,
            color: Colors.orange,
          ),
        );
        break;
    }

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 40),
        title: const Text('מפות אופליין'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(statusText, style: TextStyle(color: color)),
            if (_mapDownloadStatus == MapDownloadStatus.downloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: _mapDownloadProgress > 0 ? _mapDownloadProgress : null,
                  color: Colors.blue,
                ),
              ),
          ],
        ),
        trailing: trailing,
      ),
    );
  }

  /// כרטיס הרשאות מכשיר — מוצג בתצוגת מנווט
  Widget _buildNavigatorPermissionsCard() {
    final missingPermissions = _permissionStatuses.entries
        .where((e) => !e.value.isGranted)
        .toList();

    if (missingPermissions.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.orange[50],
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.security, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'הרשאות חסרות',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...missingPermissions.map((entry) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.warning, color: Colors.orange, size: 20),
                title: Text(_permissionDisplayName(entry.key)),
                subtitle: Text(_permissionStatusText(entry.value)),
                trailing: entry.value.isPermanentlyDenied
                    ? TextButton(
                        onPressed: openAppSettings,
                        child: const Text('הגדרות'),
                      )
                    : TextButton(
                        onPressed: () => _requestPermission(_permissionFromKey(entry.key)),
                        child: const Text('אשר'),
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// טאב הרשאות למפקד — סקירת הרשאות כלליות
  Widget _buildPermissionsTab() {
    if (_isLoadingPermissions) {
      return const Center(child: CircularProgressIndicator());
    }

    final permissions = _commanderPermissions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'הרשאות מכשיר',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'הרשאות הנדרשות לפעולה תקינה של האפליקציה',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ...permissions.entries.map((entry) {
            final isGranted = entry.value.isGranted;
            final isPermanentlyDenied = entry.value.isPermanentlyDenied;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  isGranted ? Icons.check_circle : Icons.cancel,
                  color: isGranted ? Colors.green : Colors.red,
                ),
                title: Text(_permissionDisplayName(entry.key)),
                subtitle: Text(_permissionStatusText(entry.value)),
                trailing: isGranted
                    ? null
                    : isPermanentlyDenied
                        ? TextButton(
                            onPressed: openAppSettings,
                            child: const Text('הגדרות'),
                          )
                        : TextButton(
                            onPressed: () async {
                              final permission = _permissionFromKey(entry.key);
                              final result = await permission.request();
                              if (mounted) {
                                setState(() {
                                  _commanderPermissions[entry.key] = result;
                                });
                                // אם עדיין לא אושר — הצע לפתוח הגדרות
                                if (!result.isGranted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('ההרשאה לא אושרה — ניתן לאשר בהגדרות המכשיר'),
                                      action: SnackBarAction(
                                        label: 'הגדרות',
                                        onPressed: openAppSettings,
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('אשר'),
                          ),
              ),
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loadCommanderPermissions,
              icon: const Icon(Icons.refresh),
              label: const Text('רענן הרשאות'),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, PermissionStatus>> _getAllPermissions() async {
    return {
      'location': await Permission.location.status,
      'locationAlways': await Permission.locationAlways.status,
      'notification': await Permission.notification.status,
      'microphone': await Permission.microphone.status,
      'phone': await Permission.phone.status,
      'sms': await Permission.sms.status,
    };
  }

  String _permissionDisplayName(String key) {
    switch (key) {
      case 'location':
        return 'מיקום (GPS)';
      case 'locationAlways':
        return 'מיקום ברקע';
      case 'notification':
        return 'התראות';
      case 'microphone':
        return 'מיקרופון';
      case 'phone':
        return 'טלפון';
      case 'sms':
        return 'SMS';
      default:
        return key;
    }
  }

  String _permissionStatusText(PermissionStatus status) {
    if (status.isGranted) return 'מאושר';
    if (status.isPermanentlyDenied) return 'נחסם - יש לאשר בהגדרות';
    if (status.isDenied) return 'לא אושר';
    if (status.isRestricted) return 'מוגבל';
    return 'לא ידוע';
  }

  Permission _permissionFromKey(String key) {
    switch (key) {
      case 'location':
        return Permission.location;
      case 'locationAlways':
        return Permission.locationAlways;
      case 'notification':
        return Permission.notification;
      case 'microphone':
        return Permission.microphone;
      case 'phone':
        return Permission.phone;
      case 'sms':
        return Permission.sms;
      default:
        return Permission.location;
    }
  }
}

/// סטטוס מנווט
class NavigatorStatus {
  final bool isConnected;
  final bool hasReported; // האם המנווט דיווח ל-Firestore (להבדיל מ-placeholder)
  final int batteryLevel; // 0-100
  final bool hasGPS;
  final int receptionLevel; // 0-4 (0=אין, 4=מצוין)
  final double? latitude;
  final double? longitude;
  final String positionSource; // 'gps', 'cellTower', or 'none'
  final DateTime? positionUpdatedAt; // מתי עודכן המיקום לאחרונה
  final double gpsAccuracy; // -1 = לא ידוע
  final String mapsStatus; // 'notStarted', 'downloading', 'completed', 'failed'
  final bool hasMicrophonePermission;
  final bool hasPhonePermission;

  NavigatorStatus({
    required this.isConnected,
    this.hasReported = false,
    required this.batteryLevel,
    required this.hasGPS,
    this.receptionLevel = 0,
    this.latitude,
    this.longitude,
    this.positionSource = 'gps',
    this.positionUpdatedAt,
    this.gpsAccuracy = -1,
    this.mapsStatus = 'notStarted',
    this.hasMicrophonePermission = false,
    this.hasPhonePermission = false,
  });

  bool get mapsReady => mapsStatus == 'completed';
}
