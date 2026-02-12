import 'dart:async';
import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;
import '../../../domain/entities/user.dart';
import '../../../services/navigation_data_loader.dart';

/// מסך טעינת נתוני ניווט לעבודה אופליין
///
/// מציג את התקדמות הורדת הנתונים מהשרת ושמירתם מקומית.
/// מבדיל בין מנווט (טוען רק נתונים רלוונטיים) למפקד (טוען הכל).
class DataLoadingScreen extends StatefulWidget {
  final domain.Navigation navigation;
  final User currentUser;
  final bool isCommander;
  final VoidCallback? onLoadingComplete;

  const DataLoadingScreen({
    super.key,
    required this.navigation,
    required this.currentUser,
    required this.isCommander,
    this.onLoadingComplete,
  });

  @override
  State<DataLoadingScreen> createState() => _DataLoadingScreenState();
}

class _DataLoadingScreenState extends State<DataLoadingScreen>
    with SingleTickerProviderStateMixin {
  late NavigationDataLoader _dataLoader;
  StreamSubscription<LoadProgress>? _progressSubscription;

  LoadProgress? _currentProgress;
  NavigationDataBundle? _loadedBundle;
  bool _isLoading = false;
  bool _loadCompleted = false;
  bool _hasError = false;
  String? _fatalError;
  DateTime? _lastSyncTime;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _dataLoader = NavigationDataLoader();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _checkCacheAndLoad();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _dataLoader.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// בדיקת cache ראשונית וטעינה
  Future<void> _checkCacheAndLoad() async {
    // בדיקה אם הנתונים כבר שמורים
    final isCached =
        await _dataLoader.isDataCachedLocally(widget.navigation.id);
    final lastSync =
        await _dataLoader.getLastSyncTimestamp(widget.navigation.id);

    if (mounted) {
      setState(() {
        _lastSyncTime = lastSync;
      });
    }

    if (isCached && lastSync != null) {
      // נתונים קיימים - נשאל אם להשתמש ב-cache או לרענן
      if (mounted) {
        setState(() {
          _loadCompleted = true;
        });
      }
    } else {
      // אין נתונים - מתחילים טעינה
      await _startLoading(forceRefresh: false);
    }
  }

  /// התחלת טעינת נתונים
  Future<void> _startLoading({bool forceRefresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _fatalError = null;
      _loadCompleted = false;
      _currentProgress = null;
    });

    // האזנה לעדכוני התקדמות
    _progressSubscription?.cancel();
    _progressSubscription = _dataLoader.progressStream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            _currentProgress = progress;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _fatalError = error.toString();
          });
        }
      },
    );

    try {
      NavigationDataBundle? bundle;

      if (widget.isCommander) {
        bundle = await _dataLoader.loadCommanderData(
          navigationId: widget.navigation.id,
          forceRefresh: forceRefresh,
        );
      } else {
        bundle = await _dataLoader.loadNavigatorData(
          navigationId: widget.navigation.id,
          navigatorUid: widget.currentUser.uid,
          forceRefresh: forceRefresh,
        );
      }

      if (mounted) {
        final lastSync =
            await _dataLoader.getLastSyncTimestamp(widget.navigation.id);
        setState(() {
          _loadedBundle = bundle;
          _isLoading = false;
          _loadCompleted = bundle != null;
          _hasError = bundle == null;
          _lastSyncTime = lastSync;
          if (bundle == null) {
            _fatalError = 'לא ניתן לטעון את נתוני הניווט';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _fatalError = 'שגיאה בטעינת נתונים: $e';
        });
      }
    }
  }

  /// המשך למסך הבא
  void _navigateNext() {
    widget.onLoadingComplete?.call();
    if (widget.onLoadingComplete == null) {
      Navigator.pop(context, _loadedBundle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.navigation.name),
              Text(
                widget.isCommander
                    ? 'הורדת נתונים - מפקד'
                    : 'הורדת נתונים - מנווט',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: _buildBody(),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // כותרת וסטטוס
          _buildStatusHeader(),
          const SizedBox(height: 24),

          // סרגל התקדמות כללי
          if (_isLoading || _currentProgress != null) ...[
            _buildOverallProgress(),
            const SizedBox(height: 24),
          ],

          // שלבי טעינה
          if (_currentProgress != null) _buildStepsList(),

          // שגיאה חמורה
          if (_hasError && _fatalError != null) ...[
            const SizedBox(height: 16),
            _buildErrorCard(),
          ],

          // הודעת סנכרון אחרון
          if (_lastSyncTime != null) ...[
            const SizedBox(height: 16),
            _buildLastSyncInfo(),
          ],

          // סיכום (אם הטעינה הושלמה)
          if (_loadCompleted && _loadedBundle != null) ...[
            const SizedBox(height: 16),
            _buildSummaryCard(),
          ],
        ],
      ),
    );
  }

  /// כותרת סטטוס
  Widget _buildStatusHeader() {
    IconData icon;
    Color color;
    String title;
    String subtitle;

    if (_isLoading) {
      icon = Icons.cloud_download;
      color = Theme.of(context).primaryColor;
      title = 'מוריד נתונים...';
      subtitle = 'אנא המתן, מוריד את נתוני הניווט מהשרת';
    } else if (_hasError) {
      icon = Icons.error_outline;
      color = Colors.red;
      title = 'שגיאה בהורדה';
      subtitle = 'חלק מהנתונים לא נטענו. ניתן לנסות שוב.';
    } else if (_loadCompleted) {
      icon = Icons.check_circle;
      color = Colors.green;
      title = 'הנתונים מוכנים';
      subtitle = widget.isCommander
          ? 'כל נתוני הניווט הורדו בהצלחה'
          : 'נתוני הניווט שלך הורדו בהצלחה';
    } else {
      icon = Icons.cloud_download_outlined;
      color = Colors.grey;
      title = 'הכנה לניווט';
      subtitle = 'טוען את הנתונים הנדרשים';
    }

    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _isLoading
                ? AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: 0.5 + 0.5 * _pulseController.value,
                        child: Icon(icon, size: 64, color: color),
                      );
                    },
                  )
                : Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// סרגל התקדמות כללי
  Widget _buildOverallProgress() {
    final percent = _currentProgress?.progressPercent ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'התקדמות כללית',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '${(percent * 100).toInt()}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 12,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              _hasError ? Colors.orange : Theme.of(context).primaryColor,
            ),
          ),
        ),
        if (_currentProgress?.currentStep != null) ...[
          const SizedBox(height: 8),
          Text(
            _currentProgress!.currentStep!.label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  /// רשימת שלבי טעינה
  Widget _buildStepsList() {
    final steps = _currentProgress!.steps;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'שלבי טעינה',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...steps.map((step) => _buildStepTile(step)),
          ],
        ),
      ),
    );
  }

  /// שורת שלב טעינה בודד
  Widget _buildStepTile(LoadStep step) {
    Widget leading;
    Color textColor;

    switch (step.status) {
      case LoadStepStatus.pending:
        leading = Icon(Icons.radio_button_unchecked,
            color: Colors.grey[400], size: 24);
        textColor = Colors.grey;
        break;
      case LoadStepStatus.loading:
        leading = const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
        textColor = Theme.of(context).primaryColor;
        break;
      case LoadStepStatus.completed:
        leading = const Icon(Icons.check_circle, color: Colors.green, size: 24);
        textColor = Colors.green[800]!;
        break;
      case LoadStepStatus.failed:
        leading = const Icon(Icons.error, color: Colors.red, size: 24);
        textColor = Colors.red;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: step.status == LoadStepStatus.loading
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (step.status == LoadStepStatus.completed &&
                    step.itemCount > 0)
                  Text(
                    '${step.itemCount} פריטים',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                if (step.status == LoadStepStatus.failed &&
                    step.errorMessage != null)
                  Text(
                    step.errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// כרטיס שגיאה
  Widget _buildErrorCard() {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _fatalError ?? 'אירעה שגיאה',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _startLoading(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('נסה שוב'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// מידע על סנכרון אחרון
  Widget _buildLastSyncInfo() {
    final formattedTime = _formatDateTime(_lastSyncTime!);

    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.access_time, color: Colors.blue[700], size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'סנכרון אחרון: $formattedTime',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontSize: 13,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _startLoading(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('רענן'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue[700],
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// סיכום הנתונים שנטענו
  Widget _buildSummaryCard() {
    final bundle = _loadedBundle!;

    return Card(
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Divider(),
            _buildSummaryRow(
              'גבול גזרה (GG)',
              bundle.boundary != null ? 'נטען' : 'לא קיים',
              Icons.border_all,
            ),
            _buildSummaryRow(
              'נקודות ציון (NZ)',
              '${bundle.checkpoints.length} נקודות',
              Icons.location_on,
            ),
            _buildSummaryRow(
              'נקודות בטיחות (NB)',
              '${bundle.safetyPoints.length} נקודות',
              Icons.warning_amber,
            ),
            _buildSummaryRow(
              'ביצי איזור (BA)',
              '${bundle.clusters.length} ביצים',
              Icons.hexagon_outlined,
            ),
            if (widget.isCommander) ...[
              _buildSummaryRow(
                'צירים',
                '${bundle.navigation.routes.length} צירים',
                Icons.route,
              ),
              if (bundle.navigatorTree != null)
                _buildSummaryRow(
                  'עץ מנווטים',
                  bundle.navigatorTree!.name,
                  Icons.account_tree,
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// שורת סיכום בודדת
  Widget _buildSummaryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.green[600]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: Colors.grey[700]),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
            ),
          ),
        ],
      ),
    );
  }

  /// בר תחתון
  Widget _buildBottomBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // כפתור חזרה
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('חזור'),
              ),
            ),
            const SizedBox(width: 12),
            // כפתור המשך (רק אם הטעינה הושלמה)
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _loadCompleted ? _navigateNext : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('המשך לניווט'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// פורמט תאריך ושעה
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'הרגע';
    } else if (diff.inMinutes < 60) {
      return 'לפני ${diff.inMinutes} דקות';
    } else if (diff.inHours < 24) {
      return 'לפני ${diff.inHours} שעות';
    } else {
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$day/$month/${dateTime.year} $hour:$minute';
    }
  }
}
