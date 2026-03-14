import 'dart:async';

/// A generic ref-counted stream wrapper for Firestore listeners.
///
/// Shares a single underlying Firestore listener among multiple subscribers,
/// replays the last value to new subscribers, and includes a polling fallback
/// for environments where snapshots() may not fire reliably (e.g. Windows).
class RefCountedStream<T> {
  RefCountedStream({
    required Stream<T> Function() sourceFactory,
    Future<T> Function()? pollFallback,
    Duration gracePeriod = const Duration(seconds: 5),
    Duration pollStaleThreshold = const Duration(seconds: 30),
  })  : _sourceFactory = sourceFactory,
        _pollFallback = pollFallback,
        _gracePeriod = gracePeriod,
        _pollStaleThreshold = pollStaleThreshold;

  final Stream<T> Function() _sourceFactory;
  final Future<T> Function()? _pollFallback;
  final Duration _gracePeriod;
  final Duration _pollStaleThreshold;

  StreamController<T>? _controller;
  StreamSubscription<T>? _sourceSubscription;
  Timer? _graceTimer;
  Timer? _pollTimer;

  int _refCount = 0;
  T? _lastValue;
  DateTime? _lastUpdateTime;
  bool _disposed = false;

  /// The last emitted value, or null if no value has been received yet.
  T? get lastValue => _lastValue;

  /// Whether the stream is currently active (has subscribers).
  bool get isActive => _refCount > 0;

  /// Returns a broadcast stream that manages ref counting.
  ///
  /// First subscriber starts the underlying Firestore listener.
  /// Each new subscriber gets the last value immediately (replay).
  /// When the last subscriber cancels, a grace period starts before cleanup.
  Stream<T> get stream {
    _ensureController();
    final controller = _controller!;

    // We wrap the broadcast stream so we can track subscribe/unsubscribe.
    late StreamController<T> perSubscriber;
    perSubscriber = StreamController<T>(
      onListen: () {
        _graceTimer?.cancel();
        _graceTimer = null;
        _refCount++;

        if (_refCount == 1) {
          _startSource();
        }

        // Replay last value to new subscriber.
        if (_lastValue != null) {
          perSubscriber.add(_lastValue as T);
        }
      },
      onCancel: () {
        _refCount--;
        perSubscriber.close();

        if (_refCount <= 0) {
          _refCount = 0;
          _graceTimer?.cancel();
          _graceTimer = Timer(_gracePeriod, () {
            if (_refCount == 0) {
              _stopSource();
            }
          });
        }
      },
    );

    // Forward events from the shared broadcast to the per-subscriber controller.
    final sub = controller.stream.listen(
      perSubscriber.add,
      onError: perSubscriber.addError,
    );
    perSubscriber.onCancel = () {
      sub.cancel();
      _refCount--;
      if (_refCount <= 0) {
        _refCount = 0;
        _graceTimer?.cancel();
        _graceTimer = Timer(_gracePeriod, () {
          if (_refCount == 0) {
            _stopSource();
          }
        });
      }
    };

    return perSubscriber.stream;
  }

  /// Triggers an immediate poll (calls pollFallback if available).
  void forceRefresh() {
    _doPoll();
  }

  /// Permanently disposes this ref-counted stream.
  void dispose() {
    _disposed = true;
    _graceTimer?.cancel();
    _graceTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _sourceSubscription?.cancel();
    _sourceSubscription = null;
    _controller?.close();
    _controller = null;
    _refCount = 0;
  }

  void _ensureController() {
    if (_disposed) return;
    _controller ??= StreamController<T>.broadcast();
  }

  void _startSource() {
    if (_disposed) return;
    _sourceSubscription?.cancel();

    _sourceSubscription = _sourceFactory().listen(
      (data) {
        _lastValue = data;
        _lastUpdateTime = DateTime.now();
        _controller?.add(data);
      },
      onError: (Object error, StackTrace stack) {
        _controller?.addError(error, stack);
      },
    );

    // Start poll timer.
    _startPollTimer();
  }

  void _stopSource() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _sourceSubscription?.cancel();
    _sourceSubscription = null;
    // Keep _lastValue and _controller alive for potential re-subscribe.
  }

  void _startPollTimer() {
    if (_pollFallback == null) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkAndPoll();
    });
  }

  void _checkAndPoll() {
    if (_disposed || _refCount == 0) return;
    if (_pollFallback == null) return;

    final lastUpdate = _lastUpdateTime;
    if (lastUpdate == null ||
        DateTime.now().difference(lastUpdate) > _pollStaleThreshold) {
      _doPoll();
    }
  }

  Future<void> _doPoll() async {
    if (_disposed || _pollFallback == null) return;
    try {
      final data = await _pollFallback!();
      if (_disposed) return;
      _lastValue = data;
      _lastUpdateTime = DateTime.now();
      _controller?.add(data);
    } catch (_) {
      // Polling failure is non-fatal — the listener may still be active.
    }
  }
}
