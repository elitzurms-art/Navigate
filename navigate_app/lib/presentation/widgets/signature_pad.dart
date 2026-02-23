import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// לוח חתימה דיגיטלית
class SignaturePad extends StatefulWidget {
  final String? initialBase64;
  final ValueChanged<String?> onChanged;
  final double height;
  final Color penColor;
  final double penWidth;

  const SignaturePad({
    super.key,
    this.initialBase64,
    required this.onChanged,
    this.height = 150,
    this.penColor = Colors.black,
    this.penWidth = 2.0,
  });

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  bool _hasSignature = false;

  @override
  void initState() {
    super.initState();
    _hasSignature = widget.initialBase64 != null && widget.initialBase64!.isNotEmpty;
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _hasSignature = false;
    });
    widget.onChanged(null);
  }

  Future<void> _exportSignature() async {
    if (_strokes.isEmpty) {
      widget.onChanged(null);
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = widget.penColor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = widget.penWidth
      ..style = PaintingStyle.stroke;

    // Draw white background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 300, widget.height),
      Paint()..color = Colors.white,
    );

    for (final stroke in _strokes) {
      if (stroke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, stroke, paint);
      } else {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (int i = 1; i < stroke.length; i++) {
          path.lineTo(stroke[i].dx, stroke[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(300, widget.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData != null) {
      final base64 = base64Encode(byteData.buffer.asUint8List());
      widget.onChanged(base64);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show existing signature as image
    if (_hasSignature && _strokes.isEmpty && widget.initialBase64 != null) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Stack(
          children: [
            Center(
              child: Image.memory(
                base64Decode(widget.initialBase64!),
                height: widget.height - 20,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text('חתימה שמורה'),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () {
                  setState(() => _hasSignature = false);
                },
                tooltip: 'ערוך חתימה',
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Stack(
        children: [
          GestureDetector(
            onPanStart: (details) {
              setState(() {
                _currentStroke = [details.localPosition];
                _strokes.add(_currentStroke);
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _currentStroke.add(details.localPosition);
              });
            },
            onPanEnd: (details) {
              _exportSignature();
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: _SignaturePainter(
                strokes: _strokes,
                penColor: widget.penColor,
                penWidth: widget.penWidth,
              ),
            ),
          ),
          if (_strokes.isEmpty)
            const Center(
              child: Text(
                'חתום כאן',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          if (_strokes.isNotEmpty)
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                onPressed: _clear,
                tooltip: 'נקה חתימה',
              ),
            ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color penColor;
  final double penWidth;

  _SignaturePainter({
    required this.strokes,
    required this.penColor,
    required this.penWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = penColor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = penWidth
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawPoints(ui.PointMode.points, stroke, paint);
      } else {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (int i = 1; i < stroke.length; i++) {
          path.lineTo(stroke[i].dx, stroke[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
