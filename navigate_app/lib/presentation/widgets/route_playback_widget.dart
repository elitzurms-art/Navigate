import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../services/gps_tracking_service.dart';

/// ווידג'ט הפעלה חוזרת של מסלול — אנימציית מעקב GPS
class RoutePlaybackWidget extends StatefulWidget {
  final List<TrackPoint> trackPoints;
  final ValueChanged<LatLng>? onPositionChanged;
  final ValueChanged<int>? onIndexChanged;

  const RoutePlaybackWidget({
    super.key,
    required this.trackPoints,
    this.onPositionChanged,
    this.onIndexChanged,
  });

  @override
  State<RoutePlaybackWidget> createState() => _RoutePlaybackWidgetState();
}

class _RoutePlaybackWidgetState extends State<RoutePlaybackWidget> {
  Timer? _timer;
  int _currentIndex = 0;
  bool _isPlaying = false;
  double _speed = 1.0; // מכפיל מהירות

  static const _speeds = [0.5, 1.0, 2.0, 5.0, 10.0];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    if (widget.trackPoints.length < 2) return;
    setState(() => _isPlaying = true);
    _scheduleNext();
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _isPlaying = false;
      _currentIndex = 0;
    });
    _notifyPosition();
  }

  void _scheduleNext() {
    if (_currentIndex >= widget.trackPoints.length - 1) {
      setState(() => _isPlaying = false);
      return;
    }

    final current = widget.trackPoints[_currentIndex];
    final next = widget.trackPoints[_currentIndex + 1];
    final interval = next.timestamp.difference(current.timestamp);
    final scaledMs = (interval.inMilliseconds / _speed).round().clamp(16, 2000);

    _timer = Timer(Duration(milliseconds: scaledMs), () {
      if (!mounted) return;
      setState(() => _currentIndex++);
      _notifyPosition();
      if (_isPlaying) _scheduleNext();
    });
  }

  void _notifyPosition() {
    if (_currentIndex >= widget.trackPoints.length) return;
    final tp = widget.trackPoints[_currentIndex];
    widget.onPositionChanged?.call(LatLng(tp.coordinate.lat, tp.coordinate.lng));
    widget.onIndexChanged?.call(_currentIndex);
  }

  void _seekTo(double value) {
    final idx = value.round().clamp(0, widget.trackPoints.length - 1);
    setState(() => _currentIndex = idx);
    _notifyPosition();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.trackPoints;
    if (points.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(child: Text('אין נתוני מסלול', style: TextStyle(color: Colors.grey))),
      );
    }

    final current = _currentIndex < points.length ? points[_currentIndex] : points.last;
    final progress = points.length > 1
        ? _currentIndex / (points.length - 1)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // פס התקדמות
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Theme.of(context).primaryColor,
              inactiveTrackColor: Colors.grey[300],
              thumbColor: Theme.of(context).primaryColor,
            ),
            child: Slider(
              value: _currentIndex.toDouble(),
              min: 0,
              max: (points.length - 1).toDouble(),
              onChanged: _seekTo,
            ),
          ),

          // פקדים
          Row(
            children: [
              // זמן נוכחי
              Text(
                _formatTime(current.timestamp),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),

              const Spacer(),

              // כפתורי שליטה
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 22),
                onPressed: _stop,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 28,
                  color: Theme.of(context).primaryColor,
                ),
                onPressed: _isPlaying ? _pause : _play,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),

              const Spacer(),

              // מהירות
              GestureDetector(
                onTap: () {
                  final idx = _speeds.indexOf(_speed);
                  final next = (idx + 1) % _speeds.length;
                  setState(() => _speed = _speeds[next]);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_speed}x',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // מידע
              Text(
                '${current.speed?.toStringAsFixed(1) ?? '-'} קמ"ש',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),

          // מד התקדמות
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: Colors.grey[200],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
