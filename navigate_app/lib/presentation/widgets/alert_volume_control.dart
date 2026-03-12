import 'package:flutter/material.dart';

/// פקד עוצמת צליל התראה — אייקון + סלידר
class AlertVolumeControl extends StatefulWidget {
  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final String? tooltip;

  const AlertVolumeControl({
    super.key,
    required this.volume,
    required this.onVolumeChanged,
    this.tooltip,
  });

  @override
  State<AlertVolumeControl> createState() => _AlertVolumeControlState();
}

class _AlertVolumeControlState extends State<AlertVolumeControl> {
  double? _lastNonZeroVolume;

  void _toggleMute() {
    if (widget.volume > 0) {
      _lastNonZeroVolume = widget.volume;
      widget.onVolumeChanged(0);
    } else {
      widget.onVolumeChanged(_lastNonZeroVolume ?? 1.0);
    }
  }

  IconData _iconForVolume(double v) {
    if (v == 0) return Icons.volume_off;
    if (v < 0.4) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    final vol = widget.volume;
    final isMuted = vol == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _iconForVolume(vol),
            size: 20,
            color: isMuted ? Colors.grey : null,
          ),
          tooltip: widget.tooltip ?? (isMuted ? 'הפעל צליל' : 'כבה צליל'),
          onPressed: _toggleMute,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        SizedBox(
          width: 90,
          child: Slider(
            value: vol,
            min: 0,
            max: 1,
            divisions: 4,
            onChanged: (v) {
              if (v > 0) _lastNonZeroVolume = v;
              widget.onVolumeChanged(v);
            },
          ),
        ),
      ],
    );
  }
}
