import 'package:flutter/material.dart';
import '../../../domain/entities/navigation.dart' as domain;

/// מסך המתנה לתחילת ניווט
class WaitingScreen extends StatelessWidget {
  final domain.Navigation navigation;

  const WaitingScreen({
    super.key,
    required this.navigation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(navigation.name),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 100,
              color: Colors.cyan[700],
            ),
            const SizedBox(height: 32),
            Text(
              'ממתין להתחיל ניווט',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.cyan[900],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'הניווט יתחיל ברגע שהמפקד יאשר את ההתחלה',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[700],
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
