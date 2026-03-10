import 'package:flutter/material.dart';

/// Wraps a widget in MaterialApp with RTL directionality for testing.
Widget buildTestWidget(Widget child) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
}
